function Get-AutotaskToken {
    <#
    .SYNOPSIS
        Authenticates the vendored AutotaskAPI module for this runspace.
    .DESCRIPTION
        Fulcra custom extension (migration plan 01). Despite the name it returns nothing: the
        AutotaskAPI module keeps its auth headers and zone URL in its own script scope, and every
        Get/New/Set-AutotaskAPIResource call after this uses them. The name is kept because plans
        02, 04 and 07 call it.

        The secret is the Key Vault secret 'Autotask' (via Get-ExtensionAPIKey), the same secret
        the old fork used, so the existing vault works unchanged (D-019, D-023).

        Authentication costs two HTTP calls plus a rebuild of the module's dynamic parameters, so
        a runspace that is already authenticated with the same user, integration code and secret
        is reused. Throws on failure: without auth the module's -Resource parameter does not exist
        and callers would otherwise fail later with a misleading parameter-binding error.
    .PARAMETER Configuration
        The Autotask configuration block. Defaults to the stored one.
    .PARAMETER Force
        Re-authenticate even if this runspace already is.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param (
        $Configuration,
        [switch]$Force
    )

    if (-not $Configuration) { $Configuration = Get-AutotaskConfiguration }
    if (-not $Configuration.APIUser -or -not $Configuration.APIIntegrationCode) {
        throw 'Autotask is not configured: set the API user and integration code under Settings > Integrations > Autotask.'
    }

    Import-Module AutotaskAPI -ErrorAction Stop

    $Secret = Get-ExtensionAPIKey -Extension 'Autotask'
    if (-not $Secret) {
        throw 'Autotask API secret not found. Enter it under Settings > Integrations > Autotask.'
    }

    $Module = Get-Module AutotaskAPI
    $Current = & $Module { [pscustomobject]@{ Header = $Script:AutotaskAuthHeader; BaseURI = $Script:AutotaskBaseURI } }
    if (-not $Force -and $Current.BaseURI -and $Current.Header -and
        $Current.Header.UserName -eq $Configuration.APIUser -and
        $Current.Header.ApiIntegrationcode -eq $Configuration.APIIntegrationCode -and
        $Current.Header.Secret -eq $Secret) {
        return
    }

    $Pass = ConvertTo-SecureString -String $Secret -AsPlainText -Force
    $Credential = [pscredential]::new($Configuration.APIUser, $Pass)

    try {
        Add-AutotaskAPIAuth -ApiIntegrationcode $Configuration.APIIntegrationCode -credentials $Credential 6>$null
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.Message
        }
        Write-LogMessage -API 'Autotask' -tenant 'CIPP' -message "Autotask authentication failed: $Message" -sev Error
        throw "Autotask authentication failed: $Message"
    }
}
