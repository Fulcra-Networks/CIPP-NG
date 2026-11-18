function New-AutotaskTicket {
    <#
    .SYNOPSIS
        Creates an Autotask ticket.
    .DESCRIPTION
        Fulcra custom extension (migration plan 01). Called by New-CippExtAlert for CIPP alerts,
        and by plans 02 (IronScales) and 07 (SharePoint BAK cleanup).

        The Fulcra Autotask instance ids (queue, billing code, SLA, category, source, status) are
        hard-coded in $Defaults below (D-026). The picklist values they come from are listed at
        the end of this file. HTML descriptions are converted to readable text
        (ConvertTo-AutotaskText) and cut to Autotask's 8000-character limit; titles to 255.

        Returns one line, which Send-CIPPAlert reads: 'Created Autotask ticket ...' on success,
        'Failed to create Autotask ticket: ...' on failure. It never throws.
    .PARAMETER atCompanyId
        Autotask company id. 0 is the Fulcra base company.
    .PARAMETER priority
        Autotask priority value: 1 High, 2 Normal, 4 Critical.
    .PARAMETER Configuration
        Autotask configuration block. Defaults to the stored one. (The fork read a $Configuration
        variable from the caller's scope; plan 07 set it globally to make that work.)
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Alias('atCompany')]
        $atCompanyId,
        $title,
        $description,
        $estHr = 0.1,
        $issueType,
        $subIssueType,
        $ticketType = '5',
        $priority = '2',
        $Configuration
    )

    # Fulcra Autotask instance values. See the picklist reference at the end of this file.
    $Defaults = @{
        TicketCategory          = 3          # Standard
        ServiceLevelAgreementID = 1
        Source                  = 8          # Monitoring Alert
        Status                  = 1          # New
        QueueID                 = 29682833   # Level I Support
        BillingCodeID           = 29682801   # Work type: Remote
    }
    $MaxDescription = 8000   # Tickets.description is string(8000); longer bodies reject the whole create.
    $MaxTitle = 255

    try {
        $CompanyId = 0L
        if (-not [long]::TryParse("$atCompanyId", [ref]$CompanyId) -or $CompanyId -lt 0) {
            throw "'$atCompanyId' is not a valid Autotask company id."
        }

        $Body = ConvertTo-AutotaskText -Html "$description"
        if ($Body.Length -gt $MaxDescription) {
            $Suffix = "`n...[truncated $($Body.Length - $MaxDescription) chars - see CIPP for full details]"
            $Body = $Body.Substring(0, $MaxDescription - $Suffix.Length) + $Suffix
        }
        $Title = "$title".Trim()
        if ($Title.Length -gt $MaxTitle) { $Title = $Title.Substring(0, $MaxTitle - 3) + '...' }

        # Field names as in the swagger TicketModel (what New-AutotaskBody produced in the fork).
        $Ticket = [ordered]@{
            Id                      = 0
            CompanyID               = $CompanyId
            Title                   = $Title
            Description             = $Body
            Priority                = [int]"$priority"
            TicketType              = [int]"$ticketType"
            EstimatedHours          = $estHr
            TicketCategory          = $Defaults.TicketCategory
            ServiceLevelAgreementID = $Defaults.ServiceLevelAgreementID
            Source                  = $Defaults.Source
            Status                  = $Defaults.Status
            QueueID                 = $Defaults.QueueID
            BillingCodeID           = $Defaults.BillingCodeID
        }
        if ("$issueType") { $Ticket.IssueType = [int]"$issueType" }
        if ("$subIssueType") { $Ticket.SubIssueType = [int]"$subIssueType" }

        if (-not $PSCmdlet.ShouldProcess("Autotask company $CompanyId", 'Create ticket')) { return }

        Get-AutotaskToken -Configuration $Configuration
        Write-Information "Creating Autotask ticket for company $CompanyId (issue $issueType/$subIssueType, type $ticketType, priority $priority)"
        $Created = New-AutotaskAPIResource -Resource Tickets -Body ([pscustomobject]$Ticket) -ErrorAction Stop
        if (-not $Created.itemId) {
            throw 'Autotask accepted the request but returned no ticket id.'
        }

        # The ticket number (T2026...) is what technicians search for. Best effort only.
        $Label = "id $($Created.itemId)"
        try {
            $Number = (Get-AutotaskAPIResource -Resource Tickets -ID $Created.itemId -ErrorAction Stop).ticketNumber
            if ($Number) { $Label = "$Number (id $($Created.itemId))" }
        } catch {
            Write-Information "Could not read back Autotask ticket $($Created.itemId): $($_.Exception.Message)"
        }
        Write-LogMessage -API 'Autotask' -tenant 'CIPP' -message "Created Autotask ticket $Label for company $CompanyId" -sev Debug
        return "Created Autotask ticket $Label"
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.Message
        }
        Write-LogMessage -API 'Autotask' -tenant 'CIPP' -message "Failed to create Autotask ticket for company $($atCompanyId): $Message" -sev Error
        return "Failed to create Autotask ticket: $Message"
    }
}

<# Fulcra Autotask picklist reference (captured from the instance by the old fork)

TICKET STATUS:  New 1, Complete 5, Waiting Customer 7, In Progress 8, Waiting Materials 9,
                Waiting Vendor 12, Change Order 15, On Hold 17, Outsourced 20, Accounting 21
TICKET TYPES:   Service Request 1, Incident 2, Problem 3, Change Request 4, Alert 5
PRIORITY:       High 1, Normal 2, Critical 4
SOURCE:         Insourced -2, Client Portal -1, Phone 2, Email 4, In Person/Onsite 6,
                Monitoring Alert 8, Verbal 11
CATEGORY:       AEM Alert 2, Standard 3, Datto Alert 4, RMA 5, Datto Networking Alert 6
QUEUES:         Client Portal 5, Post Sale 6, Monitoring Alert 8, Level I Support 29682833,
                Level II Support 29682969, Recurring Tickets 29683354, Renewals 29683479,
                Managed Service Config 29683480, Internal 29683481, Waiting Customer 29683482,
                Outsourced 29683483, Accounting 29683484, Taskfire Email Handler 29683485
ISSUE TYPES:    Server 7, Computer 10, Network 11, User 16, Sales 19, Management 20,
                Phones / Mobile Devices 25, Block Time 26, Backup / Restore 27, Security 28,
                Service Management 29, Printer / Scanner 30, Other 31
SUB-ISSUE TYPES (alerts use Service Management / Other = 327):
                 Applications - Other 104, Firewall/Router 112, WAP 116, AntiVirus 132, Backup 133,
                 Desktop 134, E-Mail 135, Firewall 136, Internet 137, Network 139, Other 140,
                 Phone 141, Point of Sale 142, Printer 143, Router 144, Server 145, Software 146,
                 Virus Removal 147, Website 148, Wireless 149, Workstation 150, Hardware 152,
                 Operating System 153, Backup 169, Connectivity 170, Disk Space 171, Firewall 172,
                 Hardware 173, Internet 174, Intranet/LAN 175, Network 176, Phone 177,
                 Point of Sale 178, Printer 179, Router 180, Server 181, Software 182,
                 Workstation 183, Cabling 184, Configuration 185, ISP 189, VPN 198, Switch 199,
                 E-mail 200, Firewall 201, Hardware 202, Internet 203, Intranet/LAN 204,
                 Network 205, Phone 206, Point of Sale 207, Printer 208, Router 209, Server 210,
                 Software 211, Workstation 212, Application 215, Hardware 217, Change 223,
                 SharePoint Online 225, Exchange Online 226, Skype for Business 227,
                 OneDrive for Business Sync 228, OneDrive for Business Config 229,
                 Dynamics CRM 231, Mozy 233, DNS 235, Domain Renewal 236, Application 237,
                 Report 238, Integration 239, Automation 240, Fulcra Solution 241,
                 Order Fulfillment 242, Delivery 243, Onsite Support 244, Configuration 245,
                 Surveillance - Camera 247, Surveillance - NVR/DVR 248, Client Meeting 252,
                 CCTV 254, CCTV 255, Accounting 256, HR 257, A/P 258, A/R 259, Monitoring 260,
                 Antivirus 261, AntiVirus 262, Backup 263, CCTV 264, E-Mail 265, Firewall 266,
                 Internet 267, Network 268, Onsite Maintenance 269, Other 270,
                 Patch Management 271, Phone 272, Point of Sale 273, Printer 274, Router 275,
                 Server 276, Software 277, Website 278, Wireless 279, Workstation 280,
                 Security 281, User 285, Computer 286, Operating System 287, Updates 288,
                 Desk Phone 289, Mobile Device 290, Support 291, Patch Management 292,
                 Authentication / MFA 293, Email Security 294, Device Management 295,
                 Audit / Test 296, Restore 297, Reporting 298, Configuration 299,
                 Tape Management 300, Onboarding 301, Offboarding 302, Offboarding 303,
                 Applications - Office 305, Transfer 306, Updates 307, Connectivity 308,
                 Onboarding 309, Offboarding 310, Password 311, Authentication 312, Licensing 313,
                 Access 314, Training / Question 315, Remediation - Computer Malware Event 316,
                 Malware Software Issue 317, Remediation - User Compromise 318, Updates 319,
                 Updates 320, Authentication 321, Email 322, Email Security 323,
                 Endpoint - Security 324, Endpoint - Config 325, Backup 326, Other 327,
                 Network - Cloud Management 328, Driver - 3rd Party 329, Driver - Windows 330,
                 Scanner 331, Printer 332, Other 333, PSA 334, RMM 335, Backup 336
#>
