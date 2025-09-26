<#
.SYNOPSIS
    Maps GitHub teams to repository access based on a CSV file with role-based permissions.
.DESCRIPTION
    This PowerShell script automates the process of granting GitHub teams access to repositories
    within an organization. It reads a CSV file containing team-to-repository mappings and performs
    the following operations:
    1. Validates that the specified GitHub organization, teams, and repositories exist.
    2. Analyzes the Role column to determine appropriate permissions for each team.
    3. Grants teams the highest permission level found among their members (Read->pull, Write->push, Admin->admin).
    4. Ignores entries where Team is empty (those are handled by provision_users.ps1 for direct access).
    5. Reports on successful and failed repository access grants.
.PARAMETER CsvFilePath
    The path to the CSV file containing team-to-repository mapping data.
    Expected columns: Repo, User, Role, Team
.PARAMETER DryRun
    When specified, performs a dry run without making actual changes to GitHub repository permissions.
    Useful for validating the CSV data and checking what changes would be made.
.EXAMPLE
    ./map_teams_to_repos.ps1 -CsvFilePath './users/User_Provisioning.csv'

    This command reads the team-to-repository mapping data from the specified CSV file and grants
    teams appropriate permissions based on their members' roles in the GitHub organization specified
    by the $env:GITHUB_ORG environment variable.
.EXAMPLE
    ./map_teams_to_repos.ps1 -CsvFilePath './users/User_Provisioning.csv' -DryRun

    This command performs a dry run, showing what permissions would be granted to teams based on
    their members' roles without actually modifying the GitHub repository permissions.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvFilePath,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

# --- Configuration & Prerequisites ---

# Load environment variables from .env file if it exists
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $name, $value = $_.Split('=', 2)
        if ($null -eq (Get-Item -Path "env:$name" -ErrorAction SilentlyContinue)) {
            Write-Verbose "Setting environment variable from .env file: $name"
            Set-Item -Path "env:$name" -Value $value
        }
    }
}

# Get credentials from environment variables
$GITHUB_TOKEN = $env:GITHUB_TOKEN
$GITHUB_ORG = $env:GITHUB_ORG
$GHE_URL = $env:GHE_URL # For GitHub Enterprise

# Construct GitHub API URL
$GITHUB_API_URL = if ($GHE_URL) { "$GHE_URL/api/v3" } else { "https://api.github.com" }

# --- Function Definitions ---

function Get-GitHubHeaders {
    return @{
        "Authorization" = "token $GITHUB_TOKEN"
        "Accept"        = "application/vnd.github.v3+json"
    }
}

function Test-GitHubOrganization {
    param([string]$OrgName)

    Write-Host "Validating GitHub organization '$OrgName'..."
    $headers = Get-GitHubHeaders
    $url = "$GITHUB_API_URL/orgs/$OrgName"

    try {
        Invoke-RestMethod -Uri $url -Method Get -Headers $headers | Out-Null
        Write-Host "Organization '$OrgName' found." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Organization '$OrgName' not found or not accessible: $($_.Exception.Message)"
        return $false
    }
}

function Test-GitHubRepository {
    param(
        [string]$OrgName,
        [string]$RepoName
    )

    $headers = Get-GitHubHeaders
    $url = "$GITHUB_API_URL/repos/$OrgName/$RepoName"

    try {
        Invoke-RestMethod -Uri $url -Method Get -Headers $headers | Out-Null
        return $true
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            return $false
        }
        Write-Error "Error checking repository '$RepoName': $($_.Exception.Message)"
        return $false
    }
}

function Get-GitHubTeam {
    param(
        [string]$OrgName,
        [string]$TeamSlug
    )

    $headers = Get-GitHubHeaders
    $url = "$GITHUB_API_URL/orgs/$OrgName/teams/$TeamSlug"

    try {
        $team = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        return $team
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            return $null
        }
        Write-Error "Error retrieving team '$TeamSlug': $($_.Exception.Message)"
        return $null
    }
}

function Grant-TeamRepositoryAccess {
    param(
        [string]$OrgName,
        [string]$TeamSlug,
        [string]$RepoName,
        [string]$Permission,
        [array]$CustomRoles = @()
    )

    $headers = Get-GitHubHeaders
    $url = "$GITHUB_API_URL/orgs/$OrgName/teams/$TeamSlug/repos/$OrgName/$RepoName"

    # Check if this is a custom role
    $customRole = $CustomRoles | Where-Object { $_.name -ieq $Permission }
    if ($customRole) {
        # For custom roles, we need to use the role_name parameter instead of permission
        $body = @{
            role_name = $customRole.name
        } | ConvertTo-Json
        Write-Verbose "Using custom role '$($customRole.name)' for team '$TeamSlug'"
    }
    else {
        # For standard roles, use the permission parameter
        $body = @{
            permission = $Permission
        } | ConvertTo-Json
    }

    try {
        Invoke-RestMethod -Uri $url -Method Put -Headers $headers -Body $body -ContentType "application/json" | Out-Null
        return $true
    }
    catch {
        Write-Error "Error granting team '$TeamSlug' access to repository '$RepoName': $($_.Exception.Message)"
        return $false
    }
}

function Convert-TeamNameToSlug {
    param([string]$TeamName)

    # Convert team name to GitHub team slug format (lowercase, replace dots/spaces with hyphens)
    return $TeamName.ToLower() -replace '[.\s]+', '-'
}

function Get-CustomRepositoryRoles {
    param([string]$OrgName)

    $headers = Get-GitHubHeaders
    $url = "$GITHUB_API_URL/orgs/$OrgName/custom-repository-roles"

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        return $response.custom_roles
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            Write-Verbose "Custom repository roles not available or not found for organization '$OrgName'"
            return @()
        }
        Write-Warning "Error retrieving custom repository roles: $($_.Exception.Message)"
        return @()
    }
}

function Convert-RoleToPermission {
    param(
        [string]$Role,
        [array]$CustomRoles = @()
    )

    # First check if it's a custom role
    $customRole = $CustomRoles | Where-Object { $_.name -ieq $Role }
    if ($customRole) {
        Write-Verbose "Using custom repository role: '$($customRole.name)' (ID: $($customRole.id))"
        return $customRole.name  # Return the custom role name as-is
    }

    # Convert standard role names to GitHub repository permission levels
    switch ($Role.ToLower()) {
        "admin" { return "admin" }
        "write" { return "push" }
        "read" { return "pull" }
        "maintain" { return "maintain" }
        "triage" { return "triage" }
        default {
            Write-Warning "Unknown role '$Role', defaulting to 'pull' permission"
            return "pull"
        }
    }
}

function Get-TeamPermissionLevel {
    param(
        [array]$Roles,
        [array]$CustomRoles = @()
    )

    # Convert roles to permissions
    $permissions = $Roles | ForEach-Object { Convert-RoleToPermission -Role $_ -CustomRoles $CustomRoles }

    # If any custom roles are present, we need special handling
    $customPermissions = @()
    $standardPermissions = @()

    foreach ($permission in $permissions) {
        $isCustom = $CustomRoles | Where-Object { $_.name -ieq $permission }
        if ($isCustom) {
            $customPermissions += $permission
        } else {
            $standardPermissions += $permission
        }
    }

    # If we have custom roles, prioritize them (you may want to adjust this logic based on your needs)
    if ($customPermissions.Count -gt 0) {
        # For now, return the first custom role found (you might want more sophisticated logic)
        Write-Verbose "Team has custom role(s): $($customPermissions -join ', '). Using: $($customPermissions[0])"
        return $customPermissions[0]
    }

    # Handle standard permissions with hierarchy
    # Priority: admin > maintain > push > triage > pull
    if ($standardPermissions -contains "admin") { return "admin" }
    if ($standardPermissions -contains "maintain") { return "maintain" }
    if ($standardPermissions -contains "push") { return "push" }
    if ($standardPermissions -contains "triage") { return "triage" }
    return "pull"
}

# --- Main Script Logic ---

# Validate environment variables
if (-not ($GITHUB_TOKEN -and $GITHUB_ORG)) {
    Write-Error "Ensure required environment variables are set in your session or in a .env file."
    Write-Error "Required: GITHUB_TOKEN, GITHUB_ORG"
    exit 1
}

# Validate CSV file exists
if (-not (Test-Path $CsvFilePath)) {
    Write-Error "CSV file not found: $CsvFilePath"
    exit 1
}

# Validate GitHub organization
if (-not (Test-GitHubOrganization -OrgName $GITHUB_ORG)) {
    exit 1
}

if ($DryRun) {
    Write-Host "DRY RUN MODE: No changes will be made to GitHub repository permissions." -ForegroundColor Yellow
}

# Read and process CSV file
Write-Host "Reading CSV file: $CsvFilePath"
try {
    $csvData = Import-Csv -Path $CsvFilePath
    Write-Host "Found $($csvData.Count) entries in CSV file."
}
catch {
    Write-Error "Error reading CSV file: $($_.Exception.Message)"
    exit 1
}

# Group entries by repository and team, collecting roles for each team
$repoTeamMappings = @{}
foreach ($entry in $csvData) {
    $repoName = $entry.Repo
    $teamName = $entry.Team
    $roleName = $entry.Role

    # Skip entries without team assignment
    if ([string]::IsNullOrWhiteSpace($teamName) -or [string]::IsNullOrWhiteSpace($repoName)) {
        continue
    }

    $key = "$repoName|$teamName"
    if (-not $repoTeamMappings.ContainsKey($key)) {
        $repoTeamMappings[$key] = @{
            Repository = $repoName
            Team = $teamName
            Roles = @()
        }
    }

    # Add role to the team's role collection if it's not empty
    if (-not [string]::IsNullOrWhiteSpace($roleName)) {
        $repoTeamMappings[$key].Roles += $roleName
    }
}

Write-Host "Found $($repoTeamMappings.Count) unique repository-team mappings to process."

# Load custom repository roles
Write-Host "Loading custom repository roles for organization '$GITHUB_ORG'..."
$customRoles = Get-CustomRepositoryRoles -OrgName $GITHUB_ORG
if ($customRoles.Count -gt 0) {
    Write-Host "Found $($customRoles.Count) custom repository role(s): $($customRoles.name -join ', ')" -ForegroundColor Blue
}
else {
    Write-Host "No custom repository roles found. Using standard roles only." -ForegroundColor Gray
}

# Track results
$successCount = 0
$failureCount = 0

# Process each unique repository-team mapping
foreach ($mapping in $repoTeamMappings.Values) {
    $repoName = $mapping.Repository
    $teamName = $mapping.Team
    $teamSlug = Convert-TeamNameToSlug -TeamName $teamName

    # Determine permission level based on team member roles
    $teamPermission = if ($mapping.Roles.Count -gt 0) {
        Get-TeamPermissionLevel -Roles $mapping.Roles -CustomRoles $customRoles
    } else {
        "pull"  # Default to read access if no roles specified
    }

    $rolesText = if ($mapping.Roles.Count -gt 0) { "(Roles: $($mapping.Roles -join ', '))" } else { "(No roles specified)" }
    Write-Host "`nProcessing: Repository '$repoName' -> Team '$teamName' (slug: $teamSlug) with '$teamPermission' permission $rolesText"

    if ($DryRun) {
        Write-Host "DRY RUN: Would grant team '$teamName' '$teamPermission' access to repository '$repoName'" -ForegroundColor Yellow
        continue
    }

    # Validate repository exists
    if (-not (Test-GitHubRepository -OrgName $GITHUB_ORG -RepoName $repoName)) {
        Write-Warning "Repository '$repoName' not found in organization '$GITHUB_ORG'. Skipping..."
        $failureCount++
        continue
    }

    # Validate team exists
    $team = Get-GitHubTeam -OrgName $GITHUB_ORG -TeamSlug $teamSlug
    if (-not $team) {
        Write-Warning "Team '$teamName' (slug: $teamSlug) not found in organization '$GITHUB_ORG'. Please create the team first using provision_users.ps1."
        $failureCount++
        continue
    }

    # Grant team access to repository
    Write-Host "Granting team '$teamName' '$teamPermission' access to repository '$repoName'..."
    if (Grant-TeamRepositoryAccess -OrgName $GITHUB_ORG -TeamSlug $teamSlug -RepoName $repoName -Permission $teamPermission -CustomRoles $customRoles) {
        Write-Host "Successfully granted team '$teamName' '$teamPermission' access to repository '$repoName'" -ForegroundColor Green
        $successCount++
    }
    else {
        $failureCount++
    }
}

# Summary
Write-Host "`n--- Team-to-Repository Mapping Summary ---" -ForegroundColor Cyan
Write-Host "Successful repository access grants: $successCount" -ForegroundColor Green
Write-Host "Failed repository access grants: $failureCount" -ForegroundColor Red
Write-Host "Permissions determined dynamically based on team member roles" -ForegroundColor Blue

if ($DryRun) {
    Write-Host "`nThis was a DRY RUN - no actual changes were made." -ForegroundColor Yellow
}
else {
    Write-Host "`nTeam-to-repository mapping complete!" -ForegroundColor Green
}