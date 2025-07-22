# Azure Policy Exemption Solution - PowerShell Deployment Guide

**Author**: Ron Sanchez
**Version**: 1.0  
**Last Modified**: July 2025  
**AI Assistance**: Developed with GitHub Copilot assistance

## Overview
This solution provides automated PowerShell-based management of Azure Policy exemptions for Microsoft Defender for Cloud recommendations, with support for tag-based exemptions and smart category handling.

## 🚀 Quick Start

### Prerequisites
1. **Azure PowerShell Module**:
   ```powershell
   Install-Module -Name Az -Force -AllowClobber
   ```

2. **Azure Permissions**:
   - `Reader` role on subscription/resource groups
   - `Policy Contributor` role to create exemptions
   - `Resource Contributor` to read resource tags

### Step 1: Install and Test
1. **Download all files** to `c:\temp\MDCExemptions-PowerShell\` (or your preferred directory)

2. **Connect to Azure**:
   ```powershell
   Connect-AzAccount
   Set-AzContext -SubscriptionId "your-subscription-id"
   ```

3. **Test your environment** by running the main script in list-only mode:
   ```powershell
   .\Manage-DefenderExemptions.ps1 -ListOnly
   ```

### Step 2: Tag Resources for Exemption
Tag any resources you want to exempt from Defender policies:
```powershell
# Example: Tag a virtual machine
$resourceId = "/subscriptions/12345/resourceGroups/my-rg/providers/Microsoft.Compute/virtualMachines/my-vm"
Set-AzResource -ResourceId $resourceId -Tag @{DefenderExempt='true'} -Force

# Example: Tag a storage account
$resourceId = "/subscriptions/12345/resourceGroups/my-rg/providers/Microsoft.Storage/storageAccounts/mystorageaccount"
Set-AzResource -ResourceId $resourceId -Tag @{DefenderExempt='true'} -Force
```

### Step 3: Test Exemption Creation
First, run the main script in list-only mode to validate everything works:
```powershell
.\Manage-DefenderExemptions.ps1 -ListOnly
```

If resources and policy assignments are found, test exemption creation:
```powershell
.\Manage-DefenderExemptions.ps1 -CreateExemptions
```

### Step 4: Validate with Management Groups (if applicable)
For management group testing, use the validation script:
```powershell
.\Test-ManagementGroupExemptions.ps1 -ManagementGroupId "mg-example"
```

## 🔧 Advanced Configuration

### Customizing Exemption Criteria
The script automatically filters for MCSB (Microsoft Cloud Security Benchmark) related policy assignments. The filtering criteria in `Find-DefenderPolicyAssignments` function targets:

- Display names containing "Microsoft Cloud Security Benchmark"
- Display names containing "Azure Security Baseline" 
- Assignment names containing "SecurityCenterBuiltIn", "ASC", or "Azure_Security_Baseline"
- Display names containing both "Security" and "Benchmark"

This ensures exemptions are only created for relevant security policies, not unrelated policies.

### Custom Tag Names and Values
The script supports any tag name/value combination:
```powershell
# Exempt resources tagged with SecurityExempt=approved (Waiver: 90 days)
.\Manage-DefenderExemptions.ps1 -TagName "SecurityExempt" -TagValue "approved" -ExemptionCategory "Waiver"

# Exempt resources tagged with Environment=development (Mitigated: 365 days)  
.\Manage-DefenderExemptions.ps1 -TagName "Environment" -TagValue "development" -ExemptionCategory "Mitigated"
```

### Exemption Categories
Choose the appropriate category for your use case:
- **`Mitigated`** (default): Risk addressed through compensating controls - 365 days
- **`Waiver`**: Risk accepted, requires periodic review - 90 days

### Exemption Duration
The solution automatically sets expiration based on category:
- **Mitigated**: 365 days (1 year)
- **Waiver**: 90 days (3 months)
- **Custom**: Use `-ExpiresInDays` parameter to override defaults

```powershell
# Use default durations (365 days for Mitigated, 90 days for Waiver)
.\Manage-DefenderExemptions.ps1 -ExemptionCategory "Waiver"

# Override with custom duration
.\Manage-DefenderExemptions.ps1 -ExemptionCategory "Waiver" -ExpiresInDays 30
```

## 📊 Monitoring and Maintenance

### View Created Exemptions
```powershell
# List all exemptions in subscription (including resource-level exemptions)
Get-AzPolicyExemption -IncludeDescendent

# List exemptions for specific resource
Get-AzPolicyExemption -IncludeDescendent | Where-Object { $_.Properties.scope -like "*your-resource-name*" }

# List exemptions created by this solution (by Name property)
Get-AzPolicyExemption -IncludeDescendent | Where-Object { $_.Name -like "DefenderExemption-*" }

# List exemptions created by this solution (by DisplayName property - what you see in Azure Portal)
Get-AzPolicyExemption -IncludeDescendent | Where-Object { $_.DisplayName -like "Defender Exemption -*" }

# View exemptions with expiration dates
Get-AzPolicyExemption -IncludeDescendent | Select-Object Name, @{Name="Category";Expression={$_.Properties.exemptionCategory}}, @{Name="ExpiresOn";Expression={$_.Properties.expiresOn}}, @{Name="Scope";Expression={$_.Properties.scope}}
```

### Cleanup Expired Exemptions
```powershell
# Find expired exemptions
$expiredExemptions = Get-AzPolicyExemption -IncludeDescendent | Where-Object { 
    $_.Properties.expiresOn -and $_.Properties.expiresOn -lt (Get-Date) 
}

# Remove expired exemptions (be careful!)
$expiredExemptions | ForEach-Object {
    Write-Host "Removing expired exemption: $($_.Name)"
    Remove-AzPolicyExemption -Id $_.Id -Force
}
```

### Scheduled Automation
Set up a scheduled task to run the exemption script regularly:

```powershell
# Create a scheduled task to run daily
$action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-File 'c:\temp\MDCExemptions-PowerShell\Manage-DefenderExemptions.ps1' -TagName 'DefenderExempt' -TagValue 'true' -ExemptionCategory 'Waiver'"
$trigger = New-ScheduledTaskTrigger -Daily -At 9am
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -TaskName "Azure Policy Exemptions" -Description "Daily exemption processing for tagged resources"
```

### Bulk Operations
```powershell
# Process multiple resource groups by setting context and filtering
$resourceGroups = @("rg-dev-001", "rg-test-002", "rg-staging-003")
foreach ($rg in $resourceGroups) {
    Write-Host "Processing Resource Group: $rg"
    # Note: The script finds tagged resources across the entire subscription/management group
    # You can filter results by checking resource group in the output
    .\Manage-DefenderExemptions.ps1 -TagName "DefenderExempt" -TagValue "true" -ExemptionCategory "Waiver"
}

# Process different exemption categories
$exemptionConfigs = @(
    @{TagName="DefenderExempt"; TagValue="dev"; Category="Waiver"; Days=30},
    @{TagName="DefenderExempt"; TagValue="prod"; Category="Mitigated"; Days=365}
)

foreach ($config in $exemptionConfigs) {
    Write-Host "Processing: $($config.TagName)=$($config.TagValue) as $($config.Category)"
    .\Manage-DefenderExemptions.ps1 -TagName $config.TagName -TagValue $config.TagValue -ExemptionCategory $config.Category -ExpiresInDays $config.Days
}
```

## 🔍 Quick Troubleshooting

### Most Common Issues:

1. **🚨 Az Module Not Found / "The term 'Connect-AzAccount' is not recognized"**
   
   **Check if Az module is installed:**
   ```powershell
   Get-Module -ListAvailable Az*
   ```
   
   **If nothing appears, install the Az module:**
   ```powershell
   # Install for current user (recommended)
   Install-Module -Name Az -Scope CurrentUser -Force -AllowClobber
   
   # OR install for all users (requires admin rights)
   Install-Module -Name Az -Force -AllowClobber
   ```
   
   **After installation, import the modules:**
   ```powershell
   Import-Module Az.Accounts
   Import-Module Az.Resources
   Import-Module Az.Policy
   ```
   
   **Verify installation:**
   ```powershell
   Get-Module -ListAvailable Az.Accounts, Az.Resources, Az.Policy
   ```

2. **🔄 Old AzureRM Module Conflicts**
   
   **Check for conflicting modules:**
   ```powershell
   Get-Module -ListAvailable AzureRM*
   ```
   
   **If AzureRM modules are found, remove them:**
   ```powershell
   # Uninstall AzureRM modules (they conflict with Az)
   Get-Module -ListAvailable AzureRM* | Uninstall-Module -Force
   
   # Then install Az module
   Install-Module -Name Az -Force -AllowClobber
   ```

3. **🏢 Corporate Environment / Proxy Issues**
   
   **Set PowerShell Gallery as trusted:**
   ```powershell
   Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
   ```
   
   **Configure proxy if needed:**
   ```powershell
   # Set proxy for PowerShell session
   [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy('http://your-proxy:8080')
   
   # Then try installing
   Install-Module -Name Az -Force -AllowClobber
   ```

4. **📦 Specific Module Versions**
   
   **Install specific versions if needed:**
   ```powershell
   # Install specific version
   Install-Module -Name Az -RequiredVersion 9.7.1 -Force
   
   # Check what versions are available
   Find-Module -Name Az -AllVersions | Select-Object Name, Version
   ```

5. **🔧 PowerShell Execution Policy**
   
   **Check execution policy:**
   ```powershell
   Get-ExecutionPolicy
   ```
   
   **If Restricted, change it:**
   ```powershell
   # Temporary change (current session only)
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   
   # Permanent change for current user
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

6. **Exemptions not found with Get-AzPolicyExemption**
   - **Solution**: Add `-IncludeDescendent` parameter to find resource-level exemptions
   ```powershell
   Get-AzPolicyExemption -IncludeDescendent | Where-Object { $_.DisplayName -like "Defender Exemption -*" }
   ```

7. **"No Microsoft Defender for Cloud policy assignments found"**
   - Run `.\Manage-DefenderExemptions.ps1 -ListOnly` to see what's discovered
   - Enable Microsoft Defender for Cloud in Azure Security Center

8. **"Access denied" errors**
   - Ensure you have `Policy Contributor` role at subscription/resource group level

9. **Exemptions not appearing in Portal**
   - Allow 5-10 minutes for Azure to process changes
   - Check exemption scope matches resource location

### Quick Debug Commands:
```powershell
# Test your environment
.\Manage-DefenderExemptions.ps1 -ListOnly

# Check Azure context
Get-AzContext

# Find resource-level exemptions
Get-AzPolicyExemption -IncludeDescendent
```

### 🩺 Full Environment Diagnostic
Run this comprehensive diagnostic to check your PowerShell environment:

```powershell
# === PowerShell Environment Diagnostic ===
Write-Host "=== PowerShell Environment Diagnostic ===" -ForegroundColor Cyan

# Check PowerShell version
Write-Host "PowerShell Version:" -ForegroundColor Yellow
$PSVersionTable.PSVersion

# Check execution policy
Write-Host "`nExecution Policy:" -ForegroundColor Yellow
Get-ExecutionPolicy -List

# Check if Az modules are available
Write-Host "`nAz Modules Available:" -ForegroundColor Yellow
$azModules = Get-Module -ListAvailable Az*
if ($azModules) {
    $azModules | Select-Object Name, Version | Sort-Object Name
} else {
    Write-Host "❌ No Az modules found! Run: Install-Module -Name Az -Force" -ForegroundColor Red
}

# Check for conflicting AzureRM modules
Write-Host "`nAzureRM Modules (should be empty):" -ForegroundColor Yellow
$armModules = Get-Module -ListAvailable AzureRM*
if ($armModules) {
    Write-Host "⚠️  AzureRM modules found - these conflict with Az modules!" -ForegroundColor Red
    $armModules | Select-Object Name, Version
    Write-Host "Run: Get-Module -ListAvailable AzureRM* | Uninstall-Module -Force" -ForegroundColor Yellow
} else {
    Write-Host "✅ No conflicting AzureRM modules" -ForegroundColor Green
}

# Test Azure connection
Write-Host "`nAzure Connection:" -ForegroundColor Yellow
try {
    $context = Get-AzContext -ErrorAction SilentlyContinue
    if ($context) {
        Write-Host "✅ Connected to Azure" -ForegroundColor Green
        Write-Host "   Account: $($context.Account.Id)"
        Write-Host "   Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
    } else {
        Write-Host "❌ Not connected to Azure. Run: Connect-AzAccount" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Az.Accounts module not available. Run: Install-Module -Name Az -Force" -ForegroundColor Red
}

Write-Host "`n=== Diagnostic Complete ===" -ForegroundColor Cyan
```

📖 **For detailed troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)**

### Logging and Auditing
```powershell
# Enable logging in your scripts
Start-Transcript -Path "C:\temp\exemption-log-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"

# Run your exemption commands
.\Manage-DefenderExemptions.ps1 -TagName "DefenderExempt" -TagValue "true" -ExemptionCategory "Waiver"

# Stop logging
Stop-Transcript

# Create audit report
$exemptions = Get-AzPolicyExemption -IncludeDescendent | Where-Object { $_.Name -like "DefenderExemption-*" }
$exemptions | Select-Object Name, @{Name="Category";Expression={$_.Properties.exemptionCategory}}, @{Name="Created";Expression={$_.Properties.metadata.createdOn}}, @{Name="ExpiresOn";Expression={$_.Properties.expiresOn}} | Export-Csv -Path "C:\temp\exemption-audit-$(Get-Date -Format 'yyyyMMdd').csv" -NoTypeInformation
```

## 🚀 Production Deployment

### Azure Automation Account Setup
For enterprise deployment, use Azure Automation to run scripts on schedule:

```powershell
# Create automation account
$resourceGroup = "rg-automation"
$automationAccount = "aa-policy-exemptions"
$location = "East US"

New-AzAutomationAccount -ResourceGroupName $resourceGroup -Name $automationAccount -Location $location

# Import required modules
Import-AzAutomationModule -AutomationAccountName $automationAccount -ResourceGroupName $resourceGroup -Name "Az.Accounts" -ModuleVersion "2.12.1"
Import-AzAutomationModule -AutomationAccountName $automationAccount -ResourceGroupName $resourceGroup -Name "Az.Resources" -ModuleVersion "6.5.0"
Import-AzAutomationModule -AutomationAccountName $automationAccount -ResourceGroupName $resourceGroup -Name "Az.Policy" -ModuleVersion "1.0.1"

# Create runbook
$runbookName = "Manage-PolicyExemptions"
New-AzAutomationRunbook -AutomationAccountName $automationAccount -ResourceGroupName $resourceGroup -Name $runbookName -Type PowerShell
```

### Service Principal Setup
```powershell
# Create service principal for automation
$sp = New-AzADServicePrincipal -DisplayName "PolicyExemptionAutomation"

# Assign required roles
New-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName "Policy Contributor" -Scope "/subscriptions/your-subscription-id"
New-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName "Resource Policy Contributor" -Scope "/subscriptions/your-subscription-id"

# Store credentials in automation account
$credential = New-Object System.Management.Automation.PSCredential($sp.AppId, (ConvertTo-SecureString $sp.PasswordCredentials[0].SecretText -AsPlainText -Force))
New-AzAutomationCredential -AutomationAccountName $automationAccount -ResourceGroupName $resourceGroup -Name "PolicyExemptionSP" -Value $credential
```

### Runbook Script
```powershell
# Automation runbook content
param(
    [Parameter(Mandatory=$true)]
    [string]$TagName,
    
    [Parameter(Mandatory=$true)]
    [string]$TagValue,
    
    [Parameter(Mandatory=$false)]
    [string]$ExemptionCategory = "Mitigated"
)

# Authenticate using service principal
$credential = Get-AutomationPSCredential -Name "PolicyExemptionSP"
Connect-AzAccount -ServicePrincipal -Credential $credential -TenantId "your-tenant-id"

# Set subscription context
Set-AzContext -SubscriptionId "your-subscription-id"

# Execute exemption logic (copy from Manage-DefenderExemptions.ps1)
# ... (insert main script logic here)

Write-Output "Exemption processing completed for $TagName=$TagValue"
```

## 📋 File Structure
```
c:\temp\MDCExemptions-PowerShell\
├── Manage-DefenderExemptions.ps1      # Main exemption management script
├── Test-ManagementGroupExemptions.ps1 # Management group validation (read-only)
├── README.md                          # Main documentation
├── DEPLOYMENT_GUIDE.md               # This deployment guide
├── MANAGEMENT_GROUP_GUIDE.md         # Management group specific guidance
└── TROUBLESHOOTING.md                # Common issues and solutions
```

## 🔐 Security Best Practices

### Authentication
```powershell
# Use managed identity when possible
if ($env:IDENTITY_ENDPOINT) {
    # Running in Azure with managed identity
    Connect-AzAccount -Identity
} else {
    # Interactive login for development
    Connect-AzAccount
}
```

### Least Privilege
```powershell
# Create custom role with minimal permissions
$roleDef = @{
    Name = "Policy Exemption Manager"
    Description = "Can create and manage policy exemptions"
    Actions = @(
        "Microsoft.Authorization/policyExemptions/*",
        "Microsoft.Authorization/policyAssignments/read",
        "Microsoft.Resources/subscriptions/resourceGroups/read",
        "Microsoft.Resources/subscriptions/resources/read"
    )
    AssignableScopes = @("/subscriptions/your-subscription-id")
}

New-AzRoleDefinition -Role $roleDef
```

### Audit Logging
```powershell
# Enable detailed logging
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"
$InformationPreference = "Continue"

# Log all exemption activities
function Write-ExemptionLog {
    param($Message, $Level = "Info")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"
    Add-Content -Path "C:\temp\exemption-audit.log" -Value $logEntry
    Write-Information $logEntry
}
```

## 🎯 Next Steps

1. **Test in development** environment with the debug script
2. **Configure authentication** appropriate for your environment
3. **Customize exemption criteria** in the main script
4. **Set up monitoring** and scheduled execution
5. **Create documentation** for your specific use cases
6. **Train team members** on script usage and troubleshooting

## 🆘 Support

If you encounter issues:
1. Run `.\Manage-DefenderExemptions.ps1 -ListOnly` to see debug output
2. Use `.\Test-ManagementGroupExemptions.ps1` for management group validation
3. Check Azure Activity Log for detailed error messages
4. Validate permissions with test commands above
5. Review Azure PowerShell module versions
6. Test with minimal scope first (single resource)

Remember: Always test thoroughly in a development environment before running in production!

### MCSB Coverage Analysis

The script includes functionality to check Microsoft Cloud Security Benchmark (MCSB) coverage across your Azure environment:

```powershell
# Check MCSB coverage for a single subscription
.\Manage-DefenderExemptions.ps1 -CheckMCSBCoverage -SubscriptionId "12345678-1234-1234-1234-123456789012"

# Check MCSB coverage across management group and all child subscriptions
.\Manage-DefenderExemptions.ps1 -CheckMCSBCoverage -ManagementGroupId "mg-example"

# Example output:
# === Microsoft Cloud Security Benchmark Coverage Check ===
# Checking MCSB coverage for management group: mg-example
# Found 3 child subscriptions to check
# 
# Checking subscription: 12345678-1234-1234-1234-123456789012
#   ✓ MCSB Found: 1 MCSB-related assignment(s)
#     - Microsoft Cloud Security Benchmark (Azure_Security_Baseline)
# 
# Checking subscription: 87654321-4321-4321-4321-210987654321
#   ✗ No MCSB assignments found
# 
# === MCSB Coverage Summary ===
# Total Subscriptions Checked: 3
# Subscriptions with MCSB: 2
# Subscriptions without MCSB: 1
# Coverage Percentage: 66.7%
# 
# ⚠️  Subscriptions WITHOUT MCSB Initiative:
#   - 87654321-4321-4321-4321-210987654321 (Production-Subscription)
# 
# 📋 Recommended Actions:
#   1. Assign Microsoft Cloud Security Benchmark initiative to missing subscriptions
#   2. Review subscription access permissions if 'Access Denied' errors occurred
#   3. Consider assigning MCSB at the management group level for automatic coverage
```

**Benefits of MCSB Coverage Analysis:**
- **Security Baseline Assurance**: Ensures all subscriptions have security recommendations enabled
- **Compliance Monitoring**: Track MCSB deployment across your Azure environment
- **Gap Identification**: Quickly identify subscriptions missing security baseline policies
- **Actionable Reports**: Get specific recommendations for improving security coverage
