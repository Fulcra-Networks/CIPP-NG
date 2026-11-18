function Get-AutotaskCompanyContracts {
    <#
    .SYNOPSIS
        Returns a company's active recurring-service contracts (status 1, contractType 7).
    .DESCRIPTION
        Fulcra custom extension (migration plan 01). Used by plan 04 (Azure billing).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $CompanyId
    )

    try {
        $Id = 0
        if (-not [long]::TryParse("$CompanyId", [ref]$Id)) { throw "'$CompanyId' is not a valid Autotask company id." }
        Get-AutotaskToken
        $Contracts = Get-AutotaskAPIResource -Resource Contracts -SearchQuery "{'filter':[{'op':'eq','field':'companyId','value':$Id},{'op':'eq','field':'status','value':1},{'op':'eq','field':'contractType','value':7}]}" -ErrorAction Stop
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.Message
        }
        Write-LogMessage -API 'AutotaskContracts' -tenant 'CIPP' -message "Could not get Autotask contracts for company $($CompanyId): $Message" -sev Error
        $Contracts = @([pscustomobject]@{ name = "Could not get Autotask contracts, error: $Message" })
    }
    return $Contracts
}
