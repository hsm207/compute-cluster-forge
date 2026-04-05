# --- Parameter Binding ---
param (
    [Parameter(Mandatory=$true)]
    [string]$ProjectId,

    [Parameter(Mandatory=$true)]
    [string]$Zone,

    [Parameter(Mandatory=$true)]
    [string]$GcpUser,

    [Parameter(Mandatory=$true)]
    [string]$InstancePrefix
)

$ErrorActionPreference = "Stop"

# --- Global Configuration ---
$sshDir = "$env:USERPROFILE\.ssh"
$configFile = "$sshDir\config"
$hostMatcher = "Host $InstancePrefix-*"

# --- Utilities ---

function Initialize-SshDirectory() {
    if (-not (Test-Path $sshDir)) {
        Write-Host "📁 Creating .ssh directory..."
        New-Item -ItemType Directory -Path $sshDir | Out-Null
    }
}

function Get-IdentityFilePath() {
    # Convert backslashes to forward slashes for OpenSSH IdentityFile compatibility
    $identityFilePath = "$sshDir\google_compute_engine" -replace '\\', '/'
    return $identityFilePath
}

function Get-CurrentConfigContent() {
    if (Test-Path $configFile) {
        return Get-Content -Path $configFile
    }
    return @()
}

function Remove-OldHostBlock() {
    $fileContent = Get-CurrentConfigContent
    if ($fileContent.Count -eq 0) {
        return
    }

    $newContent = @()
    $skipMode = $false
    $hostPattern = "Host $InstancePrefix-*"

    foreach ($line in $fileContent) {
        if ($line -eq $hostPattern) {
            $skipMode = $true
            Write-Host "🔄 Found existing entry. Removing old config block..."
        } elseif ($skipMode -and ($line -match "^Host " -or ($line -notmatch "^\s"))) {
            # Exit skip mode when we hit the next Host or line starting with non-whitespace
            $skipMode = $false
        }

        if (-not $skipMode) {
            $newContent += $line
        }
    }

    if ($newContent.Count -gt 0) {
        Set-Content -Path $configFile -Value $newContent
    }
}

function Add-NewHostBlock() {
    param(
        [string]$ProjectId,
        [string]$Zone,
        [string]$GcpUser,
        [string]$IdentityFile
    )

    $configBlock = @"

Host $InstancePrefix-*
    ProxyCommand gcloud.cmd compute start-iap-tunnel %h %p --listen-on-stdin --project=$ProjectId --zone=$Zone
    User $GcpUser
    IdentityFile $IdentityFile
    RequestTTY force
"@

    Add-Content -Path $configFile -Value $configBlock
}

# --- Main Orchestration Flow ---

Write-Host "🚀 PowerShell Bridge Active. Starting injection for project [$ProjectId] in zone [$Zone]..."
Write-Host "📂 Target Directory: $sshDir"

Initialize-SshDirectory
$identityFile = Get-IdentityFilePath
Write-Host "🔑 Identity File: $identityFile"

Remove-OldHostBlock

Write-Host "✍️  Injecting fresh config block..."
Add-NewHostBlock -ProjectId $ProjectId -Zone $Zone -GcpUser $GcpUser -IdentityFile $identityFile

Write-Host "✨ Config updated! VS Code Remote-SSH is natively configured with latest deployment."
