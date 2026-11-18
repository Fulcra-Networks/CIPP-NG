function Invoke-IronScalesRequest {
    <#
    .SYNOPSIS
        Sends a GET request to the IronScales partner API.
    .DESCRIPTION
        Fulcra custom extension (migration plan 02). Replaces the fork's module-scope $apiHost / $JWT
        variables: ModuleBuilder concatenates every Public file into one module, so they would have
        been module-wide globals.
    .PARAMETER Configuration
        The IronScales configuration block (needs ApiHost).
    .PARAMETER Token
        JWT from Get-IronScalesToken.
    .PARAMETER Path
        Path below ApiHost, for example '/company/list/'.
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
        [string]$Path
    )

    $Uri = "$("$($Configuration.ApiHost)".Trim().TrimEnd('/'))/$($Path.TrimStart('/'))"
    Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $Token" } -ErrorAction Stop
}
