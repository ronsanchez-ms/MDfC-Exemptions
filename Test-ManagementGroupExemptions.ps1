# Test script for Management Group functionality validation
# This script ONLY tests and validates - it never creates exemptions
#
# Author: Ron Sanchez
# Version: 1.0
# Last Modified: July 2025
# AI Assistance: Developed with GitHub Copilot assistance
#
# DISCLAIMER:
# This script is provided "AS IS" without warranty of any kind. Use at your own risk.
# The author and contributors are not responsible for any damages or issues that may
# arise from using this script. Always test in a non-production environment first.
#
# SECURITY NOTICE:
# This is a READ-ONLY validation script that does not modify any Azure resources.
# However, it requires read permissions to Azure subscriptions and management groups.
#
# PREREQUISITES:
# - Azure PowerShell modules (Az.Accounts, Az.Resources)
# - Appropriate Azure RBAC permissions (Reader or higher)
# - Review the README.md and documentation before use

param(
    [Parameter(Mandatory = $true)]
    [string]$ManagementGroupId
)

Write-Host "=== Testing Management Group Functionality (READ-ONLY) ===" -ForegroundColor Cyan
Write-Host "Management Group: $ManagementGroupId" -ForegroundColor White
Write-Host "This script only validates functionality - no exemptions will be created`n" -ForegroundColor Green

# Test 1: Validate management group access
Write-Host "Test 1: Validating management group access..." -ForegroundColor Yellow
try {
    $mg = Get-AzManagementGroup -GroupId $ManagementGroupId -ErrorAction Stop
    Write-Host "[PASS] Management group '$($mg.DisplayName)' found" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Cannot access management group: $_" -ForegroundColor Red
    Write-Host "Make sure you're logged in to Azure and have proper permissions`n" -ForegroundColor Yellow
}

Write-Host "`n" + "="*60 + "`n"

# Test 2: List all Defender assignments at management group level
Write-Host "Test 2: Finding Defender assignments at management group level..." -ForegroundColor Yellow
try {
    & .\Manage-DefenderExemptions.ps1 -ManagementGroupId $ManagementGroupId -ListOnly
    Write-Host "[PASS] Management group level search completed" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Management group level search failed: $_" -ForegroundColor Red
}

Write-Host "`n" + "="*60 + "`n"

# Test 3: List all Defender assignments including child subscriptions
Write-Host "Test 3: Finding Defender assignments including child subscriptions..." -ForegroundColor Yellow
try {
    & .\Manage-DefenderExemptions.ps1 -ManagementGroupId $ManagementGroupId -IncludeChildSubscriptions -ListOnly
    Write-Host "[PASS] Management group + child subscriptions search completed" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Management group + child subscriptions search failed: $_" -ForegroundColor Red
}

Write-Host "`n" + "="*60 + "`n"

# Test 4: Search for tagged resources across management group (read-only)
Write-Host "Test 4: Searching for tagged resources across management group..." -ForegroundColor Yellow
try {
    & .\Manage-DefenderExemptions.ps1 -ManagementGroupId $ManagementGroupId -IncludeChildSubscriptions -TagName "DefenderExempt" -TagValue "true" -ListOnly
    Write-Host "[PASS] Tagged resource search completed" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Tagged resource search failed: $_" -ForegroundColor Red
}

Write-Host "`n=== Validation Complete ===" -ForegroundColor Cyan
Write-Host "All tests completed. No exemptions were created." -ForegroundColor Green
Write-Host "`nTo create actual exemptions, use:" -ForegroundColor Yellow
Write-Host ".\Create-ManagementGroupExemptions.ps1 -ManagementGroupId '$ManagementGroupId'" -ForegroundColor Cyan
Write-Host "or" -ForegroundColor Yellow
Write-Host ".\Manage-DefenderExemptions.ps1 -ManagementGroupId '$ManagementGroupId' -CreateExemptions" -ForegroundColor Cyan
