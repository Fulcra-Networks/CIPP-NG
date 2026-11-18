# Pester tests for the IronScales extension (Fulcra migration plan 02).
# The sync follows IronScales company -> tenant (IronScalesMapping) -> Autotask company (AutotaskMapping)
# and raises one ticket per company, unless one is still open for that company (O-02-3). The fork's
# body builder repeated incidents and its token helper returned $null on failure; both are pinned here.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Get-ExtensionMapping { param($Extension) }
    function Get-ExtensionAPIKey { param($Extension) }
    function Get-AutotaskToken { param($Configuration, [switch]$Force) }
    function Get-AutotaskAPIResource { [CmdletBinding()] param($Resource, $ID, $SearchQuery) }
    function New-AutotaskTicket { param($atCompanyId, $title, $description, $estHr, $issueType, $subIssueType, $priority, $Configuration) }
    function Get-NormalizedError { param($Message) $Message }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }

    foreach ($File in 'Get-IronScalesToken', 'Invoke-IronScalesRequest', 'Get-IronScalesCompany', 'Get-IronScalesIncident', 'Get-IronScalesTicketBody', 'Invoke-IronScalesTicketSync') {
        . (Join-Path $BackendRoot "Modules/CippExtensions/Public/IronScales/$File.ps1")
    }
    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/Autotask/ConvertTo-AutotaskText.ps1')

    $script:Config = [pscustomobject]@{
        IronScales = [pscustomobject]@{ Enabled = $true; ApiHost = 'https://appapi.ironscales.com/appapi/' }
        Autotask   = [pscustomobject]@{ Enabled = $true; APIUser = 'api@fulcra.example' }
    }
    function New-Incident {
        param($Subject = 'Pay now')
        [pscustomobject]@{ emailSubject = $Subject; senderEmail = 'bad@evil.example'; senderName = 'Bad'; recipientEmail = 'user@contoso.com'; affectedMailboxesCount = 2; reportedBy = 'user@contoso.com' }
    }
}

Describe 'Get-IronScalesToken' {
    BeforeEach {
        Mock Get-ExtensionAPIKey { 'partner-key' }
        Mock Write-LogMessage {}
    }

    It 'posts the key to <ApiHost>/get-token/ and returns the jwt' {
        Mock Invoke-RestMethod { $script:Call = @{ Uri = $Uri; Body = $Body }; [pscustomobject]@{ jwt = 'token-1' } }
        Get-IronScalesToken -Configuration $script:Config.IronScales | Should -Be 'token-1'
        $script:Call.Uri | Should -Be 'https://appapi.ironscales.com/appapi/get-token/'
        ($script:Call.Body | ConvertFrom-Json).scopes | Should -Be 'partner.all'
    }

    It 'throws instead of returning nothing when the API rejects the key' {
        Mock Invoke-RestMethod { throw 'Unauthorized' }
        { Get-IronScalesToken -Configuration $script:Config.IronScales } | Should -Throw 'IronScales authentication failed: Unauthorized'
    }

    It 'throws when no key is stored' {
        Mock Get-ExtensionAPIKey { $null }
        { Get-IronScalesToken -Configuration $script:Config.IronScales } | Should -Throw '*API key not found*'
    }
}

Describe 'Get-IronScalesIncident' {
    It 'asks for unclassified incidents from the last 7 days by default' {
        Mock Invoke-RestMethod { $script:Uri = $Uri; [pscustomobject]@{ incidents = @((New-Incident), (New-Incident)) } }
        $Result = Get-IronScalesIncident -Configuration $script:Config.IronScales -Token 't' -CompanyId '42'
        $script:Uri | Should -Be 'https://appapi.ironscales.com/appapi/incident/42/list/?period=1&state=unclassified'
        $Result.Count | Should -Be 2
    }

    It 'returns an empty list when there are none' {
        Mock Invoke-RestMethod { [pscustomobject]@{ incidents = @() } }
        @(Get-IronScalesIncident -Configuration $script:Config.IronScales -Token 't' -CompanyId '42').Count | Should -Be 0
    }
}

Describe 'Get-IronScalesTicketBody' {
    It 'lists each incident once, then the classification link' {
        $Html = Get-IronScalesTicketBody -CompanyName 'Contoso' -Incidents @((New-Incident -Subject 'One'), (New-Incident -Subject 'Two'))
        $Text = ConvertTo-AutotaskText -Html $Html

        ([regex]::Matches($Text, 'Email Subject:')).Count | Should -Be 2
        $Text | Should -Match '^2 unclassified IronScales incidents for Contoso\.'
        $Text | Should -Match "Email Subject: One`nEmail Sender Address: bad@evil.example`nEmail Sender Name: Bad`nEmail Recipient: user@contoso.com`nAffected Mailboxes: 2`nReported By: user@contoso.com"
        $Text | Should -Match 'To classify the incident\(s\) go to https://members\.ironscales\.com/irontraps/incidents/unclassified$'
    }

    It 'keeps angle brackets in subjects and strips curly quotes' {
        $Text = ConvertTo-AutotaskText -Html (Get-IronScalesTicketBody -CompanyName 'A & B' -Incidents @(New-Incident -Subject "Invoice <INV-1> $([char]0x201C)urgent$([char]0x201D)"))
        $Text | Should -Match 'Email Subject: Invoice <INV-1> urgent'
        $Text | Should -Match 'incident for A & B\.'
    }
}

Describe 'Invoke-IronScalesTicketSync' {
    BeforeEach {
        $script:Tickets = [System.Collections.Generic.List[object]]::new()
        $script:Queries = [System.Collections.Generic.List[string]]::new()
        Mock Write-LogMessage {}
        Mock Get-ExtensionAPIKey { 'partner-key' }
        Mock Get-AutotaskToken {}
        Mock Invoke-RestMethod {
            if ($Uri -like '*get-token*') { return [pscustomobject]@{ jwt = 'jwt' } }
            if ($Uri -like '*company/list*') { return [pscustomobject]@{ companies = @([pscustomobject]@{ id = 11; name = 'Contoso' }, [pscustomobject]@{ id = 22; name = 'Fabrikam' }, [pscustomobject]@{ id = 33; name = 'Quiet' }) } }
            if ($Uri -like '*incident/11/*') { return [pscustomobject]@{ incidents = @((New-Incident), (New-Incident)) } }
            if ($Uri -like '*incident/22/*') { return [pscustomobject]@{ incidents = @(New-Incident) } }
            [pscustomobject]@{ incidents = @() }
        }
        Mock Get-ExtensionMapping {
            if ($Extension -eq 'IronScales') { @([pscustomobject]@{ RowKey = 'tenant-a'; IntegrationId = '11' }) }
            else { @([pscustomobject]@{ RowKey = 'tenant-a'; IntegrationId = '123' }) }
        }
        Mock Get-AutotaskAPIResource { $script:Queries.Add($SearchQuery); $null }
        Mock New-AutotaskTicket {
            $script:Tickets.Add([pscustomobject]@{ Company = $atCompanyId; Title = $title; Description = $description; EstHr = $estHr; Issue = $issueType; SubIssue = $subIssueType; Priority = $priority; Configuration = $Configuration })
            'Created Autotask ticket T1 (id 1)'
        }
    }

    It 'raises one High / Email Security ticket for the mapped company with incidents' {
        $Summary = Invoke-IronScalesTicketSync -Configuration $script:Config

        $script:Tickets.Count | Should -Be 1
        $T = $script:Tickets[0]
        $T.Company | Should -Be '123'
        $T.Title | Should -Be '[IronScales] New Incident(s) for Contoso'
        $T.Priority | Should -Be '1'
        $T.Issue | Should -Be '29'
        $T.SubIssue | Should -Be '323'
        $T.EstHr | Should -Be 0.2
        $T.Configuration.APIUser | Should -Be 'api@fulcra.example'
        $Summary.Created | Should -Be 1
        $Summary.WithIncidents | Should -Be 2
        $Summary.Unmapped | Should -Be @('Fabrikam')
    }

    It 'checks for an open ticket by title, Autotask company and open statuses' {
        Invoke-IronScalesTicketSync -Configuration $script:Config | Out-Null

        $Items = ($script:Queries[0] | ConvertFrom-Json).filter[0].items
        ($Items | Where-Object field -EQ 'title').value | Should -Be '[IronScales] New Incident(s) for Contoso'
        ($Items | Where-Object field -EQ 'companyID').value | Should -Be 123
        ($Items | Where-Object field -EQ 'status').value | Should -Be @(1, 7, 8, 12)
    }

    It 'creates nothing while a ticket is still open' {
        Mock Get-AutotaskAPIResource { [pscustomobject]@{ id = 9 } }
        $Summary = Invoke-IronScalesTicketSync -Configuration $script:Config
        Should -Invoke New-AutotaskTicket -Times 0
        $Summary.AlreadyOpen | Should -Be 1
    }

    It 'skips the company when the open-ticket lookup fails, rather than risk duplicates' {
        Mock Get-AutotaskAPIResource { Write-Error 'API Error: timeout' }
        $Summary = Invoke-IronScalesTicketSync -Configuration $script:Config
        Should -Invoke New-AutotaskTicket -Times 0
        $Summary.Failed | Should -Be 1
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Warning' -and $message -like '*1 failed*' }
    }

    It 'counts a Failed ticket result as a failure' {
        Mock New-AutotaskTicket { 'Failed to create Autotask ticket: bad queue' }
        (Invoke-IronScalesTicketSync -Configuration $script:Config).Failed | Should -Be 1
    }

    It 'keeps going when one company''s incidents cannot be read' {
        Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*incident/22/*' } { throw 'boom' }
        $Summary = Invoke-IronScalesTicketSync -Configuration $script:Config
        $Summary.Created | Should -Be 1
        $Summary.Failed | Should -Be 1
    }

    It 'logs quiet runs at Debug only' {
        Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*incident/*' } { [pscustomobject]@{ incidents = @() } }
        Invoke-IronScalesTicketSync -Configuration $script:Config | Out-Null
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Debug' -and $message -like 'IronScales sync:*' } -Times 1
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -ne 'Debug' } -Times 0
    }

    It 'does nothing when IronScales is disabled' {
        $Config = $script:Config | ConvertTo-Json -Depth 5 | ConvertFrom-Json
        $Config.IronScales.Enabled = $false
        Invoke-IronScalesTicketSync -Configuration $Config | Should -BeNullOrEmpty
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'warns and stops when Autotask is disabled' {
        $Config = $script:Config | ConvertTo-Json -Depth 5 | ConvertFrom-Json
        $Config.Autotask.Enabled = $false
        Invoke-IronScalesTicketSync -Configuration $Config | Should -BeNullOrEmpty
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Warning' -and $message -like '*Autotask is not*' }
        Should -Invoke Invoke-RestMethod -Times 0
    }
}
