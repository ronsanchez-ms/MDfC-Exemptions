# Management Group Support for Azure Policy Exemptions

**Author**: Ron Sanchez
**Version**: 1.0  
**Last Modified**: July 2025  
**AI Assistance**: Developed with GitHub Copilot assistance

## Overview

The `Manage-DefenderExemptions.ps1` script supports management group scoping for policy assignment discovery and resource search. This allows you to efficiently find and manage Microsoft Defender for Cloud policy exemptions across multiple subscriptions within a management group hierarchy.

## Important: Azure Resource Hierarchy

**Critical Understanding**: Resources in Azure **cannot exist directly at the management group level**. Resources can only exist within subscriptions. The management group scope in this script is used for:

1. **Policy Assignment Discovery**: Finding policy assignments that are assigned at the management group level
2. **Multi-Subscription Resource Search**: Searching for tagged resources across all child subscriptions
3. **Exemption Creation**: Creating resource-level exemptions within the appropriate subscriptions

```
Management Group (Policy assignments can exist here, but NOT resources)
├── Subscription A (Resources exist here)
│   ├── Resource Group 1
│   │   ├── VM-001 ← Exemptions created at this level
│   │   └── Storage Account ← Exemptions created at this level
└── Subscription B (Resources exist here)
    └── Resource Group 2
        └── Web App ← Exemptions created at this level
```

## New Features

### Management Group Support
- **Policy Assignment Discovery**: Find Defender policy assignments at management group and subscription levels
- **Multi-Subscription Resource Discovery**: Search for tagged resources across child subscriptions
- **Hierarchical Scope**: Work across entire management group hierarchies efficiently

### New Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `ManagementGroupId` | String | ID of the management group to work with |
| `IncludeChildSubscriptions` | Switch | Include all child subscriptions in operations |

## Usage Examples

### 1. Discover Policy Assignments and Resources in Management Group Hierarchy

```powershell
.\Manage-DefenderExemptions.ps1 -ManagementGroupId "mg-example" -ListOnly
```

This will:
- Find policy assignments at the management group level
- Search for tagged resources across all child subscriptions
- List existing exemptions from discovered resources

### 2. Create Exemptions Across All Child Subscriptions

```powershell
.\Manage-DefenderExemptions.ps1 -ManagementGroupId "mg-example" -IncludeChildSubscriptions -CreateExemptions
```

This will:
- Find policy assignments at management group and all child subscription levels
- Search for tagged resources across all child subscriptions
- Create resource-level exemptions within the appropriate subscriptions

### 3. Use Custom Tags Across Management Group

```powershell
.\Manage-DefenderExemptions.ps1 -ManagementGroupId "mg-example" -IncludeChildSubscriptions -TagName "SkipDefender" -TagValue "true" -ListOnly
```

### 4. Target Specific Policy Assignment

```powershell
.\Manage-DefenderExemptions.ps1 -ManagementGroupId "mg-example" -IncludeChildSubscriptions -DefenderAssignmentName "specific-assignment" -CreateExemptions
```

## Scope Behavior

### Management Group Scope (`-ManagementGroupId` without `-IncludeChildSubscriptions`)
- **Policy Assignments**: Searches for assignments at management group level only
- **Resources**: Searches for tagged resources across all child subscriptions 
- **Exemption Creation**: Creates exemptions at resource level within subscriptions
- **Use Case**: When you want to focus on policies assigned at the management group level but still search all child resources

### Management Group + Child Subscriptions (`-ManagementGroupId` with `-IncludeChildSubscriptions`)
- **Policy Assignments**: Searches assignments at management group AND all child subscription levels
- **Resources**: Searches for tagged resources across all child subscriptions (same as above)
- **Exemption Creation**: Creates exemptions at resource level within subscriptions
- **Use Case**: When you want comprehensive coverage of both management group and subscription-level policy assignments

**Note**: In both cases, resources are always searched across child subscriptions because resources cannot exist at the management group level itself.

## Prerequisites

### Required Azure PowerShell Modules
```powershell
Install-Module -Name Az.Accounts
Install-Module -Name Az.Resources
# Note: Management Group cmdlets (Get-AzManagementGroup, etc.) are included in Az.Resources
```

### Required Permissions

#### For Management Group Operations:
- **Management Group Reader** role on the target management group
- **Policy Reader** role on the management group to read policy assignments

#### For Child Subscription Operations:
- **Reader** role on all child subscriptions to discover resources
- **Resource Policy Contributor** role on subscriptions to create exemptions

#### Recommended Role Assignment:
```powershell
# Assign at management group level to cover all child subscriptions
New-AzRoleAssignment -ObjectId <your-user-or-service-principal> -RoleDefinitionName "Resource Policy Contributor" -Scope "/providers/Microsoft.Management/managementGroups/mg-example"
```

## Error Handling

The script includes robust error handling for management group scenarios:

- **Invalid Management Group**: Script will exit with clear error message
- **Inaccessible Child Subscriptions**: Warnings logged, but script continues with accessible subscriptions
- **Permission Issues**: Clear error messages indicating required permissions
- **Mixed Scope Validation**: Prevents specifying both `-SubscriptionId` and `-ManagementGroupId`

## Performance Considerations

### Large Management Groups
When working with large management groups:
- **Resource Discovery**: Takes time as each child subscription is queried for resources
- **Context Switching**: Script changes Azure context for each subscription during resource discovery
- **Rate Limiting**: Azure API rate limits may apply when querying many subscriptions

### Optimization Tips
1. **Target Specific Assignments**: Use `-DefenderAssignmentName` to focus on specific policies
2. **Custom Tags**: Use specific tag names/values to reduce resource scope
3. **Test First**: Always use `-ListOnly` to understand scope before creating exemptions

## Testing

Use the provided test script to validate functionality:

```powershell
.\Test-ManagementGroupExemptions.ps1 -ManagementGroupId "your-mg-id"
```

The test script runs in dry-run mode by default and provides comprehensive testing of all management group features.

## Migration from Subscription-Only Usage

Existing scripts using subscription-level operations continue to work unchanged:

```powershell
# This continues to work exactly as before
.\Manage-DefenderExemptions.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -CreateExemptions
```

## Troubleshooting

### Common Issues

1. **"Management Group not found"**
   - Verify the management group ID is correct
   - Ensure you have Reader access to the management group

2. **"No policy assignments found"**
   - Check if Defender for Cloud is enabled at the management group level
   - Verify policy assignments exist at the expected scope

3. **"Could not access subscription"**
   - Normal when some child subscriptions are inaccessible
   - Check subscription-level permissions if needed

4. **"Cannot specify both ManagementGroupId and SubscriptionId"**
   - Choose one scope type per execution
   - Use separate script runs for different scopes

### Debug Mode

Enable verbose output by adding debug statements or use PowerShell's built-in debugging:

```powershell
$VerbosePreference = "Continue"
.\Manage-DefenderExemptions.ps1 -ManagementGroupId "mg-example" -ListOnly -Verbose
```
