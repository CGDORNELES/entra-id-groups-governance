# Contributing to Entra ID Groups Governance

We welcome contributions to improve this toolkit! This document provides guidelines for contributing.

## How to Contribute

### Reporting Issues
1. Check existing issues to avoid duplicates
2. Use issue templates when available
3. Provide detailed information:
    - PowerShell version
    - Error messages
    - Steps to reproduce

### Submitting Pull Requests
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Standards
- Follow PowerShell best practices
- Include comment-based help for functions
- Test scripts with both Windows PowerShell and PowerShell 7
- Ensure no hardcoded values or credentials

### Testing
Before submitting:
```powershell
# Run basic tests
.\tests\Test-Scripts.ps1

# Test with sample data
.\Run-CompleteGroupAssessment.ps1 -WhatIf