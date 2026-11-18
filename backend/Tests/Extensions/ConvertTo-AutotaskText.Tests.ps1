# Pester tests for ConvertTo-AutotaskText (Fulcra migration plan 01, D-024).
# Autotask ticket bodies are plain text. The alert pipeline hands over the HTML fragment from
# New-CIPPAlertTemplate -Format psa (tables restyled by ConvertTo-PSAHtml), and a plain tag strip
# runs table cells together, so the structure has to survive as 'Header: value' lines.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/Autotask/ConvertTo-AutotaskText.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/ConvertTo-PSAHtml.ps1')
}

Describe 'ConvertTo-AutotaskText' {
    It 'returns plain text unchanged' {
        ConvertTo-AutotaskText -Html '  just text  ' | Should -Be 'just text'
    }

    It 'returns an empty string for empty input' {
        ConvertTo-AutotaskText -Html '' | Should -Be ''
    }

    It 'turns a header table into one Header: value block per row' {
        $Data = @(
            [pscustomobject]@{ Message = 'User added to admins'; Tenant = 'contoso.com'; Severity = 'Alert' }
            [pscustomobject]@{ Message = 'Mailbox forwarding set'; Tenant = 'contoso.com'; Severity = 'Warning' }
        )
        $Html = ConvertTo-PSAHtml -Html ('<p>The following alerts match your configured rules</p>' + ($Data | ConvertTo-Html -Fragment | Out-String))

        $Text = ConvertTo-AutotaskText -Html $Html

        $Text | Should -Be (@(
                'The following alerts match your configured rules'
                ''
                'Message: User added to admins'
                'Tenant: contoso.com'
                'Severity: Alert'
                ''
                'Message: Mailbox forwarding set'
                'Tenant: contoso.com'
                'Severity: Warning'
            ) -join "`n")
    }

    It 'leaves out empty cells' {
        $Html = ([pscustomobject]@{ Name = 'x'; Empty = '' } | ConvertTo-Html -Fragment | Out-String)
        ConvertTo-AutotaskText -Html $Html | Should -Be 'Name: x'
    }

    It 'turns a list table (no header row) into Name: value lines' {
        $Html = ([pscustomobject]@{ City = 'Denver'; Country = 'US' } | ConvertTo-Html -Fragment -As List | Out-String)
        ConvertTo-AutotaskText -Html $Html | Should -Be "City: Denver`nCountry: US"
    }

    It 'keeps link targets' {
        ConvertTo-AutotaskText -Html '<p><a href="https://cipp.example/cipp/logs">Open CIPP</a></p>' | Should -Be 'Open CIPP: https://cipp.example/cipp/logs'
        ConvertTo-AutotaskText -Html '<a href="https://x.example">https://x.example</a>' | Should -Be 'https://x.example'
    }

    It 'decodes entities and renders lists and line breaks' {
        $Text = ConvertTo-AutotaskText -Html '<p>A &amp; B<br/>next</p><ul><li>one</li><li>two &lt;3</li></ul>'
        $Text | Should -Be "A & B`nnext`n`n- one`n- two <3"
    }

    It 'drops style blocks and comments' {
        ConvertTo-AutotaskText -Html '<style>p{color:red}</style><!-- hidden --><p>shown</p>' | Should -Be 'shown'
    }
}
