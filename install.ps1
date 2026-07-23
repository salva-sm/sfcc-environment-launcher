# Requires Administrator privileges

$TaskName = "SFCC_Sandbox_Launcher"
$BashPath = "C:\Program Files\Git\bin\bash.exe"
$WorkingDir = (Get-Location).Path
$ScriptPath = "$WorkingDir\start_environment.sh"

# Convert POSIX path for Git Bash (e.g. C:\folder -> /c/folder)
$BashScriptPath = $ScriptPath -replace '^\s*([A-Za-z]):', '/$1' -replace '\\', '/'

Write-Host "[+] Creating Windows Scheduled Task: $TaskName..." -ForegroundColor Cyan

# Define Trigger (At Logon of current user)
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# Define Action (Run Git Bash with the .sh script)
$Action = New-ScheduledTaskAction `
    -Execute $BashPath `
    -Argument "-c `"$BashScriptPath`"" `
    -WorkingDirectory $WorkingDir

# Register Task
Register-ScheduledTask `
    -TaskName $TaskName `
    -Trigger $Trigger `
    -Action $Action `
    -Description "Automated bootstrapper for SFCC On-Demand Sandbox and local workspace." `
    -Force | Out-Null

Write-Host "[OK] Task '$TaskName' installed successfully!" -ForegroundColor Green
Write-Host "[-] Working Directory: $WorkingDir" -ForegroundColor Gray