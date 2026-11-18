function Invoke-IronScalesTicketSync {
    <#
    .SYNOPSIS
        Raises an Autotask ticket for every mapped IronScales company with unclassified incidents.
    .DESCRIPTION
        Fulcra custom extension (migration plan 02). It replaces the fork's Get-IronScalesIncidents
        and New-IronScalesTickets. Start-IronScalesTimer runs it every 30 minutes on weekdays, and
        the Force Sync button queues it.

        For each IronScales company with unclassified incidents from the last 7 days (period 1), it
        follows IronScales company -> CIPP tenant (IronScalesMapping) -> Autotask company
        (AutotaskMapping), and creates one ticket per company. It skips the company while a ticket
        with the same title is still open for the same Autotask company (status New, Waiting
        Customer, In Progress or Waiting Vendor; O-02-3).

        IronScales has no Autotask integration of its own. The helpdesk works these tickets as a
        queue and classifies the incidents in the IronScales portal.

        It calls New-AutotaskTicket directly rather than the generic alert path (O-02-1). That keeps
        the IronScales issue types: priority High (1), issue Service Management (29), sub-issue
        Email Security (323). Queue, work type and the other Fulcra ids are New-AutotaskTicket's
        defaults (D-026).
    .PARAMETER Configuration
        The full extension configuration. Defaults to the stored one.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param (
        $Configuration
    )

    $API = 'IronScales'
    if (-not $Configuration) {
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = (Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CippExtensions' and RowKey eq 'Config'").config | ConvertFrom-Json -Depth 10
    }
    if ($Configuration.IronScales.Enabled -ne $true) { return }
    if ($Configuration.Autotask.Enabled -ne $true) {
        Write-LogMessage -API $API -tenant 'none' -message 'IronScales is enabled but Autotask is not, so no incident tickets were created.' -sev Warning
        return
    }

    $Token = Get-IronScalesToken -Configuration $Configuration.IronScales
    Get-AutotaskToken -Configuration $Configuration.Autotask

    $ISMappings = @(Get-ExtensionMapping -Extension 'IronScales')
    $ATMappings = @(Get-ExtensionMapping -Extension 'Autotask')
    $Companies = Get-IronScalesCompany -Configuration $Configuration.IronScales -Token $Token

    $Summary = [ordered]@{ Companies = $Companies.Count; WithIncidents = 0; Created = 0; AlreadyOpen = 0; Failed = 0; Unmapped = [System.Collections.Generic.List[string]]::new() }

    foreach ($Company in $Companies) {
        try {
            $Incidents = Get-IronScalesIncident -Configuration $Configuration.IronScales -Token $Token -CompanyId "$($Company.id)"
        } catch {
            $Summary.Failed++
            Write-LogMessage -API $API -tenant 'none' -message "Could not get IronScales incidents for $($Company.name): $($_.Exception.Message)" -sev Error
            continue
        }
        if ($Incidents.Count -eq 0) { continue }
        $Summary.WithIncidents++

        $ISMapping = $ISMappings | Where-Object { "$($_.IntegrationId)" -eq "$($Company.id)" } | Select-Object -First 1
        $ATMapping = if ($ISMapping) { $ATMappings | Where-Object { $_.RowKey -eq $ISMapping.RowKey } | Select-Object -First 1 }
        if (-not $ATMapping -or "$($ATMapping.IntegrationId)" -notmatch '^\d+$') {
            $Summary.Unmapped.Add("$($Company.name)")
            continue
        }

        $Title = "[IronScales] New Incident(s) for $($Company.name)"
        $Filter = @{
            filter = @(@{
                    op    = 'and'
                    items = @(
                        @{ op = 'contains'; field = 'title'; value = $Title }
                        @{ op = 'eq'; field = 'companyID'; value = [int64]$ATMapping.IntegrationId }
                        # New 1, Waiting Customer 7, In Progress 8, Waiting Vendor 12
                        @{ op = 'in'; field = 'status'; value = @(1, 7, 8, 12) }
                    )
                })
        } | ConvertTo-Json -Depth 10 -Compress
        try {
            $Existing = Get-AutotaskAPIResource -Resource Tickets -SearchQuery $Filter -ErrorAction Stop
        } catch {
            # A failed lookup skips the company: the next run retries, while creating blind would
            # add a duplicate ticket every 30 minutes for as long as the lookup keeps failing.
            $Summary.Failed++
            Write-LogMessage -API $API -tenant 'none' -message "Could not check for an open IronScales ticket for $($Company.name), so none was created: $($_.Exception.Message)" -sev Error
            continue
        }
        if ($Existing) {
            $Summary.AlreadyOpen++
            continue
        }

        $Result = New-AutotaskTicket -atCompanyId $ATMapping.IntegrationId `
            -title $Title `
            -description (Get-IronScalesTicketBody -CompanyName $Company.name -Incidents $Incidents) `
            -estHr (0.1 * $Incidents.Count) `
            -issueType '29' `
            -subIssueType '323' `
            -priority '1' `
            -Configuration $Configuration.Autotask
        if ("$Result" -match '^(Failed|Error)') {
            $Summary.Failed++
        } else {
            $Summary.Created++
            Write-LogMessage -API $API -tenant 'none' -message "$Result for $($Incidents.Count) unclassified IronScales incident(s) at $($Company.name)." -sev Info
        }
    }

    # Quiet runs stay at Debug: the timer fires 48 times a weekday.
    $Message = "IronScales sync: $($Summary.Companies) companies, $($Summary.WithIncidents) with unclassified incidents, $($Summary.Created) tickets created, $($Summary.AlreadyOpen) already open, $($Summary.Failed) failed."
    if ($Summary.Unmapped.Count -gt 0) { $Message += " Not mapped to an Autotask company: $($Summary.Unmapped -join ', ')." }
    $Sev = if ($Summary.Failed -gt 0) { 'Warning' } elseif ($Summary.Created -gt 0 -or $Summary.Unmapped.Count -gt 0) { 'Info' } else { 'Debug' }
    Write-LogMessage -API $API -tenant 'none' -message $Message -sev $Sev

    return [pscustomobject]$Summary
}
