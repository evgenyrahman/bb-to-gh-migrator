<#
.SYNOPSIS
    Provisions users to GitHub teams or repositories based on a CSV file mapping.
.DESCRIPTION
    This PowerShell script automates the process of adding users to GitHub teams or directly to repositories
    within an organization. It reads a CSV file containing user mappings and performs the following operations:
    1. Validates that the specified GitHub organization, teams, and repositories exist.
    2. Validates that the specified GitHub usernames exist.
    3. If Team is specified: Adds users to their designated teams.
    4. If Team is empty but Role is specified: Grants users direct access to repositories with the specified role.
    5. Reports on successful and failed user additions.
.PARAMETER CsvFilePath
    The path to the CSV file containing user provisioning data.
    Expected columns: Repo, User, Role, Team
    Note: User column should contain GitHub usernames by default, or EMU email addresses when InputType is set to 'EMUEmail'.
.PARAMETER DryRun
    When specified, performs a dry run without making actual changes to GitHub teams.
    Useful for validating the CSV data and checking what changes would be made.
.PARAMETER InputType
    Specifies how to interpret the User column in the CSV file.
    'Username' (default): Treats the User column as GitHub usernames.
    'EMUEmail': Treats the User column as GitHub Enterprise Managed Users (EMU) email addresses.
    When 'EMUEmail' is used, the script requires a user_mapping.csv file in the users directory
    with columns 'username' and 'useremail' for email-to-username mapping.
.EXAMPLE
    ./provision_users.ps1 -CsvFilePath './users/User_Provisioning.csv'

    This command reads the user provisioning data from the specified CSV file and adds users
    to their designated teams in the GitHub organization specified by the $env:GITHUB_ORG
    environment variable.
.EXAMPLE
    ./provision_users.ps1 -CsvFilePath './users/User_Provisioning.csv' -DryRun

    This command performs a dry run, showing what changes would be made without actually
    modifying the GitHub teams.
.EXAMPLE
    ./provision_users.ps1 -CsvFilePath './users/User_Provisioning.csv' -InputType EMUEmail

    This command treats the User column as EMU email addresses instead of usernames.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvFilePath,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Username', 'EMUEmail')]
    [string]$InputType = 'Username'
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
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        Write-Host "Organization '$OrgName' found." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Organization '$OrgName' not found or not accessible: $($_.Exception.Message)"
        return $false
    }
}

function Test-GitHubUser {
    param([string]$Username)

    $headers = Get-GitHubHeaders
    $url = "$GITHUB_API_URL/users/$Username"

    try {
        $user = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        return $user
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            return $null
        }
        Write-Error "Error checking user '$Username': $($_.Exception.Message)"
        return $null
    }
}

function Test-GitHubUserByEmail {
    param([string]$Email)

    $headers = Get-GitHubHeaders
    # Use the search API to find users by email
    $url = "$GITHUB_API_URL/search/users?q=$Email+in:email"

    try {
        $result = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        if ($result.total_count -gt 0) {
            return $result.items[0]  # Return the first matching user
        }
        return $null
    }
    catch {
        Write-Error "Error searching for user by email '$Email': $($_.Exception.Message)"
        return $null
    }
}

function Test-UserInOrganization {
    param(
        [string]$OrgName,
        [string]$Username
    )

    $headers = Get-GitHubHeaders
    $url = "$GITHUB_API_URL/orgs/$OrgName/members/$Username"

    try {
        Invoke-RestMethod -Uri $url -Method Get -Headers $headers | Out-Null
        return $true
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            return $false
        }
        Write-Error "Error checking organization membership for user '$Username': $($_.Exception.Message)"
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
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        return $response
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            return $null
        }
        Write-Error "Error retrieving team '$TeamSlug': $($_.Exception.Message)"
        return $null
    }
}

function New-GitHubTeam {
    param(
        [string]$OrgName,
        [string]$TeamName,
        [string]$Description = "Team created by provisioning script"
    )

    Write-Host "Creating team '$TeamName' in organization '$OrgName'..."
    $headers = Get-GitHubHeaders
    $body = @{
        name        = $TeamName
        description = $Description
        privacy     = "closed"
    } | ConvertTo-Json

    $url = "$GITHUB_API_URL/orgs/$OrgName/teams"

    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body -ContentType "application/json"
        Write-Host "Team '$TeamName' created successfully." -ForegroundColor Green
        return $response
    }
    catch {
        Write-Error "Error creating team '$TeamName': $($_.Exception.Message)"
        return $null
    }
}

function Add-UserToTeam {
    param(
        [string]$OrgName,
        [string]$TeamSlug,
        [string]$Username
    )

    $headers = Get-GitHubHeaders
    $url = "$GITHUB_API_URL/orgs/$OrgName/teams/$TeamSlug/memberships/$Username"

    $body = @{
        role = "member"
    } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri $url -Method Put -Headers $headers -Body $body -ContentType "application/json"
        return $true
    }
    catch {
        Write-Error "Error adding user '$Username' to team '$TeamSlug': $($_.Exception.Message)"
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

function Get-UserMappingData {
    param([string]$CsvFilePath)

    # Construct path to user_mapping.csv in the users directory
    $usersDir = Split-Path -Path $CsvFilePath -Parent
    $mappingFile = Join-Path -Path $usersDir -ChildPath "user_mapping.csv"

    if (-not (Test-Path $mappingFile)) {
        throw "User mapping file not found: $mappingFile. This file is required when InputType is 'EMUEmail'."
    }

    try {
        $mappingData = Import-Csv -Path $mappingFile

        # Validate required columns exist
        $firstRow = $mappingData | Select-Object -First 1
        if (-not $firstRow.PSObject.Properties.Name -contains 'username') {
            throw "User mapping file '$mappingFile' is missing required 'username' column."
        }
        if (-not $firstRow.PSObject.Properties.Name -contains 'useremail') {
            throw "User mapping file '$mappingFile' is missing required 'useremail' column."
        }

        Write-Host "Loaded user mapping file: $mappingFile ($($mappingData.Count) entries)"
        return $mappingData
    }
    catch {
        throw "Error reading user mapping file '$mappingFile': $($_.Exception.Message)"
    }
}

function Get-UsernameFromMapping {
    param(
        [string]$Email,
        [array]$MappingData
    )

    # Case-insensitive email lookup
    $matchingEntry = $MappingData | Where-Object { $_.useremail -ieq $Email }

    if ($matchingEntry) {
        return $matchingEntry.username
    }
    else {
        return $null
    }
}

function Get-GitHubUser {
    param(
        [string]$UserInput,
        [string]$InputType,
        [array]$UserMappingData = $null
    )

    if ($InputType -eq 'EMUEmail') {
        # First, try to resolve email to username using mapping file
        if ($UserMappingData) {
            $mappedUsername = Get-UsernameFromMapping -Email $UserInput -MappingData $UserMappingData
            if ($mappedUsername) {
                Write-Verbose "Mapped email '$UserInput' to username '$mappedUsername' via user_mapping.csv"
                $user = Test-GitHubUser -Username $mappedUsername
                if (-not $user) {
                    Write-Warning "Mapped username '$mappedUsername' (from email '$UserInput') not found on GitHub. Skipping..."
                }
                return $user
            }
            else {
                Write-Warning "Email '$UserInput' not found in user_mapping.csv. Skipping..."
                return $null
            }
        }
        else {
            Write-Verbose "Looking up user by email: $UserInput"
            $user = Test-GitHubUserByEmail -Email $UserInput
            if (-not $user) {
                Write-Warning "User with email '$UserInput' not found on GitHub. Skipping..."
            }
            return $user
        }
    }
    else {
        Write-Verbose "Looking up user by username: $UserInput"
        $user = Test-GitHubUser -Username $UserInput
        if (-not $user) {
            Write-Warning "Username '$UserInput' not found on GitHub. Skipping..."
        }
        return $user
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

function Grant-UserRepositoryAccess {
    param(
        [string]$OrgName,
        [string]$RepoName,
        [string]$Username,
        [string]$Permission,
        [array]$CustomRoles = @()
    )

    $headers = Get-GitHubHeaders
    $url = "$GITHUB_API_URL/repos/$OrgName/$RepoName/collaborators/$Username"

    # Check if this is a custom role
    $customRole = $CustomRoles | Where-Object { $_.name -ieq $Permission }
    if ($customRole) {
        # For custom roles, we need to use the role_name parameter instead of permission
        $body = @{
            role_name = $customRole.name
        } | ConvertTo-Json
        Write-Verbose "Using custom role '$($customRole.name)' for user '$Username'"
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
        Write-Error "Error granting user '$Username' '$Permission' access to repository '$RepoName': $($_.Exception.Message)"
        return $false
    }
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
    Write-Host "DRY RUN MODE: No changes will be made to GitHub teams." -ForegroundColor Yellow
}

# Load user mapping data if using EMUEmail input type
$userMappingData = $null
if ($InputType -eq 'EMUEmail') {
    try {
        $userMappingData = Get-UserMappingData -CsvFilePath $CsvFilePath
    }
    catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}

# Load custom repository roles
Write-Host "Loading custom repository roles for organization '$GITHUB_ORG'..."
$customRoles = Get-CustomRepositoryRoles -OrgName $GITHUB_ORG
if ($customRoles.Count -gt 0) {
    Write-Host "Found $($customRoles.Count) custom repository role(s): $($customRoles.name -join ', ')" -ForegroundColor Blue
}
else {
    Write-Host "No custom repository roles found. Using standard roles only." -ForegroundColor Gray
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

# Track results
$successCount = 0
$failureCount = 0
$teamsProcessed = @{}
$directAccessCount = 0

# Process each entry in CSV
foreach ($entry in $csvData) {
    $userInput = $entry.User
    $teamName = $entry.Team
    $roleName = $entry.Role
    $repoName = $entry.Repo

    # Determine processing type: team assignment or direct repository access
    $hasTeam = -not [string]::IsNullOrWhiteSpace($teamName)
    $hasRole = -not [string]::IsNullOrWhiteSpace($roleName)
    $hasRepo = -not [string]::IsNullOrWhiteSpace($repoName)

    # Skip entries that have neither team nor role assignment
    if (-not $hasTeam -and -not $hasRole) {
        Write-Warning "Skipping user input '$userInput' - no team or role specified"
        continue
    }

    # Validate user exists and get user info
    Write-Host "Validating user '$userInput'..."
    $user = Get-GitHubUser -UserInput $userInput -InputType $InputType -UserMappingData $userMappingData
    if (-not $user) {
        $failureCount++
        continue
    }

    # Use the actual GitHub username for API calls (from the user object)
    $username = $user.login
    Write-Verbose "Resolved to GitHub username: $username"

    # Show input resolution if using EMU emails
    if ($InputType -eq 'EMUEmail' -and $userInput -ne $username) {
        Write-Verbose "Resolved EMU email '$userInput' to username '$username'"
    }

    # Check if user is a member of the organization (optional - they might be added as outside collaborator)
    $isOrgMember = Test-UserInOrganization -OrgName $GITHUB_ORG -Username $username
    if (-not $isOrgMember -and $hasTeam) {
        Write-Warning "User '$username' (from input '$userInput') is not a member of organization '$GITHUB_ORG'. They need to be invited to the organization before being added to teams."
        $failureCount++
        continue
    }

    if ($hasTeam) {
        # Team assignment scenario
        Write-Host "`nProcessing user: $username -> Team: $teamName"

        if ($DryRun) {
            Write-Host "DRY RUN: Would add user '$username' to team '$teamName'" -ForegroundColor Yellow
            continue
        }

        # Convert team name to slug format
        $teamSlug = Convert-TeamNameToSlug -TeamName $teamName

        # Check if team exists, create if it doesn't
        $team = Get-GitHubTeam -OrgName $GITHUB_ORG -TeamSlug $teamSlug
        if (-not $team) {
            Write-Host "Team '$teamName' (slug: $teamSlug) does not exist. Creating..."
            $team = New-GitHubTeam -OrgName $GITHUB_ORG -TeamName $teamName
            if (-not $team) {
                Write-Error "Failed to create team '$teamName'"
                $failureCount++
                continue
            }
            $teamSlug = $team.slug
        }

        # Add user to team
        Write-Host "Adding user '$username' to team '$teamName'..."
        if (Add-UserToTeam -OrgName $GITHUB_ORG -TeamSlug $teamSlug -Username $username) {
            Write-Host "Successfully added user '$username' to team '$teamName'" -ForegroundColor Green
            $successCount++
        }
        else {
            $failureCount++
        }

        $teamsProcessed[$teamName] = $true
    }
    elseif ($hasRole -and $hasRepo) {
        # Direct repository access scenario
        $permission = Convert-RoleToPermission -Role $roleName -CustomRoles $customRoles
        Write-Host "`nProcessing user: $username -> Repository: $repoName (Role: $roleName -> Permission: $permission)"

        if ($DryRun) {
            Write-Host "DRY RUN: Would grant user '$username' '$permission' access to repository '$repoName'" -ForegroundColor Yellow
            continue
        }

        # Validate repository exists
        if (-not (Test-GitHubRepository -OrgName $GITHUB_ORG -RepoName $repoName)) {
            Write-Warning "Repository '$repoName' not found in organization '$GITHUB_ORG'. Skipping..."
            $failureCount++
            continue
        }

        # Grant user direct access to repository
        Write-Host "Granting user '$username' '$permission' access to repository '$repoName'..."
        if (Grant-UserRepositoryAccess -OrgName $GITHUB_ORG -RepoName $repoName -Username $username -Permission $permission -CustomRoles $customRoles) {
            Write-Host "Successfully granted user '$username' '$permission' access to repository '$repoName'" -ForegroundColor Green
            $successCount++
            $directAccessCount++
        }
        else {
            $failureCount++
        }
    }
    else {
        Write-Warning "Skipping user '$username' - has role '$roleName' but no repository specified"
        continue
    }
}

# Summary
Write-Host "`n--- Provisioning Summary ---" -ForegroundColor Cyan
Write-Host "Users successfully processed: $successCount" -ForegroundColor Green
Write-Host "Failed user operations: $failureCount" -ForegroundColor Red
Write-Host "Teams processed: $($teamsProcessed.Count)" -ForegroundColor Blue
Write-Host "Direct repository access grants: $directAccessCount" -ForegroundColor Blue

if ($DryRun) {
    Write-Host "`nThis was a DRY RUN - no actual changes were made." -ForegroundColor Yellow
}
else {
    Write-Host "`nUser provisioning complete!" -ForegroundColor Green
}
