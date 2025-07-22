# Contributing to MDCExemptions-PowerShell

Thank you for your interest in contributing to the Microsoft Defender for Cloud Policy Exemption Management solution! This document provides guidelines for contributing to this project.

## 🚨 **IMPORTANT SECURITY NOTICE**

This project deals with Azure security policies and exemptions. All contributions must prioritize security and follow strict guidelines to prevent security vulnerabilities or misconfigurations.

## 📋 **How to Contribute**

### 1. **Before You Start**
- Read all documentation (README.md, SECURITY.md, TROUBLESHOOTING.md)
- Understand Azure Policy exemptions and their security implications
- Test any changes in a non-production environment
- Ensure you have appropriate Azure permissions for testing

### 2. **Getting Started**
1. Fork the repository
2. Create a feature branch from `main`: `git checkout -b feature/your-feature-name`
3. Make your changes following the guidelines below
4. Test thoroughly (see Testing Guidelines section)
5. Submit a pull request

### 3. **Types of Contributions Welcome**
- 🐛 Bug fixes and error handling improvements
- 📚 Documentation improvements and clarifications  
- ✨ New features that enhance security or usability
- 🧪 Additional test cases and validation scripts
- 🔧 Performance optimizations
- 🌐 Localization and accessibility improvements

## 💻 **Development Guidelines**

### **PowerShell Best Practices**
```powershell
# Use approved verbs and proper naming
function Get-SomethingUseful { }
function Set-SomethingImportant { }

# Include comprehensive help
<#
.SYNOPSIS
Brief description of the function

.DESCRIPTION
Detailed description of what the function does

.PARAMETER ParameterName
Description of the parameter

.EXAMPLE
Example of how to use the function
#>

# Use proper error handling
try {
    # Your code here
}
catch {
    Write-Warning "Descriptive error message: $_"
    # Handle appropriately
}

# Use consistent formatting and indentation (4 spaces)
if ($condition) {
    Write-Host "Consistent formatting" -ForegroundColor Green
}
```

### **Code Standards**
- **Error Handling**: Every function must include proper error handling with meaningful messages
- **Logging**: Use consistent Write-Host, Write-Warning, and Write-Error patterns
- **Comments**: Include comments for complex logic and security-critical sections
- **ASCII Only**: Use only ASCII characters (no Unicode symbols) for cross-region compatibility
- **Security First**: Always validate inputs and consider security implications

### **Documentation Standards**
- Update README.md for new features
- Include inline help for all functions
- Add examples for new parameters or features
- Update TROUBLESHOOTING.md for new known issues

## 🧪 **Testing Guidelines**

### **Required Testing**
All contributions must be tested with:

1. **Basic Functionality Testing**
   ```powershell
   # Test read-only operations first
   .\Test-ManagementGroupExemptions.ps1 -ManagementGroupId "your-mg-id"
   
   # Test with ListOnly flag
   .\Manage-DefenderExemptions.ps1 -SubscriptionId "your-sub-id" -ListOnly
   ```

2. **Security Testing**
   - Test with minimal required permissions
   - Verify no credentials are logged or exposed
   - Test error handling with invalid inputs
   - Verify exemptions are created with correct expiration dates

3. **Cross-Environment Testing**
   - Test with different Azure subscription types
   - Test with various management group structures
   - Test with different PowerShell versions (5.1 and 7+)
   - Test on different operating systems if possible

### **Test Environments**
- **NEVER** test in production environments
- Use development/testing subscriptions only
- Clean up any test resources after testing
- Document any test setup requirements

## 🔐 **Security Guidelines**

### **Critical Security Requirements**
- **No Credentials**: Never commit credentials, subscription IDs, or sensitive data
- **Input Validation**: Always validate and sanitize user inputs
- **Least Privilege**: Scripts should require minimal necessary permissions
- **Audit Trail**: Maintain clear logging for security auditing
- **Expiration**: Ensure exemptions have appropriate expiration dates

### **Security Review Process**
All changes affecting security functionality will undergo additional review:
- Policy exemption creation logic
- Permission validation
- Input sanitization
- Error handling that might expose sensitive information

## 📝 **Pull Request Process**

### **PR Requirements**
1. **Title**: Clear, descriptive title explaining the change
2. **Description**: Detailed explanation of what changed and why
3. **Testing**: Document what testing was performed
4. **Security Impact**: Describe any security implications
5. **Breaking Changes**: Highlight any breaking changes

### **PR Template**
```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Testing Performed
- [ ] Tested with read-only operations
- [ ] Tested exemption creation/listing
- [ ] Tested error handling
- [ ] Tested with minimal permissions
- [ ] Cross-environment testing completed

## Security Considerations
- [ ] No credentials or sensitive data exposed
- [ ] Input validation implemented
- [ ] Error handling doesn't leak sensitive information
- [ ] Changes follow principle of least privilege

## Checklist
- [ ] Code follows PowerShell best practices
- [ ] Documentation updated (README, help text, etc.)
- [ ] ASCII-only characters used
- [ ] Changes tested in non-production environment
- [ ] Security implications considered and documented
```

## 🚫 **What NOT to Include**

- Hardcoded credentials or subscription IDs
- Unicode characters (use ASCII alternatives)
- Breaking changes without clear justification
- Code that bypasses security validations
- Untested functionality
- Changes that don't follow PowerShell best practices

## ❓ **Questions or Issues?**

- **General Questions**: Open a discussion in GitHub Discussions
- **Bug Reports**: Use the Bug Report issue template
- **Feature Requests**: Use the Feature Request issue template
- **Security Issues**: Follow the security reporting process in SECURITY.md

## 🏆 **Recognition**

Contributors will be recognized in:
- README.md contributor section
- Release notes for significant contributions
- GitHub contributor statistics

## 📖 **Additional Resources**

- [PowerShell Best Practices and Style Guide](https://poshcode.gitbook.io/powershell-practice-and-style/)
- [Azure Policy Documentation](https://docs.microsoft.com/en-us/azure/governance/policy/)
- [Microsoft Defender for Cloud Documentation](https://docs.microsoft.com/en-us/azure/defender-for-cloud/)
- [Azure RBAC Documentation](https://docs.microsoft.com/en-us/azure/role-based-access-control/)

---

**Thank you for contributing to making Azure security management easier and more secure!** 🛡️
