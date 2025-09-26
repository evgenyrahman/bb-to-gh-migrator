# GitHub User Provisioning Script

## Overview

The `provision_users.ps1` PowerShell script automates the process of provisioning GitHub users to teams or granting direct repository access based on a CSV file mapping. This script supports both team-based access management and direct repository collaborator assignments.

## Features

- **Dual Mode Operation**: Handles both team assignments and direct repository access
- **Flexible Input Types**: Supports both GitHub usernames and EMU email addresses
- **EMU Email Mapping**: Automatically maps EMU emails to usernames via CSV lookup
- **Team Management**: Automatically creates teams if they don't exist
- **Role Mapping**: Converts role names to appropriate GitHub permissions
- **Validation**: Comprehensive validation of users, organizations, and repositories
- **Dry Run Support**: Test changes before applying them
- **Environment File Support**: Load configuration from `.env` files

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
| `User` | GitHub username or EMU email (depending on InputType) | Yes |
| `Role` | User role (Admin, Write, Read, Maintain, Triage) | Yes (for direct access) |
| `Team` | Team name | Yes (for team assignment) |

### Input Types

The script supports two input types via the `-InputType` parameter:

- **`Username`** (default): The `User` column contains GitHub usernames
- **`EMUEmail`**: The `User` column contains EMU email addresses that are mapped to usernames

## EMU User Mapping

When using `-InputType EMUEmail`, the script requires a `user_mapping.csv` file in the same directory as your input CSV file.

### user_mapping.csv Format

```csv
username,useremail
github_username1,user1@company.onmicrosoft.com
github_username2,user2@company.onmicrosoft.com
```

| Column | Description |
|--------|--------------|
| `username` | The actual GitHub username |
| `useremail` | The EMU email address |

### EMU Mapping Process

1. Script reads EMU email from main CSV file
2. Looks up email in `user_mapping.csv` (case-insensitive)
3. Retrieves corresponding GitHub username
4. Uses username for all GitHub API operations
5. If email not found in mapping file, user is skipped with warning

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

### EMU Email Input

```powershell
# Use EMU email addresses (requires user_mapping.csv)
./provision_users.ps1 -CsvFilePath './users/User_Provisioning.csv' -InputType EMUEmail

# EMU with dry run
./provision_users.ps1 -CsvFilePath './users/User_Provisioning.csv' -InputType EMUEmail -DryRun
```

### Running on macOS

```bash
# From Terminal using pwsh
pwsh -File ./provision_users.ps1 -CsvFilePath './users/User_Provisioning.csv'

# Or launch PowerShell first
pwsh
./provision_users.ps1 -CsvFilePath './users/User_Provisioning.csv'
```

## Sample CSV Files

### Username Input (Default)

```csv
Repo,User,Role,Team
my-repo,john-doe,Read,developers
my-repo,jane-smith,Write,developers
my-repo,admin-user,Admin,
my-repo,external-dev,Write,
```

### EMU Email Input

**Main CSV file (User_Provisioning.csv):**
```csv
Repo,User,Role,Team
my-repo,john@company.onmicrosoft.com,Read,developers
my-repo,jane@company.onmicrosoft.com,Write,developers
my-repo,admin@company.onmicrosoft.com,Admin,
```

**User mapping file (user_mapping.csv):**
```csv
username,useremail
john-doe_company,john@company.onmicrosoft.com
jane-smith_company,jane@company.onmicrosoft.com
admin-user_company,admin@company.onmicrosoft.com
```

In both examples:
- Users are added to the `developers` team or get direct repository access
- EMU emails are automatically mapped to their corresponding GitHub usernames

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
- **EMU mapping errors**:
  - Missing `user_mapping.csv` file when using EMUEmail input type
  - Email not found in mapping file
  - Mapped username not found on GitHub
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

4. **EMU-related Issues**
   - **"User mapping file not found"**: Ensure `user_mapping.csv` exists in the same directory as your input CSV
   - **"Email not found in user_mapping.csv"**: Verify the email exists in the mapping file (check for typos)
   - **"Mapped username not found on GitHub"**: The username from the mapping file doesn't exist on GitHub
   - **"Missing required columns"**: Ensure `user_mapping.csv` has both `username` and `useremail` columns

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
- **v2.3**: Added EMU email support with user mapping CSV functionality

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review GitHub API documentation
3. Verify token permissions and organization settings