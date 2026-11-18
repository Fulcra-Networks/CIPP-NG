Function Invoke-ExecAutotaskTestTicket {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Extension.ReadWrite
    .SYNOPSIS
        Create an Autotask test ticket so admins can check the integration works without waiting
        for a real alert to fire. Covers auth, the HTML-to-text body conversion and the
        hard-coded queue, billing code and issue type. Always tickets the base company (0).

        Fulcra custom extension (migration plan 01). Calls New-AutotaskTicket directly rather
        than going through Send-CIPPAlert, so the [CIPP] title prefix is not exercised here.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $StatusCode = [HttpStatusCode]::OK
    try {
        $Configuration = Get-AutotaskConfiguration

        if (-not $Configuration -or -not $Configuration.Enabled) {
            $Results = [pscustomobject]@{ Results = 'Autotask integration is not enabled. Save the integration with Enable Integration ticked, then try again.' }
        } else {
            # Always the Fulcra base company (0), never a client's account: a test ticket on a
            # client company can show up in their portal. Company 0 is also where unmapped
            # alerts go (D-025), so this exercises a real alert path.
            $CompanyId = 0
            $CompanyName = 'Fulcra base company'

            $Timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ssZ')
            $Title = 'Test ticket from CIPP integration'
            $Description = @"
<p>This is a <strong>test ticket</strong> created by CIPP at $Timestamp to verify end-to-end Autotask delivery.</p>
<p>Target company: <strong>$CompanyName</strong> (id $CompanyId).</p>
<table><tr><th>Check</th><th>Expected</th></tr><tr><td>Queue</td><td>Level I Support</td></tr><tr><td>Issue</td><td>Service Management / Other</td></tr></table>
<p>It is safe to close this ticket.</p>
"@
            $Result = New-AutotaskTicket -atCompanyId $CompanyId -title $Title -description $Description -issueType 29 -subIssueType 327 -Configuration $Configuration
            if ("$Result" -match '^(Failed|Error)') { $StatusCode = [HttpStatusCode]::InternalServerError }
            $Results = [pscustomobject]@{ Results = "$Result against company '$CompanyName' (id $CompanyId). It is safe to close this ticket." }
        }
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Results = [pscustomobject]@{ Results = "Failed to create Autotask test ticket: $($_.Exception.Message). Line $($_.InvocationInfo.ScriptLineNumber)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
