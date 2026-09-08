# Requires Administrator privileges

$BashPath = "C:\Program Files\Git\bin\bash.exe"
$WorkingDir = (Get-Location).Path

$StartScript = "$WorkingDir\start_environment.sh"
$StopScript  = "$WorkingDir\stop_environment.sh"

$BashStartPath = $StartScript -replace '^\s*([A-Za-z]):', '/$1' -replace '\\', '/'
$BashStopPath  = $StopScript  -replace '^\s*([A-Za-z]):', '/$1' -replace '\\', '/'

$EnvFile = "$WorkingDir\.env"

function Get-EnvValue([string]$Key) {
    if (-not (Test-Path $EnvFile)) { return "" }
    $match = Select-String -Path $EnvFile -Pattern "^\s*$Key\s*=" | Select-Object -First 1
    if (-not $match) { return "" }
    ($match.Line -replace "^\s*$Key\s*=\s*", "").Trim().Trim('"').Trim("'")
}

function Set-EnvValue([string]$Key, [string]$Value) {
    $found = $false
    $lines = @(Get-Content -LiteralPath $EnvFile | ForEach-Object {
        if ($_ -match "^\s*$Key\s*=") { $found = $true; "$Key=$Value" } else { $_ }
    })
    if (-not $found) { $lines += "$Key=$Value" }
    Set-Content -LiteralPath $EnvFile -Value $lines
}

# ------------------------------------------------------------------------------
# 0. Editor Configuration (only asked for when the dotfiles don't answer it)
# ------------------------------------------------------------------------------
if (-not (Test-Path $EnvFile)) {
    Copy-Item "$WorkingDir\.env.example" $EnvFile
    Write-Host "[+] Created .env from .env.example - remember to review it." -ForegroundColor Yellow
}

$DotfilesDir = Get-EnvValue "DOTFILES_DIR"
if ([string]::IsNullOrWhiteSpace($DotfilesDir)) { $DotfilesDir = "$HOME\Github\dotfiles" }
$DotfilesEnv = Join-Path $DotfilesDir "git-bash\env.local"

if (Test-Path $DotfilesEnv) {
    Write-Host "[-] dotfiles detected: editor taken from DOTFILES_EDITOR in $DotfilesEnv" -ForegroundColor Gray
} elseif (-not [string]::IsNullOrWhiteSpace((Get-EnvValue "LAUNCH_EDITOR"))) {
    Write-Host "[-] Editor already set in .env: $(Get-EnvValue 'LAUNCH_EDITOR')" -ForegroundColor Gray
} else {
    $Editor = "code"
    if ([Environment]::UserInteractive) {
        Write-Host "[?] No dotfiles found. Which editor should open the project?" -ForegroundColor Cyan
        Write-Host "    1) Visual Studio Code (default)"
        Write-Host "    2) Zed"
        if ((Read-Host "    Choice [1/2]") -match '^\s*(2|zed)\s*$') { $Editor = "zed" }
    }
    Set-EnvValue "LAUNCH_EDITOR" $Editor
    Write-Host "[OK] LAUNCH_EDITOR=$Editor written to .env" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 1. Startup Task (On Logon)
# ------------------------------------------------------------------------------
$StartTaskName = "SFCC_Sandbox_Launcher"
Write-Host "[+] Installing task: $StartTaskName..." -ForegroundColor Cyan

$StartTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$StartAction  = New-ScheduledTaskAction `
    -Execute $BashPath `
    -Argument "-c `"$BashStartPath`"" `
    -WorkingDirectory $WorkingDir

Register-ScheduledTask `
    -TaskName $StartTaskName `
    -Trigger $StartTrigger `
    -Action $StartAction `
    -Description "Automated bootstrapper for SFCC On-Demand Sandbox and workspace." `
    -Force | Out-Null

Write-Host "[OK] Task '$StartTaskName' installed successfully." -ForegroundColor Green

# ------------------------------------------------------------------------------
# 2. Shutdown Task (On Event 1074)
# ------------------------------------------------------------------------------
$StopTaskName = "SFCC_Sandbox_Stopper"
Write-Host "[+] Installing task: $StopTaskName..." -ForegroundColor Cyan

$CimClass    = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
$StopTrigger = New-CimInstance -CimClass $CimClass -ClientOnly
$StopTrigger.Subscription = @"
<QueryList>
  <Query Id="0" Path="System">
    <Select Path="System">*[System[EventID=1074]]</Select>
  </Query>
</QueryList>
"@
$StopTrigger.Enabled = $true

$StopAction = New-ScheduledTaskAction `
    -Execute $BashPath `
    -Argument "-c `"$BashStopPath`"" `
    -WorkingDirectory $WorkingDir

Register-ScheduledTask `
    -TaskName $StopTaskName `
    -Trigger $StopTrigger `
    -Action $StopAction `
    -User "NT AUTHORITY\SYSTEM" `
    -Description "Automated shutdown trigger for SFCC On-Demand Sandbox." `
    -Force | Out-Null

Write-Host "[OK] Task '$StopTaskName' installed successfully." -ForegroundColor Green
Write-Host "[-] Working Directory: $WorkingDir" -ForegroundColor Gray