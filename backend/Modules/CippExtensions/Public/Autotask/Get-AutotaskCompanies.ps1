function Get-AutotaskCompanies {
    <#
    .SYNOPSIS
        Returns Autotask companies: by default every active Customer (companyType 1).
    .DESCRIPTION
        Fulcra custom extension (migration plan 01). Used by the tenant mapping tab and by plan 04
        (Azure billing). On failure returns a single placeholder row whose name carries the error,
        so the mapping picker shows it instead of an empty list.
    .PARAMETER queryObj
        Optional Autotask search object (the { filter = [...] } shape) to use instead of the
        default Customer filter. The fork ignored this parameter because of a typo; it now works,
        so re-test plan 04's callers that pass it.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param ($queryObj)

    try {
        Get-AutotaskToken
        $Query = if ($null -eq $queryObj) {
            "{'filter':[{'op':'and',items:[{'op':'eq','field':'isactive','value':true},{'op':'eq','field':'companyType','value':'1'}]}]}"
        } else {
            $queryObj | ConvertTo-Json -Depth 50 -Compress
        }
        $Companies = Get-AutotaskAPIResource -Resource Companies -SearchQuery $Query -ErrorAction Stop
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.Message
        }
        Write-LogMessage -API 'AutotaskMapping' -tenant 'CIPP' -message "Could not get Autotask companies: $Message" -sev Error
        $Companies = @([pscustomobject]@{ id = -1; companyName = "Could not get Autotask companies, error: $Message" })
    }
    return $Companies
}
