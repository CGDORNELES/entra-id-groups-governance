#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.Users, Microsoft.Graph.DirectoryObjects

<#
.SYNOPSIS
    Entra ID (Azure AD) Groups Assessment Script
.DESCRIPTION
    This script performs a comprehensive assessment of Entra ID groups including:
    - Group inventory and types
    - Membership analysis
    - Security and governance review
    - Best practices compliance check
.AUTHOR
    Created for: cdornele
.DATE
    2025-06-13
#>

# Import required modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.DirectoryObjects

# Define output directory
$OutputPath = ".\EntraID_Groups_Assessment_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

Write-Host "Entra ID Groups Assessment - Started at $(Get-Date)" -ForegroundColor Green
Write-Host "Output directory: $OutputPath" -ForegroundColor Yellow

# Connect to Microsoft Graph
function Connect-MicrosoftGraphWithScopes {
    $RequiredScopes = @(
        "Group.Read.All",
        "Directory.Read.All",
        "User.Read.All",
        "GroupMember.Read.All",
        "Application.Read.All"
    )
    
    try {
        Connect-MgGraph -Scopes $RequiredScopes -ErrorAction Stop
        Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
        exit 1
    }
}

# Function to get all groups with extended properties
function Get-AllGroupsDetailed {
    Write-Host "`nFetching all groups..." -ForegroundColor Cyan
    
    $allGroups = @()
    $groupsResponse = Get-MgGroup -All -Property Id,DisplayName,Description,GroupTypes,SecurityEnabled,MailEnabled,MailNickname,MembershipRule,MembershipRuleProcessingState,CreatedDateTime,DeletedDateTime,IsAssignableToRole,Visibility,OnPremisesSyncEnabled,ProxyAddresses -PageSize 999
    
    foreach ($group in $groupsResponse) {
        # Get member count
        $memberCount = (Get-MgGroupMember -GroupId $group.Id -All).Count
        
        # Get owner count
        $ownerCount = (Get-MgGroupOwner -GroupId $group.Id -All).Count
        
        # Determine group type
        $groupType = if ($group.GroupTypes -contains "Unified") { 
            "Microsoft 365" 
        } elseif ($group.SecurityEnabled -and $group.MailEnabled) { 
            "Mail-Enabled Security" 
        } elseif ($group.SecurityEnabled) { 
            "Security" 
        } elseif ($group.MailEnabled) { 
            "Distribution" 
        } else { 
            "Unknown" 
        }
        
        # Check if dynamic
        $isDynamic = $group.GroupTypes -contains "DynamicMembership"
        
        $groupDetails = [PSCustomObject]@{
            Id                      = $group.Id
            DisplayName             = $group.DisplayName
            Description             = $group.Description
            GroupType               = $groupType
            IsDynamic               = $isDynamic
            MembershipRule          = $group.MembershipRule
            SecurityEnabled         = $group.SecurityEnabled
            MailEnabled             = $group.MailEnabled
            MailNickname            = $group.MailNickname
            MemberCount             = $memberCount
            OwnerCount              = $ownerCount
            CreatedDateTime         = $group.CreatedDateTime
            IsAssignableToRole      = $group.IsAssignableToRole
            Visibility              = $group.Visibility
            OnPremisesSyncEnabled   = $group.OnPremisesSyncEnabled
            HasDescription          = -not [string]::IsNullOrWhiteSpace($group.Description)
        }
        
        $allGroups += $groupDetails
        Write-Progress -Activity "Processing Groups" -Status "Processed $($allGroups.Count) groups" -PercentComplete (($allGroups.Count / $groupsResponse.Count) * 100)
    }
    
    Write-Host "Found $($allGroups.Count) groups" -ForegroundColor Green
    return $allGroups
}

# Function to analyze group memberships
function Get-GroupMembershipAnalysis {
    param($Groups)
    
    Write-Host "`nAnalyzing group memberships..." -ForegroundColor Cyan
    
    $membershipAnalysis = @()
    
    foreach ($group in $Groups) {
        $analysis = [PSCustomObject]@{
            GroupName               = $group.DisplayName
            GroupType               = $group.GroupType
            MemberCount             = $group.MemberCount
            OwnerCount              = $group.OwnerCount
            IsEmpty                 = $group.MemberCount -eq 0
            IsOrphaned              = $group.OwnerCount -eq 0
            IsLargeGroup            = $group.MemberCount -gt 1000
            HasNoDescription        = -not $group.HasDescription
            CreatedDateTime         = $group.CreatedDateTime
            DaysSinceCreation       = (New-TimeSpan -Start $group.CreatedDateTime -End (Get-Date)).Days
        }
        
        $membershipAnalysis += $analysis
    }
    
    return $membershipAnalysis
}

# Function to get groups with guest users
function Get-GroupsWithGuestUsers {
    Write-Host "`nChecking for groups with guest users..." -ForegroundColor Cyan
    
    $groupsWithGuests = @()
    $processedCount = 0
    
    foreach ($group in $Groups) {
        $processedCount++
        Write-Progress -Activity "Checking guest users" -Status "Processing group $processedCount of $($Groups.Count)" -PercentComplete (($processedCount / $Groups.Count) * 100)
        
        $members = Get-MgGroupMember -GroupId $group.Id -All
        $guestCount = 0
        
        foreach ($member in $members) {
            if ($member.AdditionalProperties.userType -eq "Guest") {
                $guestCount++
            }
        }
        
        if ($guestCount -gt 0) {
            $groupWithGuest = [PSCustomObject]@{
                GroupName       = $group.DisplayName
                GroupType       = $group.GroupType
                TotalMembers    = $group.MemberCount
                GuestCount      = $guestCount
                GuestPercentage = [math]::Round(($guestCount / $group.MemberCount) * 100, 2)
            }
            $groupsWithGuests += $groupWithGuest
        }
    }
    
    Write-Host "Found $($groupsWithGuests.Count) groups with guest users" -ForegroundColor Green
    return $groupsWithGuests
}

# Function to check for duplicate groups
function Find-DuplicateGroups {
    param($Groups)
    
    Write-Host "`nChecking for potential duplicate groups..." -ForegroundColor Cyan
    
    $duplicates = @()
    $groupedByName = $Groups | Group-Object -Property DisplayName
    
    foreach ($nameGroup in $groupedByName) {
        if ($nameGroup.Count -gt 1) {
            foreach ($group in $nameGroup.Group) {
                $duplicate = [PSCustomObject]@{
                    GroupName       = $group.DisplayName
                    GroupId         = $group.Id
                    GroupType       = $group.GroupType
                    MemberCount     = $group.MemberCount
                    CreatedDate     = $group.CreatedDateTime
                    DuplicateCount  = $nameGroup.Count
                }
                $duplicates += $duplicate
            }
        }
    }
    
    Write-Host "Found $($duplicates.Count) potential duplicate groups" -ForegroundColor Green
    return $duplicates
}

# Function to generate summary statistics
function Get-GroupAssessmentSummary {
    param($Groups, $MembershipAnalysis, $GroupsWithGuests)
    
    Write-Host "`nGenerating assessment summary..." -ForegroundColor Cyan
    
    $summary = [PSCustomObject]@{
        AssessmentDate          = Get-Date
        TotalGroups             = $Groups.Count
        SecurityGroups          = ($Groups | Where-Object { $_.GroupType -eq "Security" }).Count
        Microsoft365Groups      = ($Groups | Where-Object { $_.GroupType -eq "Microsoft 365" }).Count
        DistributionGroups      = ($Groups | Where-Object { $_.GroupType -eq "Distribution" }).Count
        MailEnabledSecurityGroups = ($Groups | Where-Object { $_.GroupType -eq "Mail-Enabled Security" }).Count
        DynamicGroups           = ($Groups | Where-Object { $_.IsDynamic }).Count
        EmptyGroups             = ($MembershipAnalysis | Where-Object { $_.IsEmpty }).Count
        OrphanedGroups          = ($MembershipAnalysis | Where-Object { $_.IsOrphaned }).Count
        LargeGroups             = ($MembershipAnalysis | Where-Object { $_.IsLargeGroup }).Count
        GroupsWithoutDescription = ($MembershipAnalysis | Where-Object { $_.HasNoDescription }).Count
        GroupsWithGuests        = $GroupsWithGuests.Count
        RoleAssignableGroups    = ($Groups | Where-Object { $_.IsAssignableToRole }).Count
        OnPremSyncedGroups      = ($Groups | Where-Object { $_.OnPremisesSyncEnabled }).Count
    }
    
    return $summary
}

# Main execution
try {
    # Connect to Microsoft Graph
    Connect-MicrosoftGraphWithScopes
    
    # Get all groups
    $allGroups = Get-AllGroupsDetailed
    
    # Export raw group data
    $allGroups | Export-Csv -Path "$OutputPath\AllGroups_Detailed.csv" -NoTypeInformation
    Write-Host "Exported detailed group list to: $OutputPath\AllGroups_Detailed.csv" -ForegroundColor Green
    
    # Analyze memberships
    $membershipAnalysis = Get-GroupMembershipAnalysis -Groups $allGroups
    $membershipAnalysis | Export-Csv -Path "$OutputPath\GroupMembership_Analysis.csv" -NoTypeInformation
    Write-Host "Exported membership analysis to: $OutputPath\GroupMembership_Analysis.csv" -ForegroundColor Green
    
    # Find empty groups
    $emptyGroups = $membershipAnalysis | Where-Object { $_.IsEmpty }
    if ($emptyGroups) {
        $emptyGroups | Export-Csv -Path "$OutputPath\EmptyGroups.csv" -NoTypeInformation
        Write-Host "Exported empty groups to: $OutputPath\EmptyGroups.csv" -ForegroundColor Green
    }
    
    # Find orphaned groups
    $orphanedGroups = $membershipAnalysis | Where-Object { $_.IsOrphaned }
    if ($orphanedGroups) {
        $orphanedGroups | Export-Csv -Path "$OutputPath\OrphanedGroups.csv" -NoTypeInformation
        Write-Host "Exported orphaned groups to: $OutputPath\OrphanedGroups.csv" -ForegroundColor Green
    }
    
    # Check for groups with guests (optional - can be time consuming)
    $checkGuests = Read-Host "`nDo you want to check for guest users in groups? This may take some time. (Y/N)"
    if ($checkGuests -eq 'Y') {
        $groupsWithGuests = Get-GroupsWithGuestUsers
        if ($groupsWithGuests) {
            $groupsWithGuests | Export-Csv -Path "$OutputPath\GroupsWithGuests.csv" -NoTypeInformation
            Write-Host "Exported groups with guests to: $OutputPath\GroupsWithGuests.csv" -ForegroundColor Green
        }
    } else {
        $groupsWithGuests = @()
    }
    
    # Find duplicate groups
    $duplicateGroups = Find-DuplicateGroups -Groups $allGroups
    if ($duplicateGroups) {
        $duplicateGroups | Export-Csv -Path "$OutputPath\PotentialDuplicateGroups.csv" -NoTypeInformation
        Write-Host "Exported potential duplicate groups to: $OutputPath\PotentialDuplicateGroups.csv" -ForegroundColor Green
    }
    
    # Generate summary
    $summary = Get-GroupAssessmentSummary -Groups $allGroups -MembershipAnalysis $membershipAnalysis -GroupsWithGuests $groupsWithGuests
    $summary | Export-Csv -Path "$OutputPath\AssessmentSummary.csv" -NoTypeInformation
    
    # Display summary
    Write-Host "`n========== ASSESSMENT SUMMARY ==========" -ForegroundColor Yellow
    Write-Host "Total Groups: $($summary.TotalGroups)" -ForegroundColor White
    Write-Host "  - Security Groups: $($summary.SecurityGroups)" -ForegroundColor White
    Write-Host "  - Microsoft 365 Groups: $($summary.Microsoft365Groups)" -ForegroundColor White
    Write-Host "  - Distribution Groups: $($summary.DistributionGroups)" -ForegroundColor White
    Write-Host "  - Dynamic Groups: $($summary.DynamicGroups)" -ForegroundColor White
    Write-Host "`nIssues Found:" -ForegroundColor Yellow
    Write-Host "  - Empty Groups: $($summary.EmptyGroups)" -ForegroundColor $(if ($summary.EmptyGroups -gt 0) { 'Red' } else { 'Green' })
    Write-Host "  - Orphaned Groups (no owners): $($summary.OrphanedGroups)" -ForegroundColor $(if ($summary.OrphanedGroups -gt 0) { 'Red' } else { 'Green' })
    Write-Host "  - Groups without Description: $($summary.GroupsWithoutDescription)" -ForegroundColor $(if ($summary.GroupsWithoutDescription -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "  - Groups with Guest Users: $($summary.GroupsWithGuests)" -ForegroundColor $(if ($summary.GroupsWithGuests -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "=======================================" -ForegroundColor Yellow
    
    Write-Host "`nAssessment completed successfully!" -ForegroundColor Green
    Write-Host "All reports saved to: $OutputPath" -ForegroundColor Green
}
catch {
    Write-Host "Error during assessment: $_" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    # Disconnect from Microsoft Graph
    Disconnect-MgGraph | Out-Null
}