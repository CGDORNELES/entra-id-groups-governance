
# Entra ID Groups Assessment Tools

## Overview

This comprehensive PowerShell toolkit provides in-depth assessment of Entra ID (Azure AD)
groups, including activity analysis, governance evaluation, and improvement recommendations.

**Author:** Developed for Clairo Dorneles
**Date:** January 13, 2025  
**Version:** 3.0

## Table of Contents

1. [Requirements](#requirements)
2. [Usage](#usage)
3. [Features](#Features)
4. [Support](#Support)
5. [License](#License)

## Requirements

### System Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+
- Internet connection
- Entra ID administrative account

### Required Permissions

- **Group.Read.All** - Read all groups
- **Directory.Read.All** - Read directory data
- **Reports.Read.All** - Read activity reports
- **AuditLog.Read.All** - Read audit logs
- **User.Read.All** - Read user information

### Required PowerShell Modules

```powershell
Microsoft.Graph.Authentication
Microsoft.Graph.Groups
Microsoft.Graph.Reports
Microsoft.Graph.Users
Microsoft.Graph.DirectoryObjects
```

## Usage

### Quick Start - Complete Assessment

```powershell
# Navigate to the scripts directory
cd path\to\entra-id-groups-governance\scripts

# Run the complete assessment
.\Run-CompleteGroupAssessment.ps1
```

This will:

1. Connect to Microsoft Graph (browser authentication)
2. Assess all groups in your tenant
3. Analyze group activity over the last 90 days
4. Generate an interactive HTML report

### Individual Script Usage

```powershell
# Analyze all groups
.\Get-GroupsAssessment.ps1

# Skip guest check for better performance
.\Get-GroupsAssessment.ps1 -SkipGuestCheck
```

### Activity Analysis

```powershell
# Check activity with default 90-day threshold
.\Get-GroupActivityAssessment.ps1

# Use custom inactivity threshold
.\Get-GroupActivityAssessment.ps1 -InactiveDaysThreshold 180
```

### Generate HTML Report

```powershell
# Generate report from existing data
.\Generate-GroupsHTMLReport.ps1 `
    -AssessmentFolder ".\EntraID_Groups_Assessment_20250113_120000" `
    -ActivityFolder ".\EntraID_GroupActivity_20250113_120000" 
```

### Output Structure

Each assessment creates timestamped folders containing:

EntraID_Groups_Assessment_YYYYMMDD_HHMMSS/
├── AllGroups_Detailed.csv          # Complete inventory
├── AssessmentSummary.csv           # Statistics
├── EmptyGroups.csv                 # Groups with no members
├── OrphanedGroups.csv              # Groups with no owners
├── GroupsWithGuests.csv            # External access
└── LargeGroups.csv                 # 1000+ members

EntraID_GroupActivity_YYYYMMDD_HHMMSS/
├── M365Groups_ActivityAnalysis.csv
├── SecurityGroups_ActivityAnalysis.csv
├── AllGroups_ActivitySummary.csv
└── Groups_RequiringAction.csv

## Features

The HTML report includes:

- Interactive Dashboard - Filter by Top 10, 50, 100, or All groups
- Activity Visualization - Charts showing active vs inactive groups
- Tabbed Navigation - Organized views for different group types
- Issue Highlighting - Color-coded indicators for problems
- Export Options - Copy or save data from any table
- Responsive Design - Works on desktop and mobile devices

## Support

For issues, questions, or contributions:

GitHub Issues: https://github.com/cgdorneles/entra-id-groups-governance/issues
Email: clairo@clairodorneles.cloud

## License

This project is licensed under the MIT License. 
See the [LICENSE](LICENSE) file for details.