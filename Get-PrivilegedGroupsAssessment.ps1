<#
.SYNOPSIS
    Assess privileged groups and their memberships in Entra ID
.DESCRIPTION
    This script identifies groups with administrative privileges and analyzes their membership
.AUTHOR
    Created for: Clairo Dorneles (clairo@clairodorneles.cloud)
.DATE
    2025-06-13
#>

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Group.Read.All", "RoleManagement.Read.Directory", "Directory.Read.All"

$OutputPath = ".\EntraID_PrivilegedGroups_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

Write-Host "Assessing privileged groups..." -ForegroundColor Cyan

# Get all role-assignable groups
$roleAssignableGroups = Get-MgGroup -Filter "isAssignableToRole eq true" -All

# Get groups that are members of directory roles
$directoryRoles = Get-MgDirectoryRole -All
$privilegedGroups = @()

foreach ($role in $directoryRoles) {
    $roleMembers = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -All
    
    foreach ($member in $roleMembers) {
        if ($member.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group') {
            $group = Get-MgGroup -GroupId $member.Id
            $memberCount = (Get-MgGroupMember -GroupId $member.Id -All).Count
            
            $privilegedGroup = [PSCustomObject]@{
                GroupName           = $group.DisplayName
                GroupId             = $group.Id
                AssignedRole        = $role.DisplayName
                RoleId              = $role.Id
                MemberCount         = $memberCount
                IsRoleAssignable    = $group.IsAssignableToRole
                CreatedDateTime     = $group.CreatedDateTime
            }
            
            $privilegedGroups += $privilegedGroup
        }
    }
}

# Combine with role-assignable groups
foreach ($group in $roleAssignableGroups) {
    if ($privilegedGroups.GroupId -notcontains $group.Id) {
        $memberCount = (Get-MgGroupMember -GroupId $group.Id -All).Count
        
        $privilegedGroup = [PSCustomObject]@{
            GroupName           = $group.DisplayName
            GroupId             = $group.Id
            AssignedRole        = "None (Role-Assignable)"
            RoleId              = ""
            MemberCount         = $memberCount
            IsRoleAssignable    = $true
            CreatedDateTime     = $group.CreatedDateTime
        }
        
        $privilegedGroups += $privilegedGroup
    }
}

# Export privileged groups
$privilegedGroups | Export-Csv -Path "$OutputPath\PrivilegedGroups.csv" -NoTypeInformation

# Get detailed membership for each privileged group
$privilegedMembers = @()

foreach ($privGroup in $privilegedGroups) {
    $members = Get-MgGroupMember -GroupId $privGroup.GroupId -All
    
    foreach ($member in $members) {
        $memberDetails = [PSCustomObject]@{
            GroupName       = $privGroup.GroupName
            AssignedRole    = $privGroup.AssignedRole
            MemberName      = $member.AdditionalProperties.displayName
            MemberType      = $member.AdditionalProperties.'@odata.type'.Replace('#microsoft.graph.', '')
            MemberUPN       = $member.AdditionalProperties.userPrincipalName
            MemberId        = $member.Id
        }
        
        $privilegedMembers += $memberDetails
    }
}

# Export privileged members
$privilegedMembers | Export-Csv -Path "$OutputPath\PrivilegedGroupMembers.csv" -NoTypeInformation

# Generate summary
Write-Host "`n========== PRIVILEGED GROUPS SUMMARY ==========" -ForegroundColor Yellow
Write-Host "Total Privileged Groups: $($privilegedGroups.Count)" -ForegroundColor White
Write-Host "Total Members in Privileged Groups: $($privilegedMembers.Count)" -ForegroundColor White
Write-Host "Groups with Directory Role Assignments: $(($privilegedGroups | Where-Object { $_.AssignedRole -ne 'None (Role-Assignable)' }).Count)" -ForegroundColor White
Write-Host "Role-Assignable Groups: $(($privilegedGroups | Where-Object { $_.IsRoleAssignable }).Count)" -ForegroundColor White
Write-Host "`nReports saved to: $OutputPath" -ForegroundColor Green

# Disconnect
Disconnect-MgGraph