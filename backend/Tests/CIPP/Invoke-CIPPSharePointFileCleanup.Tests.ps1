# Pester tests for the SharePoint file cleanup job (Fulcra migration plan 07).
# Replaces the old fork's PnP-based job with SharePoint REST through CIPP's own app (D-014). Pinned here:
# the size threshold is in bytes (D-013), search paging, stale index results are not errors, deletes are
# permanent (O-07-2), DryRun changes nothing, and errors raise one ticket per run.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Dir = Join-Path $BackendRoot 'Modules/CIPPCore/Public/SharePointFileCleanup'

    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-ExtensionMapping { param($Extension) }
    function New-AutotaskTicket { param($atCompanyId, $title, $description, $issueType, $subIssueType, $priority, $Configuration) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }
    function New-GraphGetRequest { param($uri, $tenantid, $scope, $extraHeaders, [switch]$UseCertificate, $AsApp, $noPagination, [switch]$SkipValueExtraction) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $scope, $type, $body, $contentType, $AddedHeaders, [switch]$UseCertificate, $AsApp) }
    function Resolve-CIPPSharePointRestContext {
        param($TenantFilter, $SiteUrl)
        if ($SiteUrl -notlike 'https://contoso.sharepoint.com/*') { throw "'$SiteUrl' is not a SharePoint URL of this tenant." }
        [pscustomobject]@{ SiteUrl = $SiteUrl; Scope = 'https://contoso.sharepoint.com/.default'; Headers = @{ Accept = 'application/json;odata=nometadata' }; BaseUri = "$SiteUrl/_api"; WebUri = "$SiteUrl/_api/web" }
    }

    Get-ChildItem $Dir -Filter *.ps1 | ForEach-Object { . $_.FullName }

    $script:Site = 'https://contoso.sharepoint.com/sites/Backups'
    function New-SearchResponse {
        param([object[]]$Files, [int]$Total)
        $Rows = foreach ($F in $Files) {
            [pscustomobject]@{ Cells = @(
                    [pscustomobject]@{ Key = 'FileName'; Value = $F.Name }
                    [pscustomobject]@{ Key = 'ParentLink'; Value = "https://contoso.sharepoint.com$($F.Folder -replace ' ', '%20')" }
                    [pscustomobject]@{ Key = 'Size'; Value = '20480' }
                    [pscustomobject]@{ Key = 'Write'; Value = '2023-01-01T00:00:00Z' }
                ) }
        }
        [pscustomobject]@{ PrimaryQueryResult = [pscustomobject]@{ RelevantResults = [pscustomobject]@{ TotalRows = ($Total ? $Total : @($Files).Count); Table = [pscustomobject]@{ Rows = @($Rows) } } } }
    }
    function Invoke-Cleanup {
        param([hashtable]$Extra = @{})
        $Params = @{ TenantFilter = 'contoso.com'; SiteUrlsCsv = $script:Site; FileTypesCsv = 'bak'; LastModifiedDays = 730; MinimumFileSizeMB = 0.01 }
        foreach ($Key in $Extra.Keys) { $Params[$Key] = $Extra[$Key] }
        Invoke-CIPPSharePointFileCleanup @Params
    }
}

Describe 'Invoke-CIPPSharePointFileCleanup' {
    BeforeEach {
        $script:Searches = [System.Collections.Generic.List[string]]::new()
        $script:Deletes = [System.Collections.Generic.List[object]]::new()
        $script:History = [System.Collections.Generic.List[object]]::new()
        Mock Start-Sleep {}
        Mock Write-LogMessage {}
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'tenant-guid'; defaultDomainName = 'contoso.com'; displayName = 'Contoso' } }
        Mock Get-CIPPTable { @{ TableName = $TableName } }
        Mock Add-CIPPAzDataTableEntity { $script:History.Add($Entity) }
        Mock New-GraphGetRequest {
            if ($uri -like '*/search/query*') {
                $script:Searches.Add($uri)
                return New-SearchResponse -Files @(@{ Name = 'db.bak'; Folder = '/sites/Backups/Shared Documents/SQL' }, @{ Name = 'old #1.bak'; Folder = '/sites/Backups/Shared Documents' })
            }
            [pscustomobject]@{ Name = 'x' }
        }
        Mock New-GraphPOSTRequest { $script:Deletes.Add([pscustomobject]@{ Uri = $uri; Headers = $AddedHeaders }) }
        Mock Submit-CIPPSPOCleanupErrorTicket {}
    }

    It 'searches by type, a byte-sized threshold and the cutoff, without trimming duplicates' {
        Invoke-Cleanup | Out-Null
        $Query = [uri]::UnescapeDataString($script:Searches[0])
        $Query | Should -Match ([regex]::Escape("path:""$($script:Site)"" AND filetype:bak AND size>10485 AND write<"""))
        $Query | Should -Match 'trimduplicates=false'
    }

    It 'converts megabytes to bytes (100 MB -> 104857600)' {
        Invoke-Cleanup -Extra @{ MinimumFileSizeMB = 100 } | Out-Null
        [uri]::UnescapeDataString($script:Searches[0]) | Should -Match 'size>104857600 '
    }

    It 'permanently deletes each match and records it in the history table' {
        $Result = Invoke-Cleanup
        $Result.Found | Should -Be 2
        $Result.Deleted | Should -Be 2
        $script:Deletes.Count | Should -Be 2
        $script:Deletes[0].Headers['X-HTTP-Method'] | Should -Be 'DELETE'
        $script:Deletes[0].Uri | Should -Not -Match 'recycle'
        $script:Deletes[0].Uri | Should -BeLike "*/_api/web/GetFileByServerRelativePath(decodedurl='/sites/Backups/Shared%20Documents/SQL/db.bak')"
        $script:Deletes[1].Uri | Should -BeLike '*old%20%231.bak*'
        $script:History.Count | Should -Be 2
        $script:History[0].PartitionKey | Should -Be 'tenant-guid'
        $script:History[0].FilePath | Should -Be '/sites/Backups/Shared Documents/SQL/db.bak'
        Should -Invoke Submit-CIPPSPOCleanupErrorTicket -Times 0
    }

    It 'pages through search results 500 at a time' {
        $script:Page = 0
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/search/query*' } {
            $script:Searches.Add($uri); $script:Page++
            if ($script:Page -le 2) { New-SearchResponse -Files @(@{ Name = "f$($script:Page).bak"; Folder = '/sites/Backups/Docs' }) -Total 1200 } else { New-SearchResponse -Files @() -Total 1200 }
        }
        (Invoke-Cleanup).Found | Should -Be 2
        $script:Searches[1] | Should -Match 'startrow=500&'
    }

    It 'treats a file the search index still lists but that is gone as already deleted' {
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*GetFileByServerRelativePath*db.bak*' } { throw 'Response status code does not indicate success: 404 (Not Found).' }
        $Result = Invoke-Cleanup
        $Result.Deleted | Should -Be 1
        $Result.Missing | Should -Be 1
        $Result.Errors.Count | Should -Be 0
    }

    It 'changes nothing on a dry run' {
        $Result = Invoke-Cleanup -Extra @{ DryRun = $true }
        $Result.Found | Should -Be 2
        Should -Invoke New-GraphPOSTRequest -Times 0
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
        Should -Invoke Write-LogMessage -ParameterFilter { $message -like 'Dry run: 2 file(s) on*would be deleted*' }
    }

    It 'collects errors, keeps going, and raises one ticket' {
        Mock New-GraphPOSTRequest -ParameterFilter { $uri -like '*db.bak*' } { throw 'Access denied' }
        $Result = Invoke-Cleanup -Extra @{ SiteUrlsCsv = "$($script:Site), https://evil.example/sites/x" }
        $Result.Deleted | Should -Be 1
        $Result.Errors.Count | Should -Be 2
        $Result.Errors | Should -Contain 'Could not delete /sites/Backups/Shared Documents/SQL/db.bak: Access denied'
        ($Result.Errors -like 'Skipped site https://evil.example/sites/x*').Count | Should -Be 1
        Should -Invoke Submit-CIPPSPOCleanupErrorTicket -Times 1 -ParameterFilter { $ErrorMessages.Count -eq 2 -and $FilesDeleted -eq 1 }
    }

    It 'refuses to run with unsafe or empty settings' -TestCases @(
        @{ Extra = @{ FileTypesCsv = ' , ' }; Reason = 'no file types' }
        @{ Extra = @{ FileTypesCsv = 'bak OR filetype:docx' }; Reason = 'plain extensions' }
        @{ Extra = @{ SiteUrlsCsv = ',' }; Reason = 'no site URLs' }
        @{ Extra = @{ LastModifiedDays = 0 }; Reason = 'at least 1' }
    ) {
        { Invoke-Cleanup -Extra $Extra } | Should -Throw "*$Reason*"
        Should -Invoke New-GraphGetRequest -Times 0
    }
}

Describe 'Submit-CIPPSPOCleanupErrorTicket' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Get-CIPPTable { @{} }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ config = '{"Autotask":{"Enabled":true,"APIUser":"api@fulcra.example"}}' } }
        Mock Get-ExtensionMapping { @([pscustomobject]@{ RowKey = 'tenant-guid'; IntegrationId = '42' }) }
        Mock New-AutotaskTicket { $script:Ticket = [pscustomobject]@{ Company = $atCompanyId; Title = $title; Body = $description; Issue = $issueType; SubIssue = $subIssueType; Config = $Configuration }; 'Created Autotask ticket T1 (id 1)' }
        $script:Tenant = [pscustomobject]@{ customerId = 'tenant-guid'; defaultDomainName = 'contoso.com'; displayName = 'Contoso' }
    }

    It 'tickets the mapped company with the errors listed and the config passed explicitly' {
        Submit-CIPPSPOCleanupErrorTicket -Tenant $script:Tenant -ErrorMessages @('Search failed <x>') -FilesFound 3 -FilesDeleted 2 -SiteCount 1
        $script:Ticket.Company | Should -Be '42'
        $script:Ticket.Title | Should -BeLike 'SharePoint file cleanup errors - contoso.com - *'
        $script:Ticket.Body | Should -Match '<li>Search failed &lt;x&gt;</li>'
        $script:Ticket.Body | Should -Match '2 of 3 matching file\(s\) deleted across 1 site'
        "$($script:Ticket.Issue)/$($script:Ticket.SubIssue)" | Should -Be '29/327'
        $script:Ticket.Config.APIUser | Should -Be 'api@fulcra.example'
    }

    It 'uses company 0 with a warning when the tenant is not mapped' {
        Mock Get-ExtensionMapping { @() }
        Submit-CIPPSPOCleanupErrorTicket -Tenant $script:Tenant -ErrorMessages @('e')
        $script:Ticket.Company | Should -Be 0
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Warning' -and $message -like '*company 0*' }
    }

    It 'does nothing but warn when Autotask is off' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ config = '{"Autotask":{"Enabled":false}}' } }
        Mock New-AutotaskTicket {}
        Submit-CIPPSPOCleanupErrorTicket -Tenant $script:Tenant -ErrorMessages @('e')
        Should -Invoke New-AutotaskTicket -Times 0
    }
}
