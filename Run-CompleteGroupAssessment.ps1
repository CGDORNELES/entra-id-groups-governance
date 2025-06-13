<#
.SYNOPSIS
    Runs complete Entra ID group assessment including activity analysis and HTML report
.DESCRIPTION
    This script runs all assessment scripts in sequence and generates a comprehensive HTML report
.AUTHOR
    Created for: cdornele
.DATE
    2025-01-13
#>

param(
    [Parameter(Mandatory=$false)]
    [switch]$SkipBasicAssessment,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipActivityAssessment,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipPrivilegedAssessment,
    
    [Parameter(Mandatory=$false)]
    [int]$InactiveDaysThreshold = 90
)

Write-Host "=================================" -ForegroundColor Cyan
Write-Host "Complete Entra ID Group Assessment" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan
Write-Host "Started at: $(Get-Date)" -ForegroundColor Yellow
Write-Host "User: $env:USERNAME" -ForegroundColor Yellow
Write-Host ""

$assessmentFolder = ""
$activityFolder = ""
$privilegedFolder = ""

# Step 1: Run basic assessment
if (!$SkipBasicAssessment) {
    Write-Host "Step 1: Running basic group assessment..." -ForegroundColor Green
    if (Test-Path ".\Get-GroupsAssessment.ps1") {
        & .\Entra-ID-Groups-Assessment.ps1
        # Get the most recent assessment folder
        $assessmentFolder = Get-ChildItem -Directory -Filter "EntraID_Groups_Assessment_*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Select-Object -ExpandProperty FullName
        Write-Host "Basic assessment completed. Output: $assessmentFolder" -ForegroundColor Green
    } else {
        Write-Host "Basic assessment script not found!" -ForegroundColor Red
    }
} else {
    # Find existing assessment folder
    $assessmentFolder = Get-ChildItem -Directory -Filter "EntraID_Groups_Assessment_*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Select-Object -ExpandProperty FullName
    Write-Host "Using existing assessment: $assessmentFolder" -ForegroundColor Yellow
}

# Step 2: Run activity assessment
if (!$SkipActivityAssessment) {
    Write-Host "`nStep 2: Running activity assessment..." -ForegroundColor Green
    if (Test-Path ".\Get-GroupActivityAssessment.ps1") {
        & .\Get-GroupActivityAssessment.ps1 -InactiveDaysThreshold $InactiveDaysThreshold
        # Get the most recent activity folder
        $activityFolder = Get-ChildItem -Directory -Filter "EntraID_GroupActivity_*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Select-Object -ExpandProperty FullName
        Write-Host "Activity assessment completed. Output: $activityFolder" -ForegroundColor Green
    } else {
        Write-Host "Activity assessment script not found!" -ForegroundColor Red
    }
} else {
    # Find existing activity folder
    $activityFolder = Get-ChildItem -Directory -Filter "EntraID_GroupActivity_*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Select-Object -ExpandProperty FullName
    if ($activityFolder) {
        Write-Host "Using existing activity assessment: $activityFolder" -ForegroundColor Yellow
    }
}

# Step 3: Run privileged groups assessment
if (!$SkipPrivilegedAssessment) {
    Write-Host "`nStep 3: Running privileged groups assessment..." -ForegroundColor Green
    if (Test-Path ".\Get-PrivilegedGroupsAssessment.ps1") {
        & .\Get-PrivilegedGroupsAssessment.ps1
        Write-Host "Privileged groups assessment completed." -ForegroundColor Green
    } else {
        Write-Host "Privileged groups assessment script not found!" -ForegroundColor Yellow
    }
}

# Step 4: Generate HTML report
Write-Host "`nStep 4: Generating comprehensive HTML report..." -ForegroundColor Green

if ($assessmentFolder) {
    $reportParams = @{
        AssessmentFolder = $assessmentFolder
    }
    
    if ($activityFolder) {
        $reportParams.ActivityFolder = $activityFolder
    }
    
    if (Test-Path ".\Generate-GroupsHTMLReport.ps1") {
        $reportFile = & .\Generate-GroupsHTMLReport.ps1 @reportParams
        Write-Host "`nComplete assessment finished!" -ForegroundColor Green
        Write-Host "Report generated successfully" -ForegroundColor Green
    } else {
        Write-Host "HTML report generator script not found!" -ForegroundColor Red
    }
} else {
    Write-Host "No assessment data found to generate report!" -ForegroundColor Red
}

Write-Host "`n=================================" -ForegroundColor Cyan
Write-Host "Assessment Summary" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan
Write-Host "Basic Assessment: $(if($assessmentFolder){'Completed'}else{'Not found'})" -ForegroundColor $(if($assessmentFolder){'Green'}else{'Red'})
Write-Host "Activity Assessment: $(if($activityFolder){'Completed'}else{'Not found'})" -ForegroundColor $(if($activityFolder){'Green'}else{'Red'})
Write-Host "HTML Report: Generated" -ForegroundColor Green
Write-Host ""
Write-Host "Completed at: $(Get-Date)" -ForegroundColor Yellow