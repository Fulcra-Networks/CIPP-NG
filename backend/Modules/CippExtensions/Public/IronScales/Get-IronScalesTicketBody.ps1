function Get-IronScalesTicketBody {
    <#
    .SYNOPSIS
        Builds the Autotask ticket body for one company's unclassified IronScales incidents.
    .DESCRIPTION
        Fulcra custom extension (migration plan 02). One block per incident, then the link to the
        IronScales classification page. Returned as HTML with every value encoded:
        New-AutotaskTicket turns it into plain text, and an email subject such as
        'Invoice <INV-1>' would otherwise be taken for a tag and stripped.

        Fixes from the fork: each incident appears once (the fork's '$body += $body += ...' repeated
        and compounded them), and the stray backtick before 'Email Recipient' is gone.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$CompanyName,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Incidents
    )

    $Encode = { param($Value) [System.Net.WebUtility]::HtmlEncode(("$Value" -replace '[“”]', '')) }
    $Url = 'https://members.ironscales.com/irontraps/incidents/unclassified'

    $Blocks = foreach ($Incident in $Incidents) {
        $Lines = @(
            "Email Subject: $(& $Encode $Incident.emailSubject)"
            "Email Sender Address: $(& $Encode $Incident.senderEmail)"
            "Email Sender Name: $(& $Encode $Incident.senderName)"
            "Email Recipient: $(& $Encode $Incident.recipientEmail)"
            "Affected Mailboxes: $(& $Encode $Incident.affectedMailboxesCount)"
            "Reported By: $(& $Encode $Incident.reportedBy)"
        )
        "<p>$($Lines -join '<br>')</p>"
    }

    $Count = @($Incidents).Count
    $Intro = "<p>$Count unclassified IronScales incident$(if ($Count -ne 1) { 's' }) for $(& $Encode $CompanyName).</p>"
    $Link = "<p>To classify the incident(s) go to <a href=`"$Url`">$Url</a></p>"
    return ($Intro + ($Blocks -join '') + $Link)
}
