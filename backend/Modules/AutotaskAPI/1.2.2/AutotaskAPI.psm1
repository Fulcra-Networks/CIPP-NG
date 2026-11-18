# LOCAL PATCH (CIPP-NG migration plan 01): Join-Path instead of backslash paths, for Linux.
$Public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public' '*.ps1') -ErrorAction SilentlyContinue) + @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private' '*.ps1') -ErrorAction SilentlyContinue)
foreach ($import in @($Public))
{
    try
    {
        . $import.FullName
    }
    catch
    {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}