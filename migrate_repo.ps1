<#
.SYNOPSIS
    Migrates a Git repository from Bitbucket Cloud to GitHub Enterprise Cloud.
.DESCRIPTION
    This PowerShell script automates the migration of a single repository. It performs the following steps:
    1. Creates a new private repository in a specified GitHub organization.
    2. Performs a mirror clone of the Bitbucket repository to a local temporary directory.
    3. Pushes the mirrored repository, including all branches and tags, to the new GitHub repository.
    4. Cleans up the temporary local clone.
.PARAMETER BitbucketWorkspace
    The Bitbucket workspace or project key where the source repository resides.
.PARAMETER BitbucketRepo
    The repository slug of the Bitbucket repository (e.g., 'my-awesome-project').
.PARAMETER GitHubRepo
    The name for the new repository to be created on GitHub.
.EXAMPLE
    ./migrate_repo.ps1 -BitbucketWorkspace 'my-workspace' -BitbucketRepo 'my-project' -GitHubRepo 'new-gh-project'

    This command migrates the 'my-project' repository from the 'my-workspace' Bitbucket workspace
    to a new GitHub repository named 'new-gh-project' in the organization specified by the
    $env:GITHUB_ORG environment variable.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BitbucketWorkspace,

    [Parameter(Mandatory = $true)]
    [string]$BitbucketRepo,

    [Parameter(Mandatory = $true)]
    [string]$GitHubRepo
)

# --- Configuration & Prequisites ---

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
$BITBUCKET_USERNAME = $env:BITBUCKET_USERNAME
$BITBUCKET_APP_PASSWORD = $env:BITBUCKET_APP_PASSWORD
$GHE_URL = $env:GHE_URL # For GitHub Enterprise

# Construct GitHub API and base URLs
$GITHUB_API_URL = if ($GHE_URL) { "$GHE_URL/api/v3" } else { "https://api.github.com" }
$GITHUB_BASE_URL = if ($GHE_URL) { $GHE_URL } else { "https://github.com" }


# --- Function Definitions ---

function Create-GitHubRepo {
    param(
        [string]$RepoName
    )
    Write-Host "Creating GitHub repository '$RepoName' in organization '$GITHUB_ORG'..."
    $headers = @{
        "Authorization" = "token $GITHUB_TOKEN"
        "Accept"        = "application/vnd.github.v3+json"
    }
    $body = @{
        name        = $RepoName
        private     = $true
        description = "Migrated from Bitbucket"
    } | ConvertTo-Json

    $url = "$GITHUB_API_URL/orgs/$GITHUB_ORG/repos"

    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body -ContentType "application/json"
        return $response.html_url
    }
    catch {
        # Check if repo already exists (HTTP 422)
        if ($_.Exception.Response.StatusCode -eq 422) {
            Write-Warning "GitHub repository '$RepoName' already exists."
            return "$GITHUB_BASE_URL/$GITHUB_ORG/$RepoName"
        }
        else {
            Write-Error "Error creating GitHub repository: $($_.Exception.Message)"
            $_.Exception.Response.GetResponseStream() | %{ [System.IO.StreamReader]::new($_).ReadToEnd() } | Write-Error
            return $null
        }
    }
}

function Invoke-Git {
    param(
        [string]$Arguments,
        [string]$WorkingDirectory
    )
    $command = "git $Arguments"
    Write-Verbose "Running Git command: $command in $WorkingDirectory"
    $process = Start-Process git -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory -Wait -NoNewWindow -PassThru -RedirectStandardError "stderr.log" -RedirectStandardOutput "stdout.log"

    if ($process.ExitCode -ne 0) {
        Write-Error "Git command failed with exit code $($process.ExitCode)."
        Get-Content "stderr.log" | Write-Error
        Get-Content "stdout.log" | Write-Output
        return $false
    }
    Get-Content "stdout.log" | Write-Output
    return $true
}


# --- Main Script Logic ---

# Validate environment variables
if (-not ($GITHUB_TOKEN -and $GITHUB_ORG -and $BITBUCKET_USERNAME -and $BITBUCKET_APP_PASSWORD)) {
    Write-Error "Ensure all required environment variables are set in your session or in a .env file."
    Write-Error "Required: GITHUB_TOKEN, GITHUB_ORG, BITBUCKET_USERNAME, BITBUCKET_APP_PASSWORD"
    exit 1
}

# 1. Create GitHub Repository
$githubRepoUrl = Create-GitHubRepo -RepoName $GitHubRepo
if (-not $githubRepoUrl) {
    exit 1
}
Write-Host "Successfully prepared GitHub repository: $githubRepoUrl"


# 2. Clone from Bitbucket (Mirror)
$bitbucketRepoUrl = "https://$($BITBUCKET_USERNAME):$($BITBUCKET_APP_PASSWORD)@bitbucket.org/$BitbucketWorkspace/$BitbucketRepo.git"
$localRepoPath = Join-Path $PSScriptRoot "$($BitbucketRepo).git"

# Clean up previous clone if it exists
if (Test-Path $localRepoPath) {
    Write-Warning "Removing existing local clone at '$localRepoPath'."
    Remove-Item -Recurse -Force $localRepoPath
}

Write-Host "Cloning '$BitbucketRepo' from Bitbucket..."
if (-not (Invoke-Git -Arguments "clone --mirror `"$bitbucketRepoUrl`" `"$localRepoPath`"" -WorkingDirectory $PSScriptRoot)) {
    Write-Error "Error cloning from Bitbucket."
    exit 1
}
Write-Host "Clone successful."


# 3. Push to GitHub (Mirror)
Write-Host "Pushing to GitHub repository '$GitHubRepo'..."
$githubPushUrl = $githubRepoUrl.Replace("https://", "https://$($GITHUB_TOKEN)@")

if (-not (Invoke-Git -Arguments "push --mirror `"$githubPushUrl`"" -WorkingDirectory $localRepoPath)) {
    Write-Error "Error pushing to GitHub."
    exit 1
}
Write-Host "Push to GitHub successful."


# 4. Cleanup
Write-Host "Cleaning up local repository clone at '$localRepoPath'..."
Remove-Item -Recurse -Force $localRepoPath
Remove-Item "stderr.log", "stdout.log" -ErrorAction SilentlyContinue
Write-Host "Cleanup successful."

Write-Host "`nMigration complete!" -ForegroundColor Green
Write-Host "Repository '$BitbucketWorkspace/$BitbucketRepo' has been migrated to '$githubRepoUrl'"
