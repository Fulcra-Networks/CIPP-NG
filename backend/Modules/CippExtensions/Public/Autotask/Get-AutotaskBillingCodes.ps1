function Get-AutotaskBillingCodes {
    <#
    .SYNOPSIS
        Returns the active billing codes used for Azure charges (type 0, useType 4, taxCategoryID 2).
    .DESCRIPTION
        Fulcra custom extension (migration plan 01). Used by plan 04 (Azure billing).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param ()

    try {
        Get-AutotaskToken
        $Codes = Get-AutotaskAPIResource -Resource BillingCodes -SearchQuery "{'filter':[{'op':'eq','field':'isActive','value':true},{'op':'eq','field':'billingCodeType','value':0},{'op':'eq','field':'usetype','value':4},{'op':'eq','field':'taxCategoryID','value':2}]}" -ErrorAction Stop
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.Message
        }
        Write-LogMessage -API 'AutotaskBillingCodes' -tenant 'CIPP' -message "Could not get Autotask billing codes: $Message" -sev Error
        $Codes = @([pscustomobject]@{ name = "Could not get Autotask billing codes: $Message" })
    }
    return $Codes
}
