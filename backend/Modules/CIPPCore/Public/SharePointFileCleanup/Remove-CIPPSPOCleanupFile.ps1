function Remove-CIPPSPOCleanupFile {
    <#
    .SYNOPSIS
        Permanently deletes one SharePoint file by server-relative path, if it still exists.
    .DESCRIPTION
        Fulcra custom (migration plan 07). The search index can lag behind deletes, so the file is
        looked up first; a missing file returns 'Missing' rather than an error. Deletion is permanent
        (not to the recycle bin), the same as the old job's Remove-PnPFile -Force (O-07-2), so the
        storage is freed straight away.
    .OUTPUTS
        'Deleted' or 'Missing'. Throws on any other failure.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)]$RestContext,
        [Parameter(Mandatory = $true)][string]$FilePath
    )

    # decodedurl takes the plain path: quotes are doubled for OData, and each segment is percent-encoded
    # so '#', '%' and '&' in file names survive the URL.
    $Encoded = ($FilePath.Replace("'", "''") -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    $FileUri = "$($RestContext.WebUri)/GetFileByServerRelativePath(decodedurl='$Encoded')"

    try {
        $null = New-GraphGetRequest -uri "$FileUri`?`$select=Name" -tenantid $TenantFilter -scope $RestContext.Scope -extraHeaders $RestContext.Headers -UseCertificate -AsApp $true -noPagination $true -SkipValueExtraction
    } catch {
        if ("$($_.Exception.Message)" -match 'File Not Found|does not exist|\(404\)|404 \(Not Found\)') { return 'Missing' }
        throw
    }

    $Headers = @{ Accept = 'application/json;odata=nometadata'; 'X-HTTP-Method' = 'DELETE'; 'If-Match' = '*' }
    $null = New-GraphPOSTRequest -uri $FileUri -tenantid $TenantFilter -scope $RestContext.Scope -type POST -body '{}' -contentType 'application/json;odata=nometadata' -AddedHeaders $Headers -UseCertificate -AsApp $true
    return 'Deleted'
}
