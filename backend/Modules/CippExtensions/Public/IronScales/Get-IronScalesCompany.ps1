function Get-IronScalesCompany {
    <#
    .SYNOPSIS
        Lists the IronScales companies under the partner account.
    .DESCRIPTION
        Fulcra custom extension (migration plan 02). Fetched on every call: the fork cached the list
        for the life of the process, so on long-lived Craft workers new customers would not appear.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Configuration,
        [Parameter(Mandatory = $true)]
        [string]$Token
    )

    @((Invoke-IronScalesRequest -Configuration $Configuration -Token $Token -Path '/company/list/').companies)
}
