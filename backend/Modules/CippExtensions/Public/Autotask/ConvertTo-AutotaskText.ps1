function ConvertTo-AutotaskText {
    <#
    .SYNOPSIS
        Converts a CIPP alert HTML fragment into readable plain text for an Autotask ticket.
    .DESCRIPTION
        Fulcra custom extension (migration plan 01, D-024). Autotask ticket descriptions are plain
        text, and simply stripping tags runs table cells together. This keeps the structure:

          - a table with a header row becomes one block per data row, as 'Header: value' lines,
            with a blank line between rows (empty values are left out);
          - a table without a header row (ConvertTo-Html -As List) becomes one 'Name: value'
            line per row;
          - links become 'text: url', list items become '- item', paragraphs and <br> become
            line breaks, and HTML entities are decoded.

        Text that contains no tags is returned unchanged (trimmed).
    .PARAMETER Html
        The alert body, normally from New-CIPPAlertTemplate -Format psa.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Html
    )

    if ($Html -notmatch '<[a-zA-Z!/][^>]*>') { return $Html.Trim() }

    $Decode = { param($s) [System.Net.WebUtility]::HtmlDecode(($s -replace '<[^>]+>', '')).Trim() }

    $Text = $Html -replace '(?s)<!--.*?-->', '' -replace '(?is)<(style|script|head)\b[^>]*>.*?</\1>', '' -replace '(?is)<colgroup\b.*?</colgroup>', ''

    # Links first, so the url survives the tag strip. Bare links (text == url) are written once.
    $Text = [regex]::Replace($Text, '(?is)<a\b[^>]*?href\s*=\s*"([^"]*)"[^>]*>(.*?)</a>', {
            param($m)
            $Url = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value).Trim()
            $Label = & $Decode $m.Groups[2].Value
            if (-not $Label -or $Label -eq $Url) { $Url } else { "$($Label): $Url" }
        })

    # Tables become text blocks, each placed on its own lines.
    $Text = [regex]::Replace($Text, '(?is)<table\b[^>]*>(.*?)</table>', {
            param($m)
            $Rows = foreach ($Row in [regex]::Matches($m.Groups[1].Value, '(?is)<tr\b[^>]*>(.*?)</tr>')) {
                $Cells = foreach ($Cell in [regex]::Matches($Row.Groups[1].Value, '(?is)<(t[hd])\b[^>]*>(.*?)</t[hd]>')) {
                    [pscustomobject]@{ IsHeader = $Cell.Groups[1].Value -ieq 'th'; Value = (& $Decode $Cell.Groups[2].Value) }
                }
                if ($Cells) { , @($Cells) }
            }
            $Rows = @($Rows)
            if ($Rows.Count -eq 0) { return '' }

            $Lines = [System.Collections.Generic.List[string]]::new()
            $Headers = $null
            if (@($Rows[0] | Where-Object { -not $_.IsHeader }).Count -eq 0) {
                $Headers = @($Rows[0].Value)
                $Rows = @($Rows | Select-Object -Skip 1)
            }
            foreach ($Row in $Rows) {
                $Values = @($Row.Value)
                if ($Headers) {
                    if ($Lines.Count -gt 0) { $Lines.Add('') }
                    for ($i = 0; $i -lt $Values.Count; $i++) {
                        if ([string]::IsNullOrWhiteSpace($Values[$i])) { continue }
                        $Name = if ($i -lt $Headers.Count -and $Headers[$i]) { $Headers[$i] } else { "Column $($i + 1)" }
                        $Lines.Add("$($Name.TrimEnd(':')): $($Values[$i])")
                    }
                } elseif ($Values.Count -eq 2) {
                    $Lines.Add("$($Values[0].TrimEnd(':')): $($Values[1])")
                } else {
                    $Lines.Add(($Values | Where-Object { $_ }) -join ' | ')
                }
            }
            "`n`n$($Lines -join "`n")`n`n"
        })

    $Text = $Text -replace '(?i)<br\s*/?>', "`n" -replace '(?i)<li\b[^>]*>', "`n- " -replace '(?i)</li>', '' -replace '(?i)</(p|div|ul|ol|h[1-6]|tr)>', "`n" -replace '(?i)<(p|div|h[1-6])\b[^>]*>', "`n"
    $Text = [System.Net.WebUtility]::HtmlDecode(($Text -replace '<[^>]+>', ''))

    # Tidy whitespace: trim each line, and collapse runs of blank lines to one.
    $Text = ($Text -split '\r?\n' | ForEach-Object { ($_ -replace '[ \t ]+', ' ').Trim() }) -join "`n"
    $Text = $Text -replace '\n{3,}', "`n`n"
    return $Text.Trim()
}
