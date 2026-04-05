param (
    [Parameter(Mandatory=$true)]
    [string]$ProjectId,

    [Parameter(Mandatory=$true)]
    [string]$Zone,

    [Parameter(Mandatory=$true)]
    [string]$GcpUser
)

$ErrorActionPreference = "Stop"

Write-Host "🚀 PowerShell Bridge Active. Starting injection for project [$ProjectId] in zone [$Zone]..."

$sshDir = "$env:USERPROFILE\.ssh"
$configFile = "$sshDir\config"

Write-Host "📂 Target Directory: $sshDir"

# Ensure the .ssh directory exists on the Windows side
if (-not (Test-Path $sshDir)) {
    Write-Host "📁 Creating .ssh directory..."
    New-Item -ItemType Directory -Path $sshDir | Out-Null
}

# Convert backslashes to forward slashes for OpenSSH IdentityFile compatibility
$identityFile = "$sshDir\google_compute_engine" -replace '\\', '/'
Write-Host "🔑 Identity File: $identityFile"

# Idempotency check: Don't duplicate the block if it already exists
if ((Test-Path $configFile) -and (Select-String -Path $configFile -Pattern 'Host hpc-node-*' -SimpleMatch -Quiet)) {
    Write-Host "✅ Windows SSH config already contains hpc-node-*. Skipping injection."
} else {
    Write-Host "✍️  Injecting new config block..."
    # Construct the multi-line config block
    $configBlock = @"

Host hpc-node-*
    ProxyCommand gcloud.cmd compute start-iap-tunnel %h %p --listen-on-stdin --project=$ProjectId --zone=$Zone
    User $GcpUser
    IdentityFile $identityFile
    RequestTTY force
"@
    # Append to the Windows config file natively
    Add-Content -Path $configFile -Value $configBlock
    Write-Host "✨ Injection complete! VS Code Remote-SSH is natively configured."
}
