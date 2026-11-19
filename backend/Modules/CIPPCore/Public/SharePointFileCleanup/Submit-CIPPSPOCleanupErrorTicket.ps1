function Submit-CIPPSPOCleanupErrorTicket {
    <#
    .SYNOPSIS
        Raises one Autotask ticket listing the errors from a SharePoint file cleanup run.
    .DESCRIPTION
        Fulcra custom (migration plan 07). Uses the Autotask integration from plan 01, with the
        configuration passed explicitly (the old job set a global variable for it). The ticket goes to
        the tenant's mapped Autotask company, or the base company (0) with a warning when the tenant is
        not mapped, the same as alert tickets (D-025).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Tenant,
        [Parameter(Mandatory = $true)][string[]]$ErrorMessages,
        [int]$FilesFound,
        [int]$FilesDeleted,
        [int]$SiteCount
    )

    $API = 'SharePointFileCleanup'
    try {
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = (Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CippExtensions' and RowKey eq 'Config'").config | ConvertFrom-Json -Depth 10
    } catch {
        Write-LogMessage -API $API -tenant $Tenant.defaultDomainName -message "Could not read the extension configuration, so no error ticket was created: $($_.Exception.Message)" -sev Error
        return
    }
    if ($Configuration.Autotask.Enabled -ne $true) {
        Write-LogMessage -API $API -tenant $Tenant.defaultDomainName -message 'Autotask is not enabled, so no error ticket was created.' -sev Warning
        return
    }

    $Mapping = @(Get-ExtensionMapping -Extension 'Autotask') | Where-Object { $_.RowKey -eq $Tenant.customerId } | Select-Object -First 1
    $CompanyId = if ($Mapping.IntegrationId -match '^\d+$') { $Mapping.IntegrationId } else {
        Write-LogMessage -API $API -tenant $Tenant.defaultDomainName -message 'The tenant is not mapped to an Autotask company, so the error ticket goes to company 0.' -sev Warning
        0
    }

    $Now = (Get-Date).ToUniversalTime()
    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add("<p>SharePoint file cleanup hit $($ErrorMessages.Count) error(s) for $($Tenant.displayName) ($($Tenant.defaultDomainName)) on $($Now.ToString('yyyy-MM-dd HH:mm')) UTC.</p>")
    $Lines.Add("<p>Summary: $FilesDeleted of $FilesFound matching file(s) deleted across $SiteCount site(s).</p>")
    $Lines.Add('<ul>')
    foreach ($Message in $ErrorMessages) { $Lines.Add("<li>$([System.Net.WebUtility]::HtmlEncode($Message))</li>") }
    $Lines.Add('</ul>')

    $Result = New-AutotaskTicket -atCompanyId $CompanyId -title "SharePoint file cleanup errors - $($Tenant.defaultDomainName) - $($Now.ToString('yyyy-MM-dd'))" `
        -description ($Lines -join '') -issueType '29' -subIssueType '327' -Configuration $Configuration.Autotask
    $Sev = if ("$Result" -match '^(Failed|Error)') { 'Error' } else { 'Info' }
    Write-LogMessage -API $API -tenant $Tenant.defaultDomainName -message "SharePoint file cleanup error ticket: $Result" -sev $Sev
}
