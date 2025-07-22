# Security Policy

## Security Considerations

This repository contains PowerShell scripts that manage Azure Policy exemptions for Microsoft Defender for Cloud. Please consider the following security implications:

### Before Use
- **Test First**: Always test scripts in a non-production environment
- **Review Permissions**: Ensure you understand what Azure RBAC permissions are required
- **Audit Trail**: Enable Azure Activity Log monitoring for policy exemption changes
- **Principle of Least Privilege**: Use the minimum required permissions

### Security Implications
- **Policy Exemptions**: Creating exemptions can reduce security coverage
- **Compliance Impact**: May affect compliance reporting and security benchmarks
- **Regular Review**: Exemptions should be reviewed periodically for continued relevance

### Best Practices
1. **Documentation**: Document the business justification for each exemption
2. **Expiration Dates**: Set appropriate expiration dates (script defaults: 90 days for Waivers, 365 days for Mitigated)
3. **Monitoring**: Monitor for unexpected exemption creation or modifications
4. **Access Control**: Limit who can run these scripts in production environments

## Reporting Security Issues

If you discover a security vulnerability in this repository, please:

1. **Do not** open a public GitHub issue
2. Send details to the repository maintainer via GitHub private message
3. Include steps to reproduce the issue
4. Allow reasonable time for response and resolution

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Security Checklist

Before using these scripts in production:

- [ ] Read all documentation (README.md, TROUBLESHOOTING.md, etc.)
- [ ] Test in a development environment
- [ ] Verify Azure RBAC permissions are appropriate
- [ ] Enable audit logging for policy changes
- [ ] Establish a process for regular exemption review
- [ ] Train users on security implications
