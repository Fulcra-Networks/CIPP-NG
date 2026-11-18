function Set-IronScalesMapping {
    <#
    .SYNOPSIS
        Replaces the stored tenant-to-IronScales-company mappings with the rows posted from the
        Tenant Mapping tab.
    .DESCRIPTION
        Fulcra custom extension (migration plan 02). While the old fork still runs against the same
        storage account (D-019), both instances read and write these same rows.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param (
        $CIPPMapping,
        $APIName,
        $Request
    )

    Get-CIPPAzDataTableEntity @CIPPMapping -Filter "PartitionKey eq 'IronScalesMapping'" | ForEach-Object {
        Remove-CIPPAzDataTableEntity -Force @CIPPMapping -Entity $_
    }
    foreach ($Mapping in $Request.Body) {
        if (-not $Mapping.TenantId) { continue }
        $AddObject = @{
            PartitionKey    = 'IronScalesMapping'
            RowKey          = "$($Mapping.TenantId)"
            IntegrationId   = "$($Mapping.IntegrationId)"
            IntegrationName = "$($Mapping.IntegrationName)"
        }
        Add-CIPPAzDataTableEntity @CIPPMapping -Entity $AddObject -Force
        Write-LogMessage -API $APIName -headers $Request.Headers -message "Added IronScales mapping for $($Mapping.Tenant) to company $($Mapping.IntegrationName)." -Sev 'Info'
    }

    return [pscustomobject]@{ 'Results' = 'Successfully edited mapping table.' }
}
