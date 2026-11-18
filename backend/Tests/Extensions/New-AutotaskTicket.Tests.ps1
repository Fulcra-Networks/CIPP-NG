# Pester tests for New-AutotaskTicket (Fulcra migration plan 01).
# The fork's version returned nothing and swallowed API errors (the AutotaskAPI module only writes
# non-terminating errors), so failed tickets were invisible. NG's Send-CIPPAlert reads the
# returned line and treats one starting with Failed/Error as a failure, so both outcomes matter.
# The payload is only observable as the body handed to New-AutotaskAPIResource.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-AutotaskToken { param($Configuration, [switch]$Force) }
    function New-AutotaskAPIResource { [CmdletBinding()] param($Resource, $Body, $ParentId) }
    function Get-AutotaskAPIResource { [CmdletBinding()] param($Resource, $ID, $SearchQuery) }
    function Get-NormalizedError { param($Message) $Message }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }

    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/Autotask/ConvertTo-AutotaskText.ps1')
    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/Autotask/New-AutotaskTicket.ps1')
}

Describe 'New-AutotaskTicket' {
    BeforeEach {
        $script:Sent = $null
        Mock Get-AutotaskToken {}
        Mock Write-LogMessage {}
        Mock New-AutotaskAPIResource { $script:Sent = $Body; [pscustomobject]@{ itemId = 555 } }
        Mock Get-AutotaskAPIResource { [pscustomobject]@{ ticketNumber = 'T20261118.0001' } }
    }

    It 'posts the ticket with the Fulcra defaults and reports the ticket number' {
        $Result = New-AutotaskTicket -atCompanyId '123' -title '[CIPP] Alert' -description '<p>body</p>' -issueType 29 -subIssueType 327

        $Result | Should -Be 'Created Autotask ticket T20261118.0001 (id 555)'
        $script:Sent.CompanyID | Should -Be 123
        $script:Sent.Title | Should -Be '[CIPP] Alert'
        $script:Sent.Description | Should -Be 'body'
        $script:Sent.IssueType | Should -Be 29
        $script:Sent.SubIssueType | Should -Be 327
        $script:Sent.Priority | Should -Be 2
        $script:Sent.TicketType | Should -Be 5
        $script:Sent.QueueID | Should -Be 29682833
        $script:Sent.BillingCodeID | Should -Be 29682801
        $script:Sent.Source | Should -Be 8
        $script:Sent.Status | Should -Be 1
    }

    It 'still binds the old -atCompany name' {
        New-AutotaskTicket -atCompany 7 -title 't' -description 'd' | Out-Null
        $script:Sent.CompanyID | Should -Be 7
    }

    It 'accepts company 0 (the base company)' {
        New-AutotaskTicket -atCompanyId 0 -title 't' -description 'd' | Should -Match '^Created'
    }

    It 'falls back to the ticket id when the read-back fails' {
        Mock Get-AutotaskAPIResource { throw 'nope' }
        New-AutotaskTicket -atCompanyId 1 -title 't' -description 'd' | Should -Be 'Created Autotask ticket id 555'
    }

    It 'truncates the description to 8000 and the title to 255 characters' {
        New-AutotaskTicket -atCompanyId 1 -title ('t' * 300) -description ('d' * 9000) | Out-Null
        $script:Sent.Description.Length | Should -Be 8000
        $script:Sent.Description | Should -Match 'truncated 1000 chars'
        $script:Sent.Title.Length | Should -Be 255
    }

    It 'leaves issue types off when not given' {
        New-AutotaskTicket -atCompanyId 1 -title 't' -description 'd' | Out-Null
        $script:Sent.PSObject.Properties.Name | Should -Not -Contain 'IssueType'
    }

    It 'returns a Failed line when the API rejects the ticket' {
        Mock New-AutotaskAPIResource { Write-Error 'API Error: Queue is invalid' }
        New-AutotaskTicket -atCompanyId 1 -title 't' -description 'd' | Should -Be 'Failed to create Autotask ticket: API Error: Queue is invalid'
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Error' }
    }

    It 'returns a Failed line when authentication fails' {
        Mock Get-AutotaskToken { throw 'Autotask authentication failed: bad secret' }
        New-AutotaskTicket -atCompanyId 1 -title 't' -description 'd' | Should -Be 'Failed to create Autotask ticket: Autotask authentication failed: bad secret'
    }

    It 'returns a Failed line for a non-numeric company id without calling the API' {
        New-AutotaskTicket -atCompanyId 'abc' -title 't' -description 'd' | Should -Match '^Failed to create Autotask ticket: .abc. is not a valid'
        Should -Invoke New-AutotaskAPIResource -Times 0
    }

    It 'returns a Failed line when no ticket id comes back' {
        Mock New-AutotaskAPIResource { [pscustomobject]@{} }
        New-AutotaskTicket -atCompanyId 1 -title 't' -description 'd' | Should -Match '^Failed.*no ticket id'
    }
}
