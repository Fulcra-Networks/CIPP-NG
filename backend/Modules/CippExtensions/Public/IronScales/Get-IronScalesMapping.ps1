function Get-IronScalesMapping {
    <#
    .SYNOPSIS
        Returns the IronScales company list and the current tenant-to-company mappings for the
        Tenant Mapping tab.
    .DESCRIPTION
        Fulcra custom extension (migration plan 02). Mappings live in CippMapping, partition
        'IronScalesMapping', RowKey = tenant customerId, read as the old fork wrote them.
    .PARAMETER CIPPMapping
        The CippMapping table context from Get-CIPPTable.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param (
        $CIPPMapping
    )

    $ExtensionMappings = Get-ExtensionMapping -Extension 'IronScales'
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

    try {
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CippExtensions' and RowKey eq 'Config'").config | ConvertFrom-Json -ErrorAction Stop).IronScales
        $Token = Get-IronScalesToken -Configuration $Configuration
        $Companies = Get-IronScalesCompany -Configuration $Configuration -Token $Token | Sort-Object -Property name | ForEach-Object {
            [PSCustomObject]@{
                name  = $_.name
                value = "$($_.id)"
            }
        }
    } catch {
        $Message = if ($_.ErrorDetails.Message) { Get-NormalizedError -Message $_.ErrorDetails.Message } else { $_.Exception.Message }
        Write-LogMessage -API 'IronScalesMapping' -tenant 'CIPP' -message "Could not get IronScales companies: $Message" -sev Error
        $Companies = @([PSCustomObject]@{ name = "Could not get IronScales companies, error: $Message"; value = '-1' })
    }

    return [PSCustomObject]@{
        Companies = @($Companies)
        Mappings  = @($Mappings)
    }
}
