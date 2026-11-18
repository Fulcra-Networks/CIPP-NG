function Get-IronScalesIncident {
    <#
    .SYNOPSIS
        Lists one IronScales company's incidents.
    .DESCRIPTION
        Fulcra custom extension (migration plan 02).
    .PARAMETER State
        all, classified, unclassified or challenged.
    .PARAMETER Period
        IronScales period code: 0 = last 24 hours, 1 = last 7 days, 2 = last 90 days, 3 = 180 days,
        4 = 360 days, 5 = year to date, 6 = all time. The fork used 1, which already covers a weekend.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Configuration,
        [Parameter(Mandatory = $true)]
        [string]$Token,
        [Parameter(Mandatory = $true)]
        [string]$CompanyId,
        [ValidateSet('all', 'classified', 'unclassified', 'challenged')]
        [string]$State = 'unclassified',
        [ValidateRange(0, 6)]
        [int]$Period = 1
    )

    $Path = "/incident/$([uri]::EscapeDataString($CompanyId))/list/?period=$Period&state=$State"
    @((Invoke-IronScalesRequest -Configuration $Configuration -Token $Token -Path $Path).incidents)
}
