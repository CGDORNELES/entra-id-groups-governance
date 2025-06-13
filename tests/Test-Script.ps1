<#
.SYNOPSIS
    Basic tests for Entra ID Groups Governance scripts
.DESCRIPTION
    Validates script functionality and requirements
#>

# Test script existence
Describe "Script Files" {
    It "All required scripts should exist" {
        $requiredScripts = @(
            "Get-GroupsAssessment.ps1",
            "Get-GroupActivityAssessment.ps1",
            "Generate-GroupsHTMLReport.ps1",
            "Run-CompleteGroupAssessment.ps1"
        )

        foreach ($script in $requiredScripts) {
            $scriptPath = Join-Path $PSScriptRoot "..\scripts\$script"
            Test-Path $scriptPath | Should -Be $true
        }
    }
}

# Test script syntax
Describe "Script Syntax" {
    It "Scripts should have valid PowerShell syntax" {
        $scripts = Get-ChildItem -Path "$PSScriptRoot\..\scripts" -Filter *.ps1

        foreach ($script in $scripts) {
            $errors = $null
            $ast = [System.Management.Automation.PSParser]::Tokenize((Get-Content $script.FullName -Raw), [ref]$errors)
            $errors.Count | Should -Be 0
        }
    }
}

# Test help documentation
Describe "Script Documentation" {
    It "Scripts should have synopsis" {
        $scripts = Get-ChildItem -Path "$PSScriptRoot\..\scripts" -Filter *.ps1

        foreach ($script in $scripts) {
            $help = Get-Help $script.FullName
            $help.Synopsis | Should -Not -BeNullOrEmpty
        }
    }
}