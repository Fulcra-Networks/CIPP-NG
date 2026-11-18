function Get-AutotaskConfiguration {
    <#
    .SYNOPSIS
        Returns the Autotask block of the stored extension configuration.
    .DESCRIPTION
        Fulcra custom extension (migration plan 01). Reads the single CippExtensions/Config row
        and returns its 'Autotask' key ({ Enabled, APIUser, APIIntegrationCode, APIKey }).
        Every Autotask helper uses this instead of its own unfiltered table read.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CippExtensions' and RowKey eq 'Config'"
    if (-not $Row.config) { return $null }
    return ($Row.config | ConvertFrom-Json -Depth 10 -ErrorAction Stop).Autotask
}
