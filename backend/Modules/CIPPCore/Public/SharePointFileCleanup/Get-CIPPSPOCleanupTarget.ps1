function Get-CIPPSPOCleanupTarget {
    <#
    .SYNOPSIS
        Finds files on one SharePoint site that match a type, a minimum size and a last-modified cutoff.
    .DESCRIPTION
        Fulcra custom (migration plan 07). Uses SharePoint search (KQL) rather than list queries, which
        fail on libraries past the 5,000-item list view threshold. The search Size property is in bytes;
        the old job compared it with a KB value, so its threshold was 1024 times too small (D-013).
        trimduplicates=false keeps identical copies in different folders, matching the old PnP query.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)]$RestContext,
        [Parameter(Mandatory = $true)][string]$FileType,
        [Parameter(Mandatory = $true)][datetime]$Cutoff,
        [Parameter(Mandatory = $true)][long]$MinimumSizeBytes,
        [int]$PageSize = 500
    )

    $CutoffText = $Cutoff.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Kql = "path:""$($RestContext.SiteUrl)"" AND filetype:$FileType AND size>$MinimumSizeBytes AND write<""$CutoffText"""
    $QueryText = [uri]::EscapeDataString("'$($Kql.Replace("'", "''"))'")
    $SitePath = ([uri]$RestContext.SiteUrl).AbsolutePath.TrimEnd('/')

    $StartRow = 0
    do {
        $Uri = "$($RestContext.BaseUri)/search/query?querytext=$QueryText&startrow=$StartRow&rowlimit=$PageSize&trimduplicates=false" +
        "&selectproperties='FileName,ParentLink,Size,Write'&sortlist='Write:ascending'"
        $Response = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -scope $RestContext.Scope -extraHeaders $RestContext.Headers -UseCertificate -AsApp $true -noPagination $true -SkipValueExtraction
        $Results = $Response.PrimaryQueryResult.RelevantResults
        $Rows = @($Results.Table.Rows)
        foreach ($Row in $Rows) {
            $Cells = @{}
            foreach ($Cell in @($Row.Cells)) { $Cells[$Cell.Key] = $Cell.Value }
            if (-not $Cells.FileName -or -not $Cells.ParentLink) { continue }
            # Path points at DispForm.aspx for some file types (.bak among them), so build the file's
            # server-relative path from its folder and name instead.
            $ParentPath = [uri]::UnescapeDataString(([uri]$Cells.ParentLink).AbsolutePath).TrimEnd('/')
            $FilePath = "$ParentPath/$($Cells.FileName)"
            # path: already scopes the query; this guards against a search result from another site.
            if (-not $FilePath.StartsWith("$SitePath/", [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            [pscustomobject]@{
                FileName = [string]$Cells.FileName
                FilePath = $FilePath
                FileSize = [long]($Cells.Size -as [long])
                Modified = [string]$Cells.Write
            }
        }
        $StartRow += $PageSize
    } while ($Rows.Count -gt 0 -and $StartRow -lt [int]$Results.TotalRows)
}
