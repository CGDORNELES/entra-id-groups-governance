<#
.SYNOPSIS
    Assess Entra ID group activity and usage patterns
.DESCRIPTION
    This script analyzes group activity including:
    - Last activity in group-enabled services (Teams, SharePoint, Exchange)
    - Recent membership changes
    - Group conversation activity
    - File activity in associated SharePoint sites
    - Last sign-in of group members
.AUTHOR
    Clairo Dorneles (clairo@clairodorneles.cloud)
.DATE
    2025-06-13
#>

param(
    [Parameter(Mandatory=$false)]
    [int]$InactiveDaysThreshold = 90,  # Groups with no activity for this many days are considered inactive
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\EntraID_GroupActivity_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
)

# Check and import required modules
$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Groups',
    'Microsoft.Graph.Reports',
    'Microsoft.Graph.Sites',
    'Microsoft.Graph.Teams',
    'Microsoft.Graph.Users',
    'Microsoft.Graph.Beta.Reports'  # Beta module for some report cmdlets
)

Write-Host "Checking required modules..." -ForegroundColor Cyan
foreach ($module in $requiredModules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module $module not found. Installing..." -ForegroundColor Yellow
        try {
            Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
            Write-Host "Module $module installed successfully" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to install module $module. Please install manually." -ForegroundColor Red
            Write-Host "Run: Install-Module -Name $module -Scope CurrentUser" -ForegroundColor Yellow
        }
    }
    Import-Module $module -ErrorAction SilentlyContinue
}

# Create output directory
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

Write-Host "`nEntra ID Group Activity Assessment - Started at $(Get-Date)" -ForegroundColor Green
Write-Host "Inactive threshold: $InactiveDaysThreshold days" -ForegroundColor Yellow
Write-Host "Output directory: $OutputPath" -ForegroundColor Yellow

# Connect to Microsoft Graph with required scopes
function Connect-MicrosoftGraphForActivity {
    $RequiredScopes = @(
        "Group.Read.All",
        "Directory.Read.All",
        "Reports.Read.All",
        "Sites.Read.All",
        "TeamSettings.Read.All",
        "Mail.Read",
        "AuditLog.Read.All",
        "User.Read.All"
    )
    
    try {
        Connect-MgGraph -Scopes $RequiredScopes -ErrorAction Stop
        Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
        
        # Show current context
        $context = Get-MgContext
        Write-Host "Connected as: $($context.Account)" -ForegroundColor Cyan
    }
    catch {
        Write-Host "Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
        exit 1
    }
}

# Function to get Microsoft 365 group activity using the correct cmdlet
function Get-M365GroupActivity {
    Write-Host "`nFetching Microsoft 365 group activity reports..." -ForegroundColor Cyan
    
    try {
        # Try using the beta endpoint first
        $tempFile = Join-Path $env:TEMP "m365groups_activity_temp.csv"
        
        # Get the activity report - this cmdlet exports to a file
        try {
            # Try the v1.0 endpoint
            Get-MgReportOffice365GroupActivityDetail -Period D180 -OutFile $tempFile
        }
        catch {
            Write-Host "Trying alternative method..." -ForegroundColor Yellow
            # Try beta endpoint with Invoke-MgGraphRequest
            $uri = "https://graph.microsoft.com/v1.0/reports/getOffice365GroupsActivityDetail(period='D180')"
            $response = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputFilePath $tempFile
        }
        
        # Copy to output folder
        Copy-Item -Path $tempFile -Destination "$OutputPath\M365GroupActivity_Raw.csv" -Force
        
        # Read and parse the CSV
        $activities = Import-Csv "$OutputPath\M365GroupActivity_Raw.csv"
        
        $groupActivities = @()
        foreach ($activity in $activities) {
            $lastActivity = $null
            $activityDates = @()
            
            # Collect all activity dates - field names might vary
            $dateFields = @(
                'Last Activity Date',
                'Exchange Last Activity Date',
                'SharePoint Last Activity Date', 
                'Teams Last Activity Date',
                'Yammer Last Activity Date'
            )
            
            foreach ($field in $dateFields) {
                if ($activity.$field -and $activity.$field -ne '') {
                    try {
                        $activityDates += [datetime]::Parse($activity.$field)
                    }
                    catch {
                        # Skip invalid dates
                    }
                }
            }
            
            # Get the most recent activity
            if ($activityDates.Count -gt 0) {
                $lastActivity = ($activityDates | Sort-Object -Descending | Select-Object -First 1)
            }
            
            # Parse numeric values safely
            $emailCount = 0
            $fileCount = 0
            $storageBytes = 0
            $messagesCount = 0
            $meetingsCount = 0
            
            if ($activity.'Exchange Received Email Count') { 
                [int]::TryParse($activity.'Exchange Received Email Count', [ref]$emailCount) | Out-Null
            }
            if ($activity.'SharePoint Active File Count') { 
                [int]::TryParse($activity.'SharePoint Active File Count', [ref]$fileCount) | Out-Null
            }
            if ($activity.'SharePoint Site Storage Used (Byte)') { 
                [long]::TryParse($activity.'SharePoint Site Storage Used (Byte)', [ref]$storageBytes) | Out-Null
            }
            if ($activity.'Teams Channel Messages Count') { 
                [int]::TryParse($activity.'Teams Channel Messages Count', [ref]$messagesCount) | Out-Null
            }
            if ($activity.'Teams Meetings Organized Count') { 
                [int]::TryParse($activity.'Teams Meetings Organized Count', [ref]$meetingsCount) | Out-Null
            }
            
            $groupActivity = [PSCustomObject]@{
                GroupId                     = $activity.'Group Id'
                GroupDisplayName            = $activity.'Group Display Name'
                IsDeleted                   = $activity.'Is Deleted'
                MemberCount                 = $activity.'Member Count'
                ExternalMemberCount         = $activity.'External Member Count'
                LastActivityDate            = $lastActivity
                ExchangeReceivedEmailCount  = $emailCount
                SharePointActiveFileCount   = $fileCount
                SharePointTotalFileCount    = $activity.'SharePoint Total File Count'
                SharePointSiteStorageUsedGB = [math]::Round($storageBytes / 1GB, 2)
                TeamsChannelMessagesCount   = $messagesCount
                TeamsMeetingOrganizedCount  = $meetingsCount
                DaysSinceLastActivity       = if ($lastActivity) { (New-TimeSpan -Start $lastActivity -End (Get-Date)).Days } else { $null }
                IsActive                    = if ($lastActivity -and (New-TimeSpan -Start $lastActivity -End (Get-Date)).Days -le $InactiveDaysThreshold) { $true } else { $false }
            }
            
            $groupActivities += $groupActivity
        }
        
        # Clean up temp file
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        
        Write-Host "Retrieved activity data for $($groupActivities.Count) Microsoft 365 groups" -ForegroundColor Green
        return $groupActivities
    }
    catch {
        Write-Host "Error fetching M365 group activity: $_" -ForegroundColor Red
        Write-Host "Attempting alternative approach..." -ForegroundColor Yellow
        
        # Alternative approach: Get basic group info and analyze recent activity
        return Get-M365GroupActivityAlternative
    }
}

# Alternative function to assess M365 group activity
function Get-M365GroupActivityAlternative {
    Write-Host "Using alternative method to assess M365 group activity..." -ForegroundColor Yellow
    
    try {
        $m365Groups = Get-MgGroup -Filter "groupTypes/any(c:c eq 'Unified')" -All -Property Id,DisplayName,CreatedDateTime,LastRenewedDateTime,Mail
        $groupActivities = @()
        $processedCount = 0
        
        foreach ($group in $m365Groups) {
            $processedCount++
            Write-Progress -Activity "Analyzing M365 groups" -Status "Processing group $processedCount of $($m365Groups.Count)" -PercentComplete (($processedCount / $m365Groups.Count) * 100)
            
            # Get member count
            $members = Get-MgGroupMember -GroupId $group.Id -All
            $memberCount = $members.Count
            
            # Check for recent conversations (if mail-enabled)
            $hasRecentActivity = $false
            $lastActivity = $null
            
            # Use creation date as baseline
            if ($group.CreatedDateTime) {
                $lastActivity = [datetime]::Parse($group.CreatedDateTime)
            }
            
            # Check if group was renewed recently (indicates some activity)
            if ($group.LastRenewedDateTime) {
                $renewedDate = [datetime]::Parse($group.LastRenewedDateTime)
                if (!$lastActivity -or $renewedDate -gt $lastActivity) {
                    $lastActivity = $renewedDate
                }
            }
            
            $daysSinceActivity = if ($lastActivity) { (New-TimeSpan -Start $lastActivity -End (Get-Date)).Days } else { $null }
            
            $groupActivity = [PSCustomObject]@{
                GroupId                     = $group.Id
                GroupDisplayName            = $group.DisplayName
                IsDeleted                   = $false
                MemberCount                 = $memberCount
                ExternalMemberCount         = 0
                LastActivityDate            = $lastActivity
                ExchangeReceivedEmailCount  = "N/A"
                SharePointActiveFileCount   = "N/A"
                SharePointTotalFileCount    = "N/A"
                SharePointSiteStorageUsedGB = "N/A"
                TeamsChannelMessagesCount   = "N/A"
                TeamsMeetingOrganizedCount  = "N/A"
                DaysSinceLastActivity       = $daysSinceActivity
                IsActive                    = if ($daysSinceActivity -and $daysSinceActivity -le $InactiveDaysThreshold) { $true } else { $false }
            }
            
            $groupActivities += $groupActivity
        }
        
        Write-Progress -Activity "Analyzing M365 groups" -Completed
        return $groupActivities
    }
    catch {
        Write-Host "Alternative method also failed: $_" -ForegroundColor Red
        return @()
    }
}

# Function to analyze security group activity through audit logs
function Get-SecurityGroupActivity {
    param($SecurityGroups)
    
    Write-Host "`nAnalyzing security group activity through audit logs..." -ForegroundColor Cyan
    
    $groupActivities = @()
    $processedCount = 0
    
    # Calculate date range for audit logs (last 90 days)
    $startDate = (Get-Date).AddDays(-90)
    $endDate = Get-Date
    
    foreach ($group in $SecurityGroups) {
        $processedCount++
        Write-Progress -Activity "Analyzing security groups" -Status "Processing group $processedCount of $($SecurityGroups.Count)" -PercentComplete (($processedCount / $SecurityGroups.Count) * 100)
        
        try {
            # Get member count
            $memberCount = (Get-MgGroupMember -GroupId $group.Id -All).Count
            
            # Try to get audit logs for this group
            $lastModified = $null
            try {
                # Search for recent membership changes
                $auditLogs = Get-MgAuditLogDirectoryAudit -Filter "targetResources/any(x:x/id eq '$($group.Id)')" -Top 1
                
                if ($auditLogs) {
                    $lastModified = $auditLogs.ActivityDateTime
                }
            }
            catch {
                # Audit log access might fail, continue without it
            }
            
            $daysSinceModified = if ($lastModified) { (New-TimeSpan -Start $lastModified -End (Get-Date)).Days } else { $null }
            $daysSinceCreation = if ($group.CreatedDateTime) { (New-TimeSpan -Start $group.CreatedDateTime -End (Get-Date)).Days } else { $null }
            
            $groupActivity = [PSCustomObject]@{
                GroupId                 = $group.Id
                GroupDisplayName        = $group.DisplayName
                GroupType               = if ($group.SecurityEnabled -and $group.MailEnabled) { "Mail-Enabled Security" } 
                                         elseif ($group.SecurityEnabled) { "Security" } 
                                         else { "Distribution" }
                MemberCount             = $memberCount
                LastMembershipChange    = $lastModified
                DaysSinceLastChange     = $daysSinceModified
                CreatedDateTime         = $group.CreatedDateTime
                DaysSinceCreation       = $daysSinceCreation
                IsRecentlyModified      = if ($daysSinceModified -and $daysSinceModified -le $InactiveDaysThreshold) { $true } else { $false }
                HasNoRecentActivity     = if (!$daysSinceModified -or $daysSinceModified -gt $InactiveDaysThreshold) { $true } else { $false }
            }
            
            $groupActivities += $groupActivity
        }
        catch {
            Write-Verbose "Could not analyze activity for group: $($group.DisplayName)"
        }
    }
    
    Write-Progress -Activity "Analyzing security groups" -Completed
    Write-Host "Analyzed activity for $($groupActivities.Count) security groups" -ForegroundColor Green
    return $groupActivities
}

# Function to get member last sign-in activity
function Get-GroupMemberActivity {
    param($GroupId, $GroupName)
    
    try {
        $members = Get-MgGroupMember -GroupId $GroupId -All
        $activeMembers = 0
        $inactiveMembers = 0
        $lastSignIns = @()
        
        foreach ($member in $members) {
            if ($member.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.user') {
                try {
                    # Get user with sign-in activity
                    $user = Get-MgUser -UserId $member.Id -Property SignInActivity,DisplayName,UserPrincipalName
                    
                    if ($user.SignInActivity -and $user.SignInActivity.LastSignInDateTime) {
                        $lastSignIn = [datetime]::Parse($user.SignInActivity.LastSignInDateTime)
                        $lastSignIns += $lastSignIn
                        
                        $daysSinceSignIn = (New-TimeSpan -Start $lastSignIn -End (Get-Date)).Days
                        if ($daysSinceSignIn -le $InactiveDaysThreshold) {
                            $activeMembers++
                        } else {
                            $inactiveMembers++
                        }
                    } else {
                        $inactiveMembers++
                    }
                }
                catch {
                    # Sign-in data might not be available for all users
                    Write-Verbose "Could not retrieve sign-in data for user: $($member.Id)"
                }
            }
        }
        
        $mostRecentMemberActivity = if ($lastSignIns.Count -gt 0) { 
            ($lastSignIns | Sort-Object -Descending | Select-Object -First 1) 
        } else { 
            $null 
        }
        
        return [PSCustomObject]@{
            GroupId                     = $GroupId
            GroupName                   = $GroupName
            TotalMembers                = $members.Count
            ActiveMembers               = $activeMembers
            InactiveMembers             = $inactiveMembers
            PercentActive               = if ($members.Count -gt 0) { [math]::Round(($activeMembers / $members.Count) * 100, 2) } else { 0 }
            MostRecentMemberActivity    = $mostRecentMemberActivity
            DaysSinceMemberActivity     = if ($mostRecentMemberActivity) { (New-TimeSpan -Start $mostRecentMemberActivity -End (Get-Date)).Days } else { $null }
        }
    }
    catch {
        Write-Verbose "Error analyzing member activity for group: $GroupName - $_"
        return $null
    }
}

# Function to generate activity summary
function Get-GroupActivitySummary {
    param($AllGroups, $M365Activities, $SecurityActivities)
    
    Write-Host "`nGenerating activity summary..." -ForegroundColor Cyan
    
    $summaryData = @()
    
    # Process M365 groups
    foreach ($m365Activity in $M365Activities) {
        $group = $AllGroups | Where-Object { $_.Id -eq $m365Activity.GroupId } | Select-Object -First 1
        if ($group) {
            $summary = [PSCustomObject]@{
                GroupId                     = $m365Activity.GroupId
                GroupName                   = $m365Activity.GroupDisplayName
                GroupType                   = "Microsoft 365"
                MemberCount                 = $m365Activity.MemberCount
                LastActivityDate            = $m365Activity.LastActivityDate
                DaysSinceLastActivity       = $m365Activity.DaysSinceLastActivity
                EmailsReceived              = $m365Activity.ExchangeReceivedEmailCount
                ActiveFiles                 = $m365Activity.SharePointActiveFileCount
                TeamsMessages               = $m365Activity.TeamsChannelMessagesCount
                TeamsMeetings               = $m365Activity.TeamsMeetingOrganizedCount
                StorageUsedGB               = $m365Activity.SharePointSiteStorageUsedGB
                ActivityStatus              = if ($m365Activity.IsActive) { "Active" } else { "Inactive" }
                RecommendedAction           = if (!$m365Activity.IsActive) { "Review for archival or deletion" } else { "" }
            }
            $summaryData += $summary
        }
    }
    
    # Process Security groups
    foreach ($secActivity in $SecurityActivities) {
        $summary = [PSCustomObject]@{
            GroupId                     = $secActivity.GroupId
            GroupName                   = $secActivity.GroupDisplayName
            GroupType                   = $secActivity.GroupType
            MemberCount                 = $secActivity.MemberCount
            LastActivityDate            = $secActivity.LastMembershipChange
            DaysSinceLastActivity       = $secActivity.DaysSinceLastChange
            EmailsReceived              = "N/A"
            ActiveFiles                 = "N/A"
            TeamsMessages               = "N/A"
            TeamsMeetings               = "N/A"
            StorageUsedGB               = "N/A"
            ActivityStatus              = if ($secActivity.IsRecentlyModified) { "Active" } else { "Inactive" }
            RecommendedAction           = if ($secActivity.HasNoRecentActivity -and $secActivity.MemberCount -eq 0) { 
                                            "Empty group - Delete" 
                                          } elseif ($secActivity.HasNoRecentActivity) { 
                                            "Review membership and necessity" 
                                          } else { 
                                            "" 
                                          }
        }
        $summaryData += $summary
    }
    
    return $summaryData
}

# Main execution
try {
    # Connect to Microsoft Graph
    Connect-MicrosoftGraphForActivity
    
    # Get all groups first
    Write-Host "`nFetching all groups..." -ForegroundColor Cyan
    $allGroups = Get-MgGroup -All -Property Id,DisplayName,GroupTypes,SecurityEnabled,MailEnabled,CreatedDateTime,LastRenewedDateTime
    
    # Separate groups by type
    $m365Groups = $allGroups | Where-Object { $_.GroupTypes -contains "Unified" }
    $securityGroups = $allGroups | Where-Object { $_.SecurityEnabled -and $_.GroupTypes -notcontains "Unified" }
    
    Write-Host "Found $($m365Groups.Count) Microsoft 365 groups" -ForegroundColor Green
    Write-Host "Found $($securityGroups.Count) security groups" -ForegroundColor Green
    
    # Get M365 group activity
    $m365Activities = Get-M365GroupActivity
    
    # Get security group activity
    $securityActivities = Get-SecurityGroupActivity -SecurityGroups $securityGroups
    
    # Analyze member activity for a sample of inactive groups
    Write-Host "`nAnalyzing member activity for inactive groups (sample)..." -ForegroundColor Cyan
    $inactiveGroups = $m365Activities | Where-Object { !$_.IsActive } | Select-Object -First 10
    $memberActivities = @()
    
    foreach ($inactiveGroup in $inactiveGroups) {
        Write-Host "  Analyzing members of: $($inactiveGroup.GroupDisplayName)" -ForegroundColor Gray
        $memberActivity = Get-GroupMemberActivity -GroupId $inactiveGroup.GroupId -GroupName $inactiveGroup.GroupDisplayName
        if ($memberActivity) {
            $memberActivities += $memberActivity
        }
    }
    
    # Generate summary
    $activitySummary = Get-GroupActivitySummary -AllGroups $allGroups -M365Activities $m365Activities -SecurityActivities $securityActivities
    
    # Export results
    if ($m365Activities) {
        $m365Activities | Export-Csv -Path "$OutputPath\M365Groups_ActivityAnalysis.csv" -NoTypeInformation
    }
    if ($securityActivities) {
        $securityActivities | Export-Csv -Path "$OutputPath\SecurityGroups_ActivityAnalysis.csv" -NoTypeInformation
    }
    if ($activitySummary) {
        $activitySummary | Export-Csv -Path "$OutputPath\AllGroups_ActivitySummary.csv" -NoTypeInformation
    }
    if ($memberActivities) {
        $memberActivities | Export-Csv -Path "$OutputPath\InactiveGroups_MemberAnalysis.csv" -NoTypeInformation
    }
    
    # Calculate statistics
    $activeM365Count = ($m365Activities | Where-Object { $_.IsActive }).Count
    $inactiveM365Count = ($m365Activities | Where-Object { !$_.IsActive }).Count
    $activeSecurityCount = ($securityActivities | Where-Object { $_.IsRecentlyModified }).Count
    $inactiveSecurityCount = ($securityActivities | Where-Object { $_.HasNoRecentActivity }).Count
    $totalInactive = ($activitySummary | Where-Object { $_.ActivityStatus -eq "Inactive" }).Count
    
    # Generate statistics
    $stats = [PSCustomObject]@{
        AssessmentDate              = Get-Date
        TotalGroupsAnalyzed         = $allGroups.Count
        M365GroupsAnalyzed          = $m365Groups.Count
        SecurityGroupsAnalyzed      = $securityGroups.Count
        ActiveM365Groups            = $activeM365Count
        InactiveM365Groups          = $inactiveM365Count
        ActiveSecurityGroups        = $activeSecurityCount
        InactiveSecurityGroups      = $inactiveSecurityCount
        InactivityThresholdDays     = $InactiveDaysThreshold
        TotalInactiveGroups         = $totalInactive
        PercentInactive             = if ($allGroups.Count -gt 0) { [math]::Round(($totalInactive / $allGroups.Count) * 100, 2) } else { 0 }
    }
    
    $stats | Export-Csv -Path "$OutputPath\ActivityAssessment_Statistics.csv" -NoTypeInformation
    
    # Display summary
    Write-Host "`n========== ACTIVITY ASSESSMENT SUMMARY ==========" -ForegroundColor Yellow
    Write-Host "Total Groups Analyzed: $($stats.TotalGroupsAnalyzed)" -ForegroundColor White
    Write-Host "`nMicrosoft 365 Groups:" -ForegroundColor Cyan
    Write-Host "  - Active: $($stats.ActiveM365Groups) ($(if($stats.M365GroupsAnalyzed -gt 0){'{0:N2}' -f (($stats.ActiveM365Groups / $stats.M365GroupsAnalyzed) * 100)}else{0})%)" -ForegroundColor Green
    Write-Host "  - Inactive: $($stats.InactiveM365Groups) ($(if($stats.M365GroupsAnalyzed -gt 0){'{0:N2}' -f (($stats.InactiveM365Groups / $stats.M365GroupsAnalyzed) * 100)}else{0})%)" -ForegroundColor Red
    Write-Host "`nSecurity Groups:" -ForegroundColor Cyan
    Write-Host "  - Recently Modified: $($stats.ActiveSecurityGroups)" -ForegroundColor Green
    Write-Host "  - No Recent Activity: $($stats.InactiveSecurityGroups)" -ForegroundColor Yellow
    Write-Host "`nTotal Inactive Groups: $($stats.TotalInactiveGroups) ($($stats.PercentInactive)%)" -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Yellow
    
    # Generate recommendations report
    $recommendations = $activitySummary | Where-Object { $_.RecommendedAction -ne "" } | 
        Select-Object GroupName, GroupType, DaysSinceLastActivity, MemberCount, ActivityStatus, RecommendedAction |
        Sort-Object DaysSinceLastActivity -Descending
    
    if ($recommendations) {
        $recommendations | Export-Csv -Path "$OutputPath\Groups_RequiringAction.csv" -NoTypeInformation
        Write-Host "`nGenerated recommendations for $($recommendations.Count) groups requiring action" -ForegroundColor Yellow
    }
    
    Write-Host "`nActivity assessment completed successfully!" -ForegroundColor Green
    Write-Host "All reports saved to: $OutputPath" -ForegroundColor Green
}
catch {
    Write-Host "`nError during activity assessment: $_" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
}
finally {
    # Disconnect from Microsoft Graph
    Write-Host "`nDisconnecting from Microsoft Graph..." -ForegroundColor Cyan
    Disconnect-MgGraph | Out-Null
}