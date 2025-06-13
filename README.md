# Entra ID Groups Assessment Tools

## Overview

This comprehensive PowerShell toolkit provides in-depth assessment of Entra ID (Azure AD) groups, including activity analysis, governance evaluation, and improvement recommendations.

**Author:** Developed for cdornele  
**Date:** January 13, 2025  
**Version:** 3.0

## Table of Contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [Available Scripts](#available-scripts)
4. [Quick Start Guide](#quick-start-guide)
5. [Detailed Script Descriptions](#detailed-script-descriptions)
6. [Understanding the Results](#understanding-the-results)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

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