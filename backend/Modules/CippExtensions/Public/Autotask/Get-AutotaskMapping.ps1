function Get-AutotaskMapping {
    <#
    .SYNOPSIS
        Returns the Autotask company list and the current tenant-to-company mappings for the
        Tenant Mapping tab.
    .DESCRIPTION
        Fulcra custom extension (migration plan 01). Same payload shape as Get-SyncroMapping.
        Mappings live in CippMapping, partition 'AutotaskMapping', RowKey = tenant customerId -
        the rows the old fork wrote, read as they are (D-023).
    .PARAMETER CIPPMapping
        The CippMapping table context from Get-CIPPTable.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param (
        $CIPPMapping
    )

    $ExtensionMappings = Get-ExtensionMapping -Extension 'Autotask'
    $Tenants = Get-Tenants -IncludeErrors

    $Mappings = foreach ($Mapping in $ExtensionMappings) {
        $Tenant = $Tenants | Where-Object { $_.customerId -eq $Mapping.RowKey }
        if ($Tenant) {
            [PSCustomObject]@{
                TenantId        = $Tenant.customerId
                Tenant          = $Tenant.displayName
                TenantDomain    = $Tenant.defaultDomainName
                IntegrationId   = $Mapping.IntegrationId
                IntegrationName = $Mapping.IntegrationName
            }
        }
    }

    $Companies = Get-AutotaskCompanies | Sort-Object -Property companyName | ForEach-Object {
        [PSCustomObject]@{
            name  = $_.companyName
            value = "$($_.id)"
        }
    }

    return [PSCustomObject]@{
        Companies = @($Companies)
        Mappings  = @($Mappings)
    }
}
