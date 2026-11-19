function Invoke-CIPPSharePointFileCleanup {
    <#
    .SYNOPSIS
        Deletes old files of the given types from a tenant's SharePoint sites.
    .DESCRIPTION
        Fulcra custom (migration plan 07). Run it as a Scheduler task. For each site it searches for
        files of the given types that are larger than MinimumFileSizeMB and were last modified more
        than LastModifiedDays ago, then deletes them permanently. Each deletion is recorded in the
        SharePointCleanupHistory table. Any errors raise one Autotask ticket per run.

        It uses CIPP's own app (app-only SharePoint REST with the CIPP certificate), so no separate
        app registration or PnP module is needed (D-014). Use DryRun for the first run: it lists what
        would be deleted and changes nothing.
    .PARAMETER TenantFilter
        The tenant. The scheduler sets this from the task's tenant.
    .PARAMETER SiteUrlsCsv
        Comma-separated full site URLs in that tenant, e.g. https://contoso.sharepoint.com/sites/Backups.
    .PARAMETER FileTypesCsv
        Comma-separated file extensions without the dot, e.g. bak.
    .PARAMETER LastModifiedDays
        Only files last modified more than this many days ago are deleted (at least 1).
    .PARAMETER MinimumFileSizeMB
        Only files larger than this are deleted. Decimals are allowed (0.01 is about 10 KB).
    .PARAMETER DryRun
        List the matching files without deleting anything or writing history.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$SiteUrlsCsv,
        [Parameter(Mandatory = $true)][string]$FileTypesCsv,
        [Parameter(Mandatory = $true)][int]$LastModifiedDays,
        [double]$MinimumFileSizeMB = 100,
        [switch]$DryRun
    )

    $API = 'SharePointFileCleanup'
    $Sites = @($SiteUrlsCsv -split ',' | ForEach-Object { $_.Trim().TrimEnd('/') } | Where-Object { $_ } | Select-Object -Unique)
    $FileTypes = @($FileTypesCsv -split ',' | ForEach-Object { $_.Trim().TrimStart('.').ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)

    # Fail fast on settings that would make the query meaningless or unsafe to run.
    $Problems = @(
        if ($Sites.Count -eq 0) { 'no site URLs were given' }
        if ($FileTypes.Count -eq 0) { 'no file types were given' }
        if ($FileTypes | Where-Object { $_ -notmatch '^[a-z0-9]{1,10}$' }) { 'file types must be plain extensions such as bak' }
        if ($LastModifiedDays -lt 1) { 'LastModifiedDays must be at least 1' }
        if ($MinimumFileSizeMB -lt 0) { 'MinimumFileSizeMB cannot be negative' }
    )
    if ($Problems) {
        $Message = "SharePoint file cleanup did not run: $($Problems -join '; ')."
        Write-LogMessage -API $API -tenant $TenantFilter -message $Message -sev Error
        throw $Message
    }

    $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
    if (-not $Tenant.customerId) { throw "SharePoint file cleanup did not run: tenant '$TenantFilter' was not found." }

    $Cutoff = (Get-Date).ToUniversalTime().AddDays(-$LastModifiedDays)
    $MinimumSizeBytes = [long][math]::Floor($MinimumFileSizeMB * 1MB)
    $Errors = [System.Collections.Generic.List[string]]::new()
    $Found = 0
    $Deleted = 0
    $Missing = 0
    $HistoryTable = if (-not $DryRun) { Get-CIPPTable -TableName 'SharePointCleanupHistory' }
    $Mode = if ($DryRun) { 'Dry run: ' } else { '' }

    foreach ($Site in $Sites) {
        try {
            $Context = Resolve-CIPPSharePointRestContext -TenantFilter $TenantFilter -SiteUrl $Site
        } catch {
            $Errors.Add("Skipped site ${Site}: $($_.Exception.Message)")
            continue
        }

        $Targets = [System.Collections.Generic.List[object]]::new()
        foreach ($FileType in $FileTypes) {
            try {
                foreach ($Target in @(Get-CIPPSPOCleanupTarget -TenantFilter $TenantFilter -RestContext $Context -FileType $FileType -Cutoff $Cutoff -MinimumSizeBytes $MinimumSizeBytes)) { $Targets.Add($Target) }
            } catch {
                $Errors.Add("Search failed on $Site for .${FileType}: $($_.Exception.Message)")
            }
        }
        $Found += $Targets.Count
        if ($Targets.Count -eq 0) { continue }

        if ($DryRun) {
            $Sample = ($Targets | Sort-Object Modified -Descending | Select-Object -First 10 | ForEach-Object { "$($_.FilePath) ($($_.Modified))" }) -join '; '
            Write-LogMessage -API $API -tenant $TenantFilter -message "${Mode}$($Targets.Count) file(s) on $Site would be deleted. Newest 10: $Sample" -sev Info
            continue
        }

        foreach ($Target in $Targets) {
            # SharePoint throttles bursts of deletes; the request helpers also retry on 429/503.
            Start-Sleep -Milliseconds 650
            try {
                $Outcome = Remove-CIPPSPOCleanupFile -TenantFilter $TenantFilter -RestContext $Context -FilePath $Target.FilePath
            } catch {
                $Errors.Add("Could not delete $($Target.FilePath): $($_.Exception.Message)")
                continue
            }
            if ($Outcome -eq 'Missing') { $Missing++; continue }
            $Deleted++
            try {
                Add-CIPPAzDataTableEntity @HistoryTable -Entity @{
                    PartitionKey  = [string]$Tenant.customerId
                    RowKey        = [string][guid]::NewGuid()
                    SiteUrl       = $Site
                    FileName      = $Target.FileName
                    FilePath      = $Target.FilePath
                    FileSize      = [string]$Target.FileSize
                    FileModified  = $Target.Modified
                    DeletedDate   = (Get-Date).ToUniversalTime().ToString('o')
                    FileExtension = [System.IO.Path]::GetExtension($Target.FileName)
                } -Force
            } catch {
                Write-LogMessage -API $API -tenant $TenantFilter -message "Deleted $($Target.FilePath) but could not record it in the history table: $($_.Exception.Message)" -sev Warning
            }
        }
    }

    $Summary = "${Mode}SharePoint file cleanup: $Found matching file(s) across $($Sites.Count) site(s) (.$($FileTypes -join ', .'), larger than $MinimumFileSizeMB MB, last modified before $($Cutoff.ToString('yyyy-MM-dd')))"
    if (-not $DryRun) { $Summary += "; $Deleted deleted, $Missing already gone" }
    $Summary += "; $($Errors.Count) error(s)."
    Write-LogMessage -API $API -tenant $TenantFilter -message $Summary -sev $(if ($Errors.Count) { 'Warning' } else { 'Info' })
    foreach ($ErrorMessage in $Errors) { Write-LogMessage -API $API -tenant $TenantFilter -message $ErrorMessage -sev Error }

    if ($Errors.Count -gt 0) {
        try {
            Submit-CIPPSPOCleanupErrorTicket -Tenant $Tenant -ErrorMessages $Errors -FilesFound $Found -FilesDeleted $Deleted -SiteCount $Sites.Count
        } catch {
            Write-LogMessage -API $API -tenant $TenantFilter -message "Could not create the error ticket: $($_.Exception.Message)" -sev Error
        }
    }

    return [pscustomobject]@{ Found = $Found; Deleted = $Deleted; Missing = $Missing; Errors = @($Errors); DryRun = [bool]$DryRun; Summary = $Summary }
}
