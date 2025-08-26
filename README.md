# Bitbucket to GitHub Migrator

This script migrates a Git repository from Bitbucket Cloud to GitHub Enterprise Cloud.

## Prerequisites

- PowerShell 7+
- Git command-line tool
- A GitHub Personal Access Token with `repo` scope.
- A Bitbucket App Password with `repository` read scope.

## Usage

1.  **Create a `.env` file:**

    Create a `.env` file in the same directory as the script and populate it with your credentials. You can use the `.env.example` file as a template.

    ```
    GITHUB_TOKEN="your_github_personal_access_token"
    GITHUB_ORG="your_target_github_organization"
    BITBUCKET_USERNAME="your_bitbucket_username"
    BITBUCKET_APP_PASSWORD="your_bitbucket_app_password"
    # GHE_URL="https://your-github-enterprise-url" # Optional: for GitHub Enterprise
    ```

2.  **Run the script in a PowerShell terminal:**

    ```powershell
    ./migrate_repo.ps1 -BitbucketWorkspace <bitbucket_workspace> -BitbucketRepo <bitbucket_repo_slug> -GitHubRepo <new_github_repo_name>
    ```

    -   `<bitbucket_workspace>`: The workspace ID where the source repository resides.
    -   `<bitbucket_repo_slug>`: The repository slug from your Bitbucket URL (e.g., `my-awesome-project`).
    -   `<new_github_repo_name>`: The name for the new repository on GitHub.
