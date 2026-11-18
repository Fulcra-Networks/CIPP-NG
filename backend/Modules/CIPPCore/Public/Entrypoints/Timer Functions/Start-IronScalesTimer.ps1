function Start-IronScalesTimer {
    <#
    .SYNOPSIS
        Raises Autotask tickets for unclassified IronScales incidents.
    .DESCRIPTION
        Fulcra custom extension (migration plan 02). Replaces the fork's Scheduler_IronScales timer.
        CIPPTimers.json runs it every 30 minutes on weekdays.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param()
    try {
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = (Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CippExtensions' and RowKey eq 'Config'").config | ConvertFrom-Json -Depth 10
        if ($Configuration.IronScales.Enabled -eq $true) {
            $null = Invoke-IronScalesTicketSync -Configuration $Configuration
        }
    } catch {
        Write-LogMessage -API 'Scheduler_IronScales' -tenant 'none' -message "IronScales sync failed: $($_.Exception.Message)" -sev Error
    }
}
