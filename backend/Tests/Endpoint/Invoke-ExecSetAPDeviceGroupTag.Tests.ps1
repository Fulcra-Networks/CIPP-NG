# Pester tests for Invoke-ExecSetAPDeviceGroupTag (Fulcra migration plan 09).
# The list page now sends the group tag as a dropdown option ({label, value}) instead of a string.
# Both shapes must set the same tag, and the "(clear tag)" option (value '') must clear it.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecSetAPDeviceGroupTag.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $method) }
    function Write-LogMessage { param($Headers, $API, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }

    . $FunctionPath

    function Invoke-SetTag {
        param($GroupTag)
        $Body = [pscustomobject]@{ tenantFilter = 'contoso.com'; deviceId = 'dev-1'; serialNumber = 'SN1'; groupTag = $GroupTag }
        # Round-trip through JSON so the body has the same shape the HTTP layer produces.
        Invoke-ExecSetAPDeviceGroupTag -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecSetAPDeviceGroupTag' }; Headers = @{}; Body = ($Body | ConvertTo-Json -Depth 5 | ConvertFrom-Json) })
    }
}

Describe 'Invoke-ExecSetAPDeviceGroupTag' {
    BeforeEach {
        $script:Sent = $null
        Mock New-GraphPOSTRequest { $script:Sent = $body | ConvertFrom-Json }
        Mock Write-LogMessage {}
    }

    It 'sets the tag from a dropdown option' {
        $Response = Invoke-SetTag -GroupTag @{ label = 'BLY-Shared'; value = 'BLY-Shared' }
        $Response.StatusCode | Should -Be 200
        $script:Sent.groupTag | Should -Be 'BLY-Shared'
        Should -Invoke New-GraphPOSTRequest -ParameterFilter { $uri -like '*windowsAutopilotDeviceIdentities/dev-1/UpdateDeviceProperties' -and $tenantid -eq 'contoso.com' }
    }

    It 'still accepts a plain string' {
        Invoke-SetTag -GroupTag 'ManagedPC' | Out-Null
        $script:Sent.groupTag | Should -Be 'ManagedPC'
    }

    It 'clears the tag with the (clear tag) option' {
        (Invoke-SetTag -GroupTag @{ label = '(clear tag)'; value = '' }).StatusCode | Should -Be 200
        $script:Sent.groupTag | Should -Be ''
    }

    It 'rejects a tag over 128 characters without calling Graph' {
        (Invoke-SetTag -GroupTag @{ label = 'x'; value = ('x' * 129) }).StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0
    }
}
