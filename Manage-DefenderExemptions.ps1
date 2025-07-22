# Azure Policy Exemption Management Script
# Manages exemptions for Microsoft Defender for Cloud recommendations
# Supports both subscription and management group level operations
# Includes MCSB coverage checking functionality
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
# This script modifies Azure Policy exemptions which can affect security compliance.
# Ensure you understand the security implications before creating exemptions.
# Review and audit all exemptions regularly per your organization's security policies.
#
# PREREQUISITES:
# - Azure PowerShell modules (Az.Accounts, Az.Resources)
# - Appropriate Azure RBAC permissions (Policy Contributor or higher)
# - Review the README.md and documentation before use
#
# Examples:
#   .\Manage-DefenderExemptions.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -ListOnly
#   .\Manage-DefenderExemptions.ps1 -ManagementGroupId "mg-example" -IncludeChildSubscriptions -CreateExemptions
#   .\Manage-DefenderExemptions.ps1 -ManagementGroupId "mg-example" -TagName "CustomTag" -TagValue "exempt" -ListOnly
#   .\Manage-DefenderExemptions.ps1 -ManagementGroupId "mg-example" -CheckMCSBCoverage

<#
.SYNOPSIS
Manages Azure Policy exemptions for Microsoft Defender for Cloud recommendations based on resource tags.

.DESCRIPTION
This script helps manage policy exemptions for Microsoft Defender for Cloud by finding resources with specific tags
and creating exemptions for them. It supports both subscription and management group level operations.

.PARAMETER SubscriptionId
The subscription ID to work with. If not specified, uses the current context subscription.
Cannot be used together with ManagementGroupId.

.PARAMETER ManagementGroupId
The management group ID to use for policy assignment discovery and multi-subscription resource search.
When specified, the script searches for policy assignments at the management group level and searches
for tagged resources across all child subscriptions. Exemptions are always created at the resource level
within the appropriate subscriptions. Cannot be used together with SubscriptionId.

.PARAMETER TagName
The name of the tag to filter resources by. Default is "DefenderExempt".

.PARAMETER TagValue
The value of the tag to filter resources by. Default is "true".

.PARAMETER ExemptionCategory
The category for the exemption. Valid values are "Waiver" or "Mitigated". Default is "Mitigated".
- "Mitigated": Long-term exemption (365 days) for risks that have been addressed through compensating controls
- "Waiver": Short-term exemption (90 days) for accepted risks that require periodic review

.PARAMETER ExpiresInDays
Number of days from now when the exemption should expire. 
- Default is 365 days for "Mitigated" category
- Default is 90 days for "Waiver" category
- This parameter overrides the category-based defaults if explicitly specified

.PARAMETER ListOnly
Switch to only list existing exemptions without creating new ones.

.PARAMETER CreateExemptions
Switch to create new exemptions for tagged resources.

.PARAMETER DefenderAssignmentName
Specific Defender policy assignment name to target. If not specified, uses the first found assignment.

.PARAMETER CheckMCSBCoverage
Switch to check which subscriptions do not have Microsoft Cloud Security Benchmark (MCSB) initiative assigned.
When used with ManagementGroupId, checks all child subscriptions for MCSB policy assignment coverage.

.PARAMETER IncludeChildSubscriptions
When used with ManagementGroupId, includes all child subscriptions in the operation.

.EXAMPLE
.\Manage-DefenderExemptions.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -ListOnly
Lists all existing exemptions for tagged resources in the specified subscription.

.EXAMPLE
.\Manage-DefenderExemptions.ps1 -ManagementGroupId "mg-example" -IncludeChildSubscriptions -CreateExemptions
Creates exemptions for all tagged resources across the management group and all child subscriptions.

.EXAMPLE
.\Manage-DefenderExemptions.ps1 -ManagementGroupId "mg-example" -TagName "SkipDefender" -TagValue "yes" -ListOnly
Lists exemptions for resources with the custom tag "SkipDefender=yes" at the management group level.

.EXAMPLE
.\Manage-DefenderExemptions.ps1 -ManagementGroupId "mg-example" -CheckMCSBCoverage
Checks which child subscriptions under the management group do not have MCSB initiative assigned.
#>

param (
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $false)]
    [string]$ManagementGroupId,
    
    [Parameter(Mandatory = $false)]
    [string]$TagName = "DefenderExempt",
    
    [Parameter(Mandatory = $false)]
    [string]$TagValue = "true",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Waiver", "Mitigated")]
    [string]$ExemptionCategory = "Mitigated",
    
    [Parameter(Mandatory = $false)]
    [int]$ExpiresInDays = 0,  # Will be set based on category if not specified
    
    [Parameter(Mandatory = $false)]
    [switch]$ListOnly,
    
    [Parameter(Mandatory = $false)]
    [switch]$CreateExemptions,
    
    [Parameter(Mandatory = $false)]
    [string]$DefenderAssignmentName,
    
    [Parameter(Mandatory = $false)]
    [switch]$CheckMCSBCoverage,
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeChildSubscriptions
)

# Import required modules
try {
    Import-Module Az.Accounts -Force
    Import-Module Az.Resources -Force
    # Note: Management Group cmdlets are part of Az.Resources module
} catch {
    Write-Error "Required Azure PowerShell modules not found. Please install: Install-Module -Name Az"
    exit 1
}

# Ensure we're logged in
$context = Get-AzContext
if (!$context) {
    Write-Host "Please log in to Azure..."
    Connect-AzAccount
    $context = Get-AzContext
}

# Validate input parameters
if ($ManagementGroupId -and $SubscriptionId) {
    Write-Error "Cannot specify both ManagementGroupId and SubscriptionId. Choose one scope."
    exit 1
}

if (!$ManagementGroupId -and !$SubscriptionId) {
    $SubscriptionId = $context.Subscription.Id
    Write-Host "No scope specified, using current subscription: $SubscriptionId" -ForegroundColor Yellow
}

if ($ManagementGroupId) {
    Write-Host "Working with management group: $ManagementGroupId" -ForegroundColor Green
    $scope = "/providers/Microsoft.Management/managementGroups/$ManagementGroupId"
} else {
    Write-Host "Working with subscription: $SubscriptionId" -ForegroundColor Green
    $scope = "/subscriptions/$SubscriptionId"
}

function Get-ChildSubscriptions {
    <#
    .SYNOPSIS
    Recursively get all subscription IDs from management group children
    #>
    param($ManagementGroupChildren)
    
    $subscriptions = @()
    
    foreach ($child in $ManagementGroupChildren) {
        if ($child.Type -eq "/subscriptions") {
            $subscriptions += $child.Name
        } elseif ($child.Type -eq "/providers/Microsoft.Management/managementGroups") {
            if ($child.Children) {
                $subscriptions += Get-ChildSubscriptions -ManagementGroupChildren $child.Children
            }
        }
    }
    
    return $subscriptions
}

function Find-DefenderPolicyAssignments {
    <#
    .SYNOPSIS
    Find Microsoft Defender for Cloud policy assignments
    #>
    param(
        [string]$Scope,
        [string]$ManagementGroupId,
        [string]$SubscriptionId,
        [switch]$IncludeChildSubscriptions
    )
    
    Write-Host "Searching for policy assignments in scope: $Scope" -ForegroundColor Gray
    
    $allAssignments = @()
    
    if ($ManagementGroupId) {
        # Get assignments at management group level
        $assignments = Get-AzPolicyAssignment -Scope $Scope
        $allAssignments += $assignments
        
        # If IncludeChildSubscriptions is specified, also get assignments from child subscriptions
        if ($IncludeChildSubscriptions) {
            Write-Host "Including child subscriptions..." -ForegroundColor Gray
            try {
                $mgDetails = Get-AzManagementGroup -GroupId $ManagementGroupId -Expand -Recurse
                $subscriptions = Get-ChildSubscriptions -ManagementGroupChildren $mgDetails.Children
                
                foreach ($subId in $subscriptions) {
                    Write-Host "  Checking subscription: $subId" -ForegroundColor Gray
                    $subScope = "/subscriptions/$subId"
                    $subAssignments = Get-AzPolicyAssignment -Scope $subScope -ErrorAction SilentlyContinue
                    if ($subAssignments) {
                        $allAssignments += $subAssignments
                    }
                }
            }
            catch {
                Write-Warning "Could not retrieve child subscriptions: $_"
            }
        }
    } else {
        # Get assignments at subscription level
        $allAssignments = Get-AzPolicyAssignment -Scope $Scope
    }
    
    $defenderAssignments = @()
    foreach ($assignment in $allAssignments) {
        $displayName = $assignment.Properties.displayName
        $name = $assignment.Name
        
        # Get the assignment ID - Azure policy assignments use different property names
        $assignmentId = $null
        
        # The correct property for policy assignments is usually just 'Id'
        if (![string]::IsNullOrEmpty($assignment.Id)) {
            $assignmentId = $assignment.Id
        } elseif (![string]::IsNullOrEmpty($assignment.ResourceId)) {
            $assignmentId = $assignment.ResourceId
        } elseif (![string]::IsNullOrEmpty($assignment.PolicyAssignmentId)) {
            $assignmentId = $assignment.PolicyAssignmentId
        } else {
            # Fallback: construct the ID manually if we have the scope and name
            if ($assignment.Properties.scope -and $assignment.Name) {
                $assignmentId = "$($assignment.Properties.scope)/providers/Microsoft.Authorization/policyAssignments/$($assignment.Name)"
            }
        }
        
        # Filter to only Microsoft Cloud Security Benchmark (MCSB) related assignments
        # This ensures exemptions are only created for MCSB recommendations
        if ($displayName -like "*Microsoft Cloud Security Benchmark*" -or 
            $displayName -like "*Azure Security Baseline*" -or
            $name -like "*SecurityCenterBuiltIn*" -or
            $name -like "*ASC*" -or
            $name -like "*Azure_Security_Baseline*" -or
            ($displayName -like "*Security*" -and $displayName -like "*Benchmark*")) {
            
            Write-Host "  Found MCSB assignment: $name (ID: $assignmentId)" -ForegroundColor Gray
            Write-Host "    Display Name: $displayName" -ForegroundColor Gray
            
            # Only add assignments with valid IDs
            if (![string]::IsNullOrEmpty($assignmentId)) {
                $defenderAssignments += [PSCustomObject]@{
                    Id = $assignmentId
                    Name = $assignment.Name
                    DisplayName = $displayName
                    PolicyDefinitionId = $assignment.Properties.policyDefinitionId
                    Scope = $assignment.Properties.scope
                }
            } else {
                Write-Warning "  Skipping assignment '$name' - no valid ID found"
            }
        } else {
            # Log non-MCSB assignments for transparency
            Write-Host "  Skipping non-MCSB assignment: $name" -ForegroundColor DarkGray
            Write-Host "    Display Name: $displayName" -ForegroundColor DarkGray
        }
    }
    
    return $defenderAssignments
}

function New-PolicyExemptionForResource {
    <#
    .SYNOPSIS
    Create a policy exemption for a specific resource
    #>
    param(
        [string]$ResourceId,
        [string]$ResourceName,
        [string]$PolicyAssignmentId,
        [string]$ExemptionCategory,
        [string]$TagName,
        [string]$TagValue,
        [datetime]$ExpiresOn,
        [int]$ExpiresInDays
    )
    
    $exemptionName = "DefenderExemption-$ResourceName-$(Get-Date -Format 'yyyyMMdd')"
    
    # Create category-specific description with actual expiration days
    if ($ExemptionCategory -eq "Waiver") {
        $description = "Waiver exemption for resource $ResourceName with tag $TagName=$TagValue. Risk accepted, requires periodic review ($ExpiresInDays days)."
    } else {
        $description = "Mitigated exemption for resource $ResourceName with tag $TagName=$TagValue. Risk addressed through compensating controls ($ExpiresInDays days)."
    }
    
    try {
        # Debug: Check if PolicyAssignmentId is valid
        if ([string]::IsNullOrEmpty($PolicyAssignmentId)) {
            throw "PolicyAssignmentId is null or empty"
        }
        
        Write-Host "  Getting policy assignment: $PolicyAssignmentId" -ForegroundColor Gray
        
        # Get the policy assignment object
        $policyAssignment = Get-AzPolicyAssignment -Id $PolicyAssignmentId -ErrorAction Stop
        
        if (!$policyAssignment) {
            throw "Could not retrieve policy assignment with ID: $PolicyAssignmentId"
        }
        
        Write-Host "  Policy assignment found: $($policyAssignment.Properties.displayName)" -ForegroundColor Gray
        
        $exemption = New-AzPolicyExemption `
            -Name $exemptionName `
            -Scope $ResourceId `
            -PolicyAssignment $policyAssignment `
            -ExemptionCategory $ExemptionCategory `
            -DisplayName "Defender Exemption - $ResourceName" `
            -Description $description `
            -ExpiresOn $ExpiresOn `
            -ErrorAction Stop
        
        Write-Host "[PASS] Created exemption: $exemptionName for $ResourceName" -ForegroundColor Green
        return $exemption
    }
    catch {
        Write-Host "[FAIL] Failed to create exemption for $ResourceName`: $_" -ForegroundColor Red
        return $null
    }
}

function Get-ExistingExemptions {
    <#
    .SYNOPSIS
    Get existing exemptions for a resource
    #>
    param([string]$ResourceId)
    
    try {
        return Get-AzPolicyExemption -Scope $ResourceId -ErrorAction SilentlyContinue
    }
    catch {
        return @()
    }
}

function Find-TaggedResources {
    <#
    .SYNOPSIS
    Find resources with specified tag across subscription(s)
    #>
    param(
        [string]$TagName,
        [string]$TagValue,
        [string]$SubscriptionId,
        [string]$ManagementGroupId,
        [switch]$IncludeChildSubscriptions
    )
    
    $allResources = @()
    
    if ($ManagementGroupId -and $IncludeChildSubscriptions) {
        Write-Host "Finding resources across all subscriptions in management group..." -ForegroundColor Gray
        try {
            $mgDetails = Get-AzManagementGroup -GroupId $ManagementGroupId -Expand -Recurse
            $subscriptions = Get-ChildSubscriptions -ManagementGroupChildren $mgDetails.Children
            
            foreach ($subId in $subscriptions) {
                Write-Host "  Checking subscription: $subId" -ForegroundColor Gray
                try {
                    # Set context to the subscription
                    $null = Set-AzContext -SubscriptionId $subId -ErrorAction Stop
                    $resources = Get-AzResource -TagName $TagName -TagValue $TagValue -ErrorAction SilentlyContinue
                    if ($resources) {
                        $allResources += $resources
                        Write-Host "    Found $($resources.Count) resources" -ForegroundColor Gray
                    }
                }
                catch {
                    Write-Warning "  Could not access subscription $subId`: $_"
                }
            }
        }
        catch {
            Write-Error "Could not retrieve management group details: $_"
            return @()
        }
    } else {
        # Single subscription scope
        if ($SubscriptionId) {
            $null = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
        }
        $allResources = Get-AzResource -TagName $TagName -TagValue $TagValue
    }
    
    return $allResources
}

function Test-ExemptionLimits {
    <#
    .SYNOPSIS
    Check if we're approaching Azure Policy exemption limits
    #>
    param(
        [string]$Scope,
        [int]$PlannedExemptions,
        [int]$MaxAllowedExemptions = 950,  # Safety buffer below 1,000 limit
        [array]$Resources = @()  # Optional: provide resources to count existing exemptions at resource level
    )
    
    Write-Host "Checking exemption limits for scope: $Scope" -ForegroundColor Gray
    
    try {
        $currentCount = 0
        
        if ($Resources.Count -gt 0) {
            # Count existing exemptions across all provided resources
            Write-Host "  Counting existing exemptions across $($Resources.Count) resources..." -ForegroundColor Gray
            foreach ($resource in $Resources) {
                $resourceExemptions = Get-AzPolicyExemption -Scope $resource.ResourceId -ErrorAction SilentlyContinue
                $currentCount += ($resourceExemptions | Measure-Object).Count
                if ($resourceExemptions.Count -gt 0) {
                    Write-Host "    Resource $($resource.Name): $($resourceExemptions.Count) exemptions" -ForegroundColor Gray
                }
            }
        } else {
            # Fallback: get exemptions at the specified scope level
            $existingExemptions = Get-AzPolicyExemption -Scope $Scope -ErrorAction SilentlyContinue
            $currentCount = ($existingExemptions | Measure-Object).Count
        }
        
        $projectedTotal = $currentCount + $PlannedExemptions
        
        Write-Host "  Current exemptions: $currentCount" -ForegroundColor Gray
        Write-Host "  Planned exemptions: $PlannedExemptions" -ForegroundColor Gray
        Write-Host "  Projected total: $projectedTotal" -ForegroundColor Gray
        Write-Host "  Azure limit: 1,000 (safety threshold: $MaxAllowedExemptions)" -ForegroundColor Gray
        
        $result = @{
            CurrentCount = $currentCount
            PlannedCount = $PlannedExemptions
            ProjectedTotal = $projectedTotal
            Limit = 1000
            SafetyThreshold = $MaxAllowedExemptions
            IsWithinLimits = $projectedTotal -le $MaxAllowedExemptions
            WarningLevel = "None"
        }
        
        # Determine warning level
        if ($projectedTotal -gt 1000) {
            $result.WarningLevel = "Critical"
            Write-Host "  [CRITICAL] CRITICAL: Projected total ($projectedTotal) exceeds Azure limit (1,000)!" -ForegroundColor Red
        }
        elseif ($projectedTotal -gt $MaxAllowedExemptions) {
            $result.WarningLevel = "High"
            Write-Host "  [WARNING] WARNING: Projected total ($projectedTotal) exceeds safety threshold ($MaxAllowedExemptions)!" -ForegroundColor Yellow
        }
        elseif ($projectedTotal -gt ($MaxAllowedExemptions * 0.8)) {
            $result.WarningLevel = "Medium"
            Write-Host "  [INFO] INFO: Approaching safety threshold (80% = $([int]($MaxAllowedExemptions * 0.8)))" -ForegroundColor Yellow
        }
        else {
            Write-Host "  [PASS] Within safe limits" -ForegroundColor Green
        }
        
        return $result
    }
    catch {
        Write-Warning "Could not check exemption limits for scope $Scope`: $_"
        return @{
            CurrentCount = -1
            PlannedCount = $PlannedExemptions
            ProjectedTotal = -1
            Limit = 1000
            SafetyThreshold = $MaxAllowedExemptions
            IsWithinLimits = $false
            WarningLevel = "Unknown"
        }
    }
}

function Invoke-ThrottledExemptionCreation {
    <#
    .SYNOPSIS
    Create exemptions with rate limiting to avoid Azure API throttling
    #>
    param(
        [array]$Resources,
        [array]$PolicyAssignments,
        [string]$ExemptionCategory,
        [string]$TagName,
        [string]$TagValue,
        [datetime]$ExpiresOn,
        [int]$BatchSize = 5,           # Process in batches to avoid overwhelming Azure
        [int]$DelayBetweenBatches = 2, # Seconds to wait between batches
        [int]$DelayBetweenCalls = 500  # Milliseconds to wait between individual API calls
    )
    
    Write-Host "`n=== Throttled Exemption Creation ===" -ForegroundColor Cyan
    Write-Host "Batch Size: $BatchSize exemptions per batch" -ForegroundColor Gray
    Write-Host "Delay Between Batches: $DelayBetweenBatches seconds" -ForegroundColor Gray
    Write-Host "Delay Between Calls: $DelayBetweenCalls milliseconds" -ForegroundColor Gray
    
    $totalOperations = $Resources.Count * $PolicyAssignments.Count
    $createdCount = 0
    $skippedCount = 0
    $failedCount = 0
    $currentOperation = 0
    
    Write-Host "Total Operations: $totalOperations exemptions to process`n" -ForegroundColor White
    
    # Process resources in batches
    for ($i = 0; $i -lt $Resources.Count; $i += $BatchSize) {
        $batch = $Resources[$i..[Math]::Min($i + $BatchSize - 1, $Resources.Count - 1)]
        $batchNumber = [Math]::Floor($i / $BatchSize) + 1
        $totalBatches = [Math]::Ceiling($Resources.Count / $BatchSize)
        $batchResourceCount = $batch.Count
        Write-Host "Processing Batch $batchNumber of $totalBatches - $batchResourceCount resources" -ForegroundColor Yellow
        
        foreach ($resource in $batch) {
            Write-Host "`n  Resource: $($resource.Name)" -ForegroundColor White
            
            # Get existing exemptions for this resource
            $existingExemptions = Get-ExistingExemptions -ResourceId $resource.ResourceId
            
            foreach ($assignment in $PolicyAssignments) {
                $currentOperation++
                $progressPercent = [Math]::Round(($currentOperation / $totalOperations) * 100, 1)
                
                Write-Host "    [$progressPercent%] Assignment: $($assignment.DisplayName)" -ForegroundColor Gray
                
                # Check if exemption already exists - with debug output
                Write-Host "      Checking for existing exemptions..." -ForegroundColor Gray
                Write-Host "      Assignment ID to match: $($assignment.Id)" -ForegroundColor Gray
                Write-Host "      Found $($existingExemptions.Count) existing exemptions" -ForegroundColor Gray
                
                # Debug: Show existing exemption policy assignment IDs and comparison
                Write-Host "        Target assignment ID: '$($assignment.Id)'" -ForegroundColor Cyan
                foreach ($exemption in $existingExemptions) {
                    Write-Host "        Existing exemption: $($exemption.Name) (Category: $($exemption.ExemptionCategory))" -ForegroundColor Gray
                    Write-Host "          PolicyAssignmentId: '$($exemption.PolicyAssignmentId)'" -ForegroundColor Gray
                    Write-Host "          Properties.policyAssignmentId: '$($exemption.Properties.policyAssignmentId)'" -ForegroundColor Gray
                    Write-Host "          Properties.PolicyAssignmentId: '$($exemption.Properties.PolicyAssignmentId)'" -ForegroundColor Gray
                    
                    # Check which property actually contains the policy assignment ID
                    $exemptionPolicyId = $null
                    if ($exemption.Properties.PolicyAssignmentId) {
                        $exemptionPolicyId = $exemption.Properties.PolicyAssignmentId
                    } elseif ($exemption.Properties.policyAssignmentId) {
                        $exemptionPolicyId = $exemption.Properties.policyAssignmentId
                    } elseif ($exemption.PolicyAssignmentId) {
                        $exemptionPolicyId = $exemption.PolicyAssignmentId
                    }
                    
                    Write-Host "          Detected PolicyAssignmentId: '$exemptionPolicyId'" -ForegroundColor Yellow
                    $isMatch = $exemptionPolicyId -and ($exemptionPolicyId.ToLower() -eq $assignment.Id.ToLower())
                    Write-Host "          Matches target assignment: $isMatch" -ForegroundColor $(if ($isMatch) { "Green" } else { "Red" })
                }
                
                $hasExemption = $existingExemptions | Where-Object { 
                    # Case-insensitive comparison across all possible property locations
                    $exemptionPolicyId = $null
                    if ($_.Properties.PolicyAssignmentId) {
                        $exemptionPolicyId = $_.Properties.PolicyAssignmentId
                    } elseif ($_.Properties.policyAssignmentId) {
                        $exemptionPolicyId = $_.Properties.policyAssignmentId
                    } elseif ($_.PolicyAssignmentId) {
                        $exemptionPolicyId = $_.PolicyAssignmentId
                    }
                    
                    return $exemptionPolicyId -and ($exemptionPolicyId.ToLower() -eq $assignment.Id.ToLower())
                }
                
                if ($hasExemption) {
                    Write-Host "      [PASS] Exemption already exists for this policy assignment, skipping..." -ForegroundColor Yellow
                    Write-Host "        Existing exemption: $($hasExemption.Name) (Category: $($hasExemption.ExemptionCategory))" -ForegroundColor Yellow
                    $skippedCount++
                    continue
                } else {
                    Write-Host "      [FAIL] No matching exemption found, proceeding with creation..." -ForegroundColor Yellow
                }
                
                # Create the exemption with throttling
                try {
                    $exemption = New-PolicyExemptionForResource `
                        -ResourceId $resource.ResourceId `
                        -ResourceName $resource.Name `
                        -PolicyAssignmentId $assignment.Id `
                        -ExemptionCategory $ExemptionCategory `
                        -TagName $TagName `
                        -TagValue $TagValue `
                        -ExpiresOn $ExpiresOn `
                        -ExpiresInDays $ExpiresInDays
                    
                    if ($exemption) {
                        $createdCount++
                        Write-Host "      [PASS] Created successfully" -ForegroundColor Green
                    } else {
                        $failedCount++
                        Write-Host "      [FAIL] Creation failed" -ForegroundColor Red
                    }
                    
                    # Throttle individual API calls
                    Start-Sleep -Milliseconds $DelayBetweenCalls
                }
                catch {
                    $failedCount++
                    Write-Host "      [FAIL] Exception: $_" -ForegroundColor Red
                }
            }
        }
        
        # Delay between batches (except for the last batch)
        if ($i + $BatchSize -lt $Resources.Count) {
            Write-Host "`n  Waiting $DelayBetweenBatches seconds before next batch..." -ForegroundColor Gray
            Start-Sleep -Seconds $DelayBetweenBatches
        }
    }
    
    return @{
        CreatedCount = $createdCount
        SkippedCount = $skippedCount
        FailedCount = $failedCount
        TotalOperations = $totalOperations
    }
}

function Get-ScopeExemptionSummary {
    <#
    .SYNOPSIS
    Get a summary of exemptions across multiple scopes for management groups
    #>
    param(
        [string]$ManagementGroupId,
        [switch]$IncludeChildSubscriptions
    )
    
    Write-Host "`nGathering exemption summary across scopes..." -ForegroundColor Yellow
    
    $scopeSummary = @()
    
    # Management group level
    $mgScope = "/providers/Microsoft.Management/managementGroups/$ManagementGroupId"
    $mgLimits = Test-ExemptionLimits -Scope $mgScope -PlannedExemptions 0
    
    $scopeSummary += [PSCustomObject]@{
        Scope = "Management Group"
        ScopeId = $ManagementGroupId
        CurrentExemptions = $mgLimits.CurrentCount
        WarningLevel = $mgLimits.WarningLevel
        IsAtRisk = $mgLimits.CurrentCount -gt 800
    }
    
    # Child subscriptions if requested
    if ($IncludeChildSubscriptions) {
        try {
            $mgDetails = Get-AzManagementGroup -GroupId $ManagementGroupId -Expand -Recurse
            $subscriptions = Get-ChildSubscriptions -ManagementGroupChildren $mgDetails.Children
            
            foreach ($subId in $subscriptions[0..4]) { # Limit to first 5 for performance
                $subScope = "/subscriptions/$subId"
                $subLimits = Test-ExemptionLimits -Scope $subScope -PlannedExemptions 0
                
                $scopeSummary += [PSCustomObject]@{
                    Scope = "Subscription"
                    ScopeId = $subId
                    CurrentExemptions = $subLimits.CurrentCount
                    WarningLevel = $subLimits.WarningLevel
                    IsAtRisk = $subLimits.CurrentCount -gt 800
                }
            }
            
            if ($subscriptions.Count -gt 5) {
                Write-Host "  (Showing first 5 of $($subscriptions.Count) subscriptions)" -ForegroundColor Gray
            }
        }
        catch {
            Write-Warning "Could not retrieve child subscription details: $_"
        }
    }
    
    # Display summary
    Write-Host "`n=== Exemption Summary ===" -ForegroundColor Cyan
    $scopeSummary | Format-Table -AutoSize
    
    $atRiskScopes = $scopeSummary | Where-Object { $_.IsAtRisk }
    if ($atRiskScopes) {
        Write-Host "[WARNING] WARNING: $($atRiskScopes.Count) scope(s) have >800 exemptions and may be at risk" -ForegroundColor Yellow
        foreach ($scope in $atRiskScopes) {
            Write-Host "  - $($scope.Scope): $($scope.ScopeId) ($($scope.CurrentExemptions) exemptions)" -ForegroundColor Yellow
        }
    }
    
    return $scopeSummary
}

function Test-MCSBCoverage {
    <#
    .SYNOPSIS
    Check which subscriptions do not have Microsoft Cloud Security Benchmark (MCSB) initiative assigned
    #>
    param(
        [string]$ManagementGroupId,
        [string]$SubscriptionId
    )
    
    Write-Host "`n=== Microsoft Cloud Security Benchmark Coverage Check ===" -ForegroundColor Cyan
    
    $subscriptionsToCheck = @()
    
    if ($ManagementGroupId) {
        Write-Host "Checking MCSB coverage for management group: $ManagementGroupId" -ForegroundColor Yellow
        try {
            $mgDetails = Get-AzManagementGroup -GroupId $ManagementGroupId -Expand -Recurse
            $subscriptionsToCheck = Get-ChildSubscriptions -ManagementGroupChildren $mgDetails.Children
            Write-Host "Found $($subscriptionsToCheck.Count) child subscriptions to check" -ForegroundColor Gray
        }
        catch {
            Write-Error "Could not retrieve management group details: $_"
            return
        }
    } else {
        $subscriptionsToCheck = @($SubscriptionId)
        Write-Host "Checking MCSB coverage for subscription: $SubscriptionId" -ForegroundColor Yellow
    }
    
    $coverageResults = @()
    $subscriptionsWithoutMCSB = @()
    
    foreach ($subId in $subscriptionsToCheck) {
        Write-Host "`nChecking subscription: $subId" -ForegroundColor Gray
        
        try {
            # Set context to the subscription
            $null = Set-AzContext -SubscriptionId $subId -ErrorAction Stop
            $subScope = "/subscriptions/$subId"
            
            # Get all policy assignments for this subscription
            $assignments = Get-AzPolicyAssignment -Scope $subScope -ErrorAction SilentlyContinue
            
            # Check for MCSB-related assignments
            $mscbAssignments = @()
            foreach ($assignment in $assignments) {
                $displayName = $assignment.Properties.displayName
                $name = $assignment.Name
                
                if ($displayName -like "*Microsoft Cloud Security Benchmark*" -or 
                    $displayName -like "*Azure Security Baseline*" -or
                    $name -like "*SecurityCenterBuiltIn*" -or
                    $name -like "*ASC*" -or
                    $name -like "*Azure_Security_Baseline*" -or
                    ($displayName -like "*Security*" -and $displayName -like "*Benchmark*")) {
                    
                    $mscbAssignments += [PSCustomObject]@{
                        Name = $assignment.Name
                        DisplayName = $displayName
                        AssignmentScope = $assignment.Properties.scope
                        PolicyDefinitionId = $assignment.Properties.policyDefinitionId
                    }
                }
            }
            
            $hasMCSB = $mscbAssignments.Count -gt 0
            
            if ($hasMCSB) {
                Write-Host "  [PASS] MCSB Found: $($mscbAssignments.Count) MCSB-related assignment(s)" -ForegroundColor Green
                foreach ($assignment in $mscbAssignments) {
                    Write-Host "    - $($assignment.DisplayName) ($($assignment.Name))" -ForegroundColor Gray
                }
            } else {
                Write-Host "  [FAIL] No MCSB assignments found" -ForegroundColor Red
                $subscriptionsWithoutMCSB += $subId
            }
            
            # Get subscription details for better reporting
            $subscription = Get-AzSubscription -SubscriptionId $subId -ErrorAction SilentlyContinue
            $subscriptionName = if ($subscription) { $subscription.Name } else { "Unknown" }
            
            $coverageResults += [PSCustomObject]@{
                SubscriptionId = $subId
                SubscriptionName = $subscriptionName
                HasMCSB = $hasMCSB
                MCSBAssignmentCount = $mscbAssignments.Count
                Assignments = $mscbAssignments
            }
        }
        catch {
            Write-Warning "  Could not check subscription $subId`: $_"
            $coverageResults += [PSCustomObject]@{
                SubscriptionId = $subId
                SubscriptionName = "Access Denied"
                HasMCSB = $false
                MCSBAssignmentCount = 0
                Assignments = @()
                Error = $_.Exception.Message
            }
        }
    }
    
    # Summary Report
    Write-Host "`n=== MCSB Coverage Summary ===" -ForegroundColor Cyan
    
    $totalSubscriptions = $coverageResults.Count
    $subscriptionsWithMCSB = ($coverageResults | Where-Object { $_.HasMCSB }).Count
    $subscriptionsWithoutMCSBCount = $subscriptionsWithoutMCSB.Count
    $coveragePercentage = if ($totalSubscriptions -gt 0) { [Math]::Round(($subscriptionsWithMCSB / $totalSubscriptions) * 100, 1) } else { 0 }
    
    Write-Host "Total Subscriptions Checked: $totalSubscriptions" -ForegroundColor White
    Write-Host "Subscriptions with MCSB: $subscriptionsWithMCSB" -ForegroundColor Green
    Write-Host "Subscriptions without MCSB: $subscriptionsWithoutMCSBCount" -ForegroundColor Red
    Write-Host "Coverage Percentage: $coveragePercentage%" -ForegroundColor $(if ($coveragePercentage -ge 90) { "Green" } elseif ($coveragePercentage -ge 70) { "Yellow" } else { "Red" })
    
    if ($subscriptionsWithoutMCSBCount -gt 0) {
        Write-Host "`n[WARNING] Subscriptions WITHOUT MCSB Initiative:" -ForegroundColor Red
        foreach ($subId in $subscriptionsWithoutMCSB) {
            $subDetails = $coverageResults | Where-Object { $_.SubscriptionId -eq $subId }
            Write-Host "  - $subId ($($subDetails.SubscriptionName))" -ForegroundColor Red
        }
        
        Write-Host "`n[ACTION] Recommended Actions:" -ForegroundColor Yellow
        Write-Host "  1. Assign Microsoft Cloud Security Benchmark initiative to missing subscriptions" -ForegroundColor Gray
        Write-Host "  2. Review subscription access permissions if 'Access Denied' errors occurred" -ForegroundColor Gray
        Write-Host "  3. Consider assigning MCSB at the management group level for automatic coverage" -ForegroundColor Gray
    } else {
        Write-Host "`n[PASS] All subscriptions have MCSB coverage!" -ForegroundColor Green
    }
    
    # Detailed table view
    if ($coverageResults.Count -gt 0) {
        Write-Host "`n=== Detailed Coverage Report ===" -ForegroundColor Cyan
        $coverageResults | Select-Object SubscriptionId, SubscriptionName, HasMCSB, MCSBAssignmentCount | Format-Table -AutoSize
    }
    
    return @{
        TotalSubscriptions = $totalSubscriptions
        SubscriptionsWithMCSB = $subscriptionsWithMCSB
        SubscriptionsWithoutMCSB = $subscriptionsWithoutMCSB
        CoveragePercentage = $coveragePercentage
        Results = $coverageResults
    }
}

# Main execution
Write-Host "`n=== Azure Policy Exemption Management ===" -ForegroundColor Cyan
if ($ManagementGroupId) {
    Write-Host "Management Group: $ManagementGroupId"
    if ($IncludeChildSubscriptions) {
        Write-Host "Scope: Management Group and all child subscriptions"
    } else {
        Write-Host "Scope: Management Group only"
    }
} else {
    Write-Host "Subscription: $SubscriptionId"
}
Write-Host "Tag Filter: $TagName=$TagValue"
Write-Host "Exemption Category: $ExemptionCategory"

# Display expiration information based on category and parameter
if ($ExpiresInDays -eq 0) {
    $defaultDays = if ($ExemptionCategory -eq "Waiver") { 90 } else { 365 }
    Write-Host "Expires In: $defaultDays days (default for $ExemptionCategory category)"
} else {
    Write-Host "Expires In: $ExpiresInDays days (explicitly specified)"
}
Write-Host ""

# Handle MCSB Coverage Check
if ($CheckMCSBCoverage) {
    $coverageResult = Test-MCSBCoverage -ManagementGroupId $ManagementGroupId -SubscriptionId $SubscriptionId
    Write-Host "`nMCSB Coverage Check completed." -ForegroundColor Green
    exit 0
}

# Find Defender policy assignments
Write-Host "Finding Microsoft Defender for Cloud policy assignments..." -ForegroundColor Yellow
$defenderAssignments = Find-DefenderPolicyAssignments -Scope $scope -ManagementGroupId $ManagementGroupId -SubscriptionId $SubscriptionId -IncludeChildSubscriptions:$IncludeChildSubscriptions

if ($defenderAssignments.Count -eq 0) {
    Write-Host "No Microsoft Defender for Cloud policy assignments found!" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($defenderAssignments.Count) Defender-related policy assignments:" -ForegroundColor Green
foreach ($assignment in $defenderAssignments) {
    Write-Host "  - $($assignment.DisplayName) ($($assignment.Name))" -ForegroundColor Gray
}

# Select the assignment to work with
if ($DefenderAssignmentName) {
    $selectedAssignment = $defenderAssignments | Where-Object { $_.Name -eq $DefenderAssignmentName }
    if (!$selectedAssignment) {
        Write-Host "Specified assignment '$DefenderAssignmentName' not found!" -ForegroundColor Red
        exit 1
    }
} else {
    $selectedAssignment = $defenderAssignments[0]
    Write-Host "`nUsing assignment: $($selectedAssignment.DisplayName)" -ForegroundColor Green
}

Write-Host "Selected assignment ID: $($selectedAssignment.Id)" -ForegroundColor Gray

# Find resources with the specified tag
Write-Host "`nFinding resources with tag $TagName=$TagValue..." -ForegroundColor Yellow
$resources = Find-TaggedResources -TagName $TagName -TagValue $TagValue -SubscriptionId $SubscriptionId -ManagementGroupId $ManagementGroupId -IncludeChildSubscriptions:$IncludeChildSubscriptions

if ($resources.Count -eq 0) {
    Write-Host "No resources found with tag $TagName=$TagValue" -ForegroundColor Red
    exit 0
}

Write-Host "Found $($resources.Count) resources with the specified tag:" -ForegroundColor Green
foreach ($resource in $resources) {
    Write-Host "  - $($resource.Name) ($($resource.ResourceType))" -ForegroundColor Gray
}

if ($ListOnly) {
    Write-Host "`n=== Existing Exemptions ===" -ForegroundColor Cyan
    foreach ($resource in $resources) {
        Write-Host "`nResource: $($resource.Name)" -ForegroundColor Yellow
        $existingExemptions = Get-ExistingExemptions -ResourceId $resource.ResourceId
        
        if ($existingExemptions.Count -eq 0) {
            Write-Host "  No exemptions found" -ForegroundColor Gray
        } else {
            foreach ($exemption in $existingExemptions) {
                Write-Host "  - $($exemption.Name) (Category: $($exemption.ExemptionCategory), Expires: $($exemption.ExpiresOn))" -ForegroundColor Green
            }
        }
    }
    exit 0
}

if ($CreateExemptions) {
    Write-Host "`n=== Creating Exemptions ===" -ForegroundColor Cyan
    
    # Set expiration days based on category if not explicitly specified
    if ($ExpiresInDays -eq 0) {
        $ExpiresInDays = if ($ExemptionCategory -eq "Waiver") { 90 } else { 365 }
        Write-Host "Using category-based expiration: $ExpiresInDays days for $ExemptionCategory category" -ForegroundColor Yellow
    }
    
    $expiresOn = (Get-Date).AddDays($ExpiresInDays)
    $createdCount = 0
    $skippedCount = 0
    
    # Check exemption limits before proceeding
    $totalPlannedExemptions = $resources.Count * $defenderAssignments.Count
    Write-Host "Planned exemptions calculation: $($resources.Count) resources x $($defenderAssignments.Count) policy assignments = $totalPlannedExemptions exemptions" -ForegroundColor Gray
    
    $limitCheck = Test-ExemptionLimits -Scope $scope -PlannedExemptions $totalPlannedExemptions -Resources $resources
    if (-not $limitCheck.IsWithinLimits) {
        Write-Host "Cannot proceed: Exemption limits exceeded or at risk!" -ForegroundColor Red
        exit 1
    }
    
    $result = Invoke-ThrottledExemptionCreation `
        -Resources $resources `
        -PolicyAssignments $defenderAssignments `
        -ExemptionCategory $ExemptionCategory `
        -TagName $TagName `
        -TagValue $TagValue `
        -ExpiresOn $expiresOn
    
    Write-Host "`n=== Summary ===" -ForegroundColor Cyan
    Write-Host "Created: $($result.CreatedCount) exemptions" -ForegroundColor Green
    Write-Host "Skipped: $($result.SkippedCount) exemptions (already exist)" -ForegroundColor Yellow
    Write-Host "Failed: $($result.FailedCount) exemptions" -ForegroundColor Red
    Write-Host "Total Operations: $($result.TotalOperations)" -ForegroundColor Gray
} else {
    Write-Host "`nUse -CreateExemptions switch to create exemptions" -ForegroundColor Yellow
    Write-Host "Use -ListOnly switch to only list existing exemptions" -ForegroundColor Yellow
}

Write-Host "`nScript completed." -ForegroundColor Green