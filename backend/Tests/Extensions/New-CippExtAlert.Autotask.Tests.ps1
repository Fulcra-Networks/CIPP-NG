# Pester tests for the Autotask branch of New-CippExtAlert (Fulcra migration plan 01).
# The dispatcher resolves the tenant to its mapped Autotask company and hands the alert to
# New-AutotaskTicket. Unmapped tenants go to the base company 0 with a warning (D-025), and the
# per-alert priority only passes through when it is an Autotask priority.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Get-ExtensionMapping { param($Extension) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function New-AutotaskTicket { param($atCompanyId, $title, $description, $issueType, $subIssueType, $priority, $Configuration) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }

    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/New-CippExtAlert.ps1')

    function New-Alert {
        param($PsaTicketPriority)
        $Alert = [pscustomobject]@{ TenantId = 'contoso.onmicrosoft.com'; AlertTitle = '[CIPP] Alert'; AlertText = '<p>body</p>' }
        if ($PsaTicketPriority) { $Alert | Add-Member -NotePropertyName PsaTicketPriority -NotePropertyValue $PsaTicketPriority }
        $Alert
    }
}

Describe 'New-CippExtAlert - Autotask' {
    BeforeEach {
        $script:TicketArgs = $null
        $script:Enabled = $true
        Mock Get-CIPPTable { @{ TableName = $TableName } }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ config = (@{ Autotask = @{ Enabled = $script:Enabled; APIUser = 'api@fulcra.example' } } | ConvertTo-Json -Depth 5) } }
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'customer-guid' } }
        Mock Get-ExtensionMapping { [pscustomobject]@{ RowKey = 'customer-guid'; IntegrationId = '123'; IntegrationName = 'Contoso' } }
        Mock Write-LogMessage {}
        Mock New-AutotaskTicket {
            $script:TicketArgs = [pscustomobject]@{ Company = $atCompanyId; Title = $title; Description = $description; Issue = $issueType; SubIssue = $subIssueType; Priority = $priority; Configuration = $Configuration }
            'Created Autotask ticket T1 (id 1)'
        }
    }

    It 'raises the ticket against the mapped company with the alert issue types' {
        $Result = New-CippExtAlert -Alert (New-Alert)

        $Result | Should -Be 'Created Autotask ticket T1 (id 1)'
        $script:TicketArgs.Company | Should -Be '123'
        $script:TicketArgs.Title | Should -Be '[CIPP] Alert'
        $script:TicketArgs.Description | Should -Be '<p>body</p>'
        $script:TicketArgs.Issue | Should -Be 29
        $script:TicketArgs.SubIssue | Should -Be 327
        $script:TicketArgs.Priority | Should -Be '2'
        $script:TicketArgs.Configuration.APIUser | Should -Be 'api@fulcra.example'
    }

    It 'uses company 0 and logs a warning when the tenant is not mapped' {
        Mock Get-ExtensionMapping { [pscustomobject]@{ RowKey = 'other-guid'; IntegrationId = '999' } }

        New-CippExtAlert -Alert (New-Alert) | Out-Null

        $script:TicketArgs.Company | Should -Be 0
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Warning' -and $message -like '*company 0*' }
    }

    It 'maps Autotask priorities and falls back to Normal for anything else' -TestCases @(
        @{ In = '1'; Out = '1' }
        @{ In = 'High'; Out = '1' }
        @{ In = '4'; Out = '4' }
        @{ In = 'critical'; Out = '4' }
        @{ In = '2 Normal'; Out = '2' }
        @{ In = '17'; Out = '2' }
    ) {
        New-CippExtAlert -Alert (New-Alert -PsaTicketPriority $In) | Out-Null
        $script:TicketArgs.Priority | Should -Be $Out
    }

    It 'reads the value of a {label, value} priority' {
        New-CippExtAlert -Alert (New-Alert -PsaTicketPriority ([pscustomobject]@{ label = 'Critical'; value = '4' })) | Out-Null
        $script:TicketArgs.Priority | Should -Be '4'
    }

    It 'does nothing when the integration is disabled' {
        $script:Enabled = $false
        New-CippExtAlert -Alert (New-Alert) | Should -BeNullOrEmpty
        Should -Invoke New-AutotaskTicket -Times 0
    }
}
