# GitHub Team-to-Repository Mapping Script

## Overview

The `map_teams_to_repos.ps1` PowerShell script automates the process of granting GitHub teams access to repositories based on CSV file mappings. The script intelligently analyzes team member roles and grants appropriate permission levels to ensure teams have the access they need.

## Features

- ✅ **Role-Based Permissions**: Analyzes CSV roles to determine appropriate team permissions
- ✅ **Permission Hierarchy**: Grants highest permission level among team members
- ✅ **Team Validation**: Verifies teams exist before granting repository access
- ✅ **Repository Validation**: Confirms repositories exist in the organization
- ✅ **Duplicate Prevention**: Processes unique repository-team pairs only
- ✅ **Dry Run Support**: Preview changes before applying them
- ✅ **Environment File Support**: Load configuration from `.env` files

## Prerequisites

### Software Requirements
- **PowerShell 7+** (Cross-platform)
- **GitHub Personal Access Token** with appropriate permissions

### GitHub Token Permissions
Your GitHub token needs the following permissions:
- `repo` (Full repository access)
- `admin:org` (Organization administration)

### Environment Variables
Create a `.env` file in the script directory or set these environment variables:

```bash
GITHUB_TOKEN=ghp_your_github_personal_access_token_here
GITHUB_ORG=your-github-organization-name
# GHE_URL=https://your-github-enterprise-url.com  # Only for GitHub Enterprise
```

## CSV File Format

The script reads the same CSV format as `provision_users.ps1`:

| Column | Description | Usage |
|--------|-------------|-------|
| `Repo` | Repository name | Used to identify target repository |
| `User` | GitHub username | Used to group by team |
| `Role` | User role (Admin, Write, Read, etc.) | Analyzed to determine team permissions |
| `Team` | Team name | Target team for repository access |

### Processing Logic

1. **Team Filtering**: Only processes entries where `Team` column is not empty
2. **Role Analysis**: Collects all roles for each repository-team combination
3. **Permission Calculation**: Determines highest permission level needed for the team
4. **Access Grant**: Grants team access to repository with calculated permission

## Permission Hierarchy

The script uses the following permission hierarchy (highest to lowest):

| Priority | Role | GitHub Permission | Description |
|----------|------|-------------------|-------------|
| 1 (Highest) | `Admin` | `admin` | Full administrative access |
| 2 | `Maintain` | `maintain` | Maintain access (manage settings) |
| 3 | `Write` | `push` | Read and write access |
| 4 | `Triage` | `triage` | Triage access (manage issues/PRs) |
| 5 (Lowest) | `Read` | `pull` | Read-only access |

### Example Scenarios

**Scenario 1**: Team has mixed roles
```csv
Repo,User,Role,Team
my-app,dev1,Read,frontend-team
my-app,dev2,Write,frontend-team
```
**Result**: `frontend-team` gets `push` permission (highest among Read/Write)

**Scenario 2**: Team has admin member
```csv
Repo,User,Role,Team
my-api,lead1,Admin,backend-team  
my-api,dev3,Write,backend-team
```
**Result**: `backend-team` gets `admin` permission (highest among Admin/Write)

## Usage Examples

### Basic Usage

```powershell
# Map teams to repositories based on CSV roles
./map_teams_to_repos.ps1 -CsvFilePath './users/User_Provisioning.csv'
```

### Dry Run (Recommended First)

```powershell
# Preview what permissions would be granted
./map_teams_to_repos.ps1 -CsvFilePath './users/User_Provisioning.csv' -DryRun
```

### Running on macOS

```bash
# From Terminal using pwsh
pwsh -File ./map_teams_to_repos.ps1 -CsvFilePath './users/User_Provisioning.csv'

# Or launch PowerShell first
pwsh
./map_teams_to_repos.ps1 -CsvFilePath './users/User_Provisioning.csv'
```

## Sample CSV and Expected Results

### Input CSV
```csv
Repo,User,Role,Team
hello-world,alice,Read,good-team
hello-world,bob,Read,good-team
hello-world,carol,Write,nice-team
hello-world,dave,Write,nice-team
hello-world,admin,Admin,
```

### Expected Processing
- `good-team`: Gets `pull` permission (all members have Read roles)
- `nice-team`: Gets `push` permission (all members have Write roles)  
- `admin` user: Ignored (no team specified, handled by `provision_users.ps1`)

## Script Output

The script provides detailed output showing role analysis:

```
Found 6 entries in CSV file.
Found 2 unique repository-team mappings to process.

Processing: Repository 'hello-world' -> Team 'good-team' (slug: good-team) with 'pull' permission (Roles: Read, Read)
Granting team 'good-team' 'pull' access to repository 'hello-world'...
Successfully granted team 'good-team' 'pull' access to repository 'hello-world'

Processing: Repository 'hello-world' -> Team 'nice-team' (slug: nice-team) with 'push' permission (Roles: Write, Write)
Granting team 'nice-team' 'push' access to repository 'hello-world'...
Successfully granted team 'nice-team' 'push' access to repository 'hello-world'

--- Team-to-Repository Mapping Summary ---
Successful repository access grants: 2
Failed repository access grants: 0
Permissions determined dynamically based on team member roles
```

## Error Handling

The script handles various error scenarios:

- **Repository Not Found**: Validates repository exists before granting access
- **Team Not Found**: Checks team exists and suggests running `provision_users.ps1` first
- **API Errors**: Provides detailed error messages for GitHub API failures
- **Invalid Data**: Skips entries with missing repository or team information

## Integration Workflow

This script is designed to work with `provision_users.ps1` in a two-step workflow:

### Step 1: User and Team Provisioning
```powershell
./provision_users.ps1 -CsvFilePath './users/User_Provisioning.csv'
```
- Creates teams if they don't exist
- Adds users to teams
- Grants direct repository access where specified

### Step 2: Team Repository Access
```powershell
./map_teams_to_repos.ps1 -CsvFilePath './users/User_Provisioning.csv'
```
- Analyzes team member roles
- Grants teams appropriate repository permissions
- Ignores entries without team assignments

## Troubleshooting

### Common Issues

1. **"Team not found"**
   - Run `provision_users.ps1` first to create teams and add members
   - Verify team names match exactly between scripts

2. **"Repository not found"**
   - Check repository name spelling
   - Ensure repository exists in the specified organization
   - Verify token has access to the repository

3. **"No mappings to process"**
   - Ensure CSV has entries with both `Repo` and `Team` columns filled
   - Check CSV format and column headers

### Debugging Tips

**Enable verbose output:**
```powershell
./map_teams_to_repos.ps1 -CsvFilePath './users/test.csv' -Verbose
```

**Check team slug conversion:**
- Team names are converted to slugs (lowercase, dots/spaces → hyphens)
- Example: "My Team.Name" becomes "my-team-name"

**Validate CSV structure:**
```powershell
Import-Csv './users/test.csv' | Format-Table
```

## Security Considerations

- **Token Security**: Store tokens securely, never commit to version control
- **Principle of Least Privilege**: Teams get minimum permissions needed
- **Audit Trail**: Script provides detailed logs for compliance
- **Role Validation**: Unknown roles default to `pull` permission with warnings

## Advanced Usage

### Custom Permission Override
If you need all teams to have a specific permission regardless of member roles, modify the CSV to have consistent roles for all team members.

### Batch Processing
Process multiple CSV files:
```powershell
Get-ChildItem -Path ".\users\*.csv" | ForEach-Object {
    ./map_teams_to_repos.ps1 -CsvFilePath $_.FullName -DryRun
}
```

### Role Distribution Analysis
Analyze role distribution before processing:
```powershell
$data = Import-Csv './users/User_Provisioning.csv'
$data | Where-Object { $_.Team } | Group-Object Team, Role | Format-Table Count, Name
```

## Version History

- **v1.0**: Initial release with fixed permission parameter
- **v2.0**: Added role-based permission calculation
- **v2.1**: Enhanced role analysis and permission hierarchy
- **v2.2**: Improved error handling and team validation

## Support

For issues or questions:
1. Review the troubleshooting section
2. Ensure proper workflow order (`provision_users.ps1` then `map_teams_to_repos.ps1`)
3. Verify CSV format matches expected structure
4. Check GitHub API documentation for permission details