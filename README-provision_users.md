# GitHub User Provisioning Script

## Overview

The `provision_users.ps1` PowerShell script automates the process of provisioning GitHub users to teams or granting direct repository access based on a CSV file mapping. This script supports both team-based access management and direct repository collaborator assignments.

## Features

- ✅ **Dual Mode Operation**: Handles both team assignments and direct repository access
- ✅ **Username-Based**: Works with GitHub usernames (not email addresses) for efficiency
- ✅ **Team Management**: Automatically creates teams if they don't exist
- ✅ **Role Mapping**: Converts role names to appropriate GitHub permissions
- ✅ **Validation**: Comprehensive validation of users, organizations, and repositories
- ✅ **Dry Run Support**: Test changes before applying them
- ✅ **Environment File Support**: Load configuration from `.env` files

## Prerequisites

### Software Requirements
- **PowerShell 7+** (Cross-platform)
- **GitHub Personal Access Token** with appropriate permissions

### GitHub Token Permissions
Your GitHub token needs the following permissions:
- `repo` (Full repository access)
- `admin:org` (Organization administration)
- `user` (User information access)

### Environment Variables
Create a `.env` file in the script directory or set these environment variables:

```bash
GITHUB_TOKEN=ghp_your_github_personal_access_token_here
GITHUB_ORG=your-github-organization-name
# GHE_URL=https://your-github-enterprise-url.com  # Only for GitHub Enterprise
```

## CSV File Format

The script expects a CSV file with the following columns:

| Column | Description | Required |
|--------|-------------|----------|
| `Repo` | Repository name | Yes (for direct access) |
| `User` | GitHub username | Yes |
| `Role` | User role (Admin, Write, Read, Maintain, Triage) | Yes (for direct access) |
| `Team` | Team name | Yes (for team assignment) |

### Processing Logic

1. **Team Assignment**: If `Team` column has a value, user is added to the specified team
2. **Direct Repository Access**: If `Team` is empty but `Role` and `Repo` are specified, user gets direct repository access

### Role to Permission Mapping

| Role | GitHub Permission | Description |
|------|-------------------|-------------|
| `Admin` | `admin` | Full administrative access |
| `Write` | `push` | Read and write access |
| `Read` | `pull` | Read-only access |
| `Maintain` | `maintain` | Maintain access (triage + some admin) |
| `Triage` | `triage` | Triage access (manage issues/PRs) |

## Usage Examples

### Basic Usage

```powershell
# Run the provisioning script
./provision_users.ps1 -CsvFilePath './users/User_Provisioning.csv'
```

### Dry Run (Recommended First)

```powershell
# Test what changes would be made without applying them
./provision_users.ps1 -CsvFilePath './users/User_Provisioning.csv' -DryRun
```

### Running on macOS

```bash
# From Terminal using pwsh
pwsh -File ./provision_users.ps1 -CsvFilePath './users/User_Provisioning.csv'

# Or launch PowerShell first
pwsh
./provision_users.ps1 -CsvFilePath './users/User_Provisioning.csv'
```

## Sample CSV File

```csv
Repo,User,Role,Team
my-repo,john-doe,Read,developers
my-repo,jane-smith,Write,developers
my-repo,admin-user,Admin,
my-repo,external-dev,Write,
```

In this example:
- `john-doe` and `jane-smith` are added to the `developers` team
- `admin-user` gets direct admin access to `my-repo`
- `external-dev` gets direct write access to `my-repo`

## Script Output

The script provides detailed output including:

```
Processing user: john-doe -> Team: developers
Successfully added user 'john-doe' to team 'developers'

Processing user: admin-user -> Repository: my-repo (Role: Admin -> Permission: admin)
Successfully granted user 'admin-user' 'admin' access to repository 'my-repo'

--- Provisioning Summary ---
Users successfully processed: 4
Failed user operations: 0
Teams processed: 1
Direct repository access grants: 2
```

## Error Handling

The script handles various error scenarios:

- **User not found**: Warns if GitHub username doesn't exist
- **Organization membership**: Checks if user is member of organization for team assignments
- **Repository validation**: Verifies repository exists before granting access
- **Team creation**: Automatically creates teams that don't exist
- **API errors**: Provides detailed error messages for GitHub API failures

## Troubleshooting

### Common Issues

1. **"User not found in organization"**
   - User needs to be invited to the organization first
   - For direct repository access, external collaborators are allowed

2. **"Repository not found"**
   - Verify repository name is correct
   - Ensure token has access to the repository

3. **"Team creation failed"**
   - Check if token has organization admin permissions
   - Verify team name doesn't conflict with existing teams

### PowerShell Execution Policy (Windows)

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Debugging

Enable verbose output:
```powershell
./provision_users.ps1 -CsvFilePath './users/test.csv' -Verbose
```

## Security Considerations

- **Token Security**: Never commit `.env` files with tokens to version control
- **Least Privilege**: Use tokens with minimal required permissions
- **Audit Trail**: The script provides detailed logs for audit purposes
- **Dry Run**: Always test with `-DryRun` first in production environments

## Integration with Other Scripts

This script works in conjunction with `map_teams_to_repos.ps1`:

1. **First**: Run `provision_users.ps1` to set up users and teams
2. **Second**: Run `map_teams_to_repos.ps1` to grant teams repository access

## Version History

- **v1.0**: Initial release with email-based user lookup
- **v2.0**: Updated to use GitHub usernames for improved performance
- **v2.1**: Added dual-mode operation (team + direct repository access)
- **v2.2**: Enhanced role mapping and permission handling

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review GitHub API documentation
3. Verify token permissions and organization settings