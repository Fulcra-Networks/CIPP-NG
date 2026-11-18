function Get-IronScalesToken {
    <#
    .SYNOPSIS
        Signs in to the IronScales partner API and returns the JWT.
    .DESCRIPTION
        Fulcra custom extension (migration plan 02). The partner API key is the stored secret
        'IronScales' (Key Vault, or the DevSecrets table locally), the same secret the old fork used.
        Throws on failure: the fork returned $null and then called the API with an empty bearer token.
    .PARAMETER Configuration
        The IronScales configuration block (needs ApiHost).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Configuration
    )

    if (-not "$($Configuration.ApiHost)".Trim()) {
        throw 'IronScales is not configured: set the API base URL under Settings > Integrations > IronScales.'
    }
    $Key = Get-ExtensionAPIKey -Extension 'IronScales'
    if (-not $Key) {
        throw 'IronScales API key not found. Enter it under Settings > Integrations > IronScales.'
    }

    # TODO (from the fork): move scopes to config.
    $Body = @{ key = "$Key"; scopes = @('partner.all') } | ConvertTo-Json -Compress
    try {
        $Response = Invoke-RestMethod -Method Post -ContentType 'application/json' -Uri "$("$($Configuration.ApiHost)".Trim().TrimEnd('/'))/get-token/" -Body $Body
    } catch {
        $Message = if ($_.ErrorDetails.Message) { Get-NormalizedError -Message $_.ErrorDetails.Message } else { $_.Exception.Message }
        Write-LogMessage -API 'IronScales' -tenant 'CIPP' -message "IronScales authentication failed: $Message" -sev Error
        throw "IronScales authentication failed: $Message"
    }
    if (-not $Response.jwt) {
        throw 'IronScales authentication failed: no token was returned.'
    }
    return $Response.jwt
}
