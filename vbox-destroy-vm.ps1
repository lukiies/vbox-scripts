param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Load configuration from .vbox-setup file
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir ".vbox-setup"

if (Test-Path $ConfigFile) {
    # Parse configuration file
    $Config = @{}
    Get-Content $ConfigFile | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '=' } | ForEach-Object {
        $key, $value = $_ -split '=', 2
        $Config[$key.Trim()] = $ExecutionContext.InvokeCommand.ExpandString($value.Trim())
    }
    $VBoxManage = $Config['VBOX_MANAGE_PATH']
}

if (-not $VBoxManage) { $VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" }

if (-not (Test-Path $VBoxManage)) {
    Write-Host "VBoxManage not found at: $VBoxManage" -ForegroundColor Red
    Write-Host "Please install VirtualBox or update VBOX_MANAGE_PATH in .vbox-setup" -ForegroundColor Red
    exit 1
}

# Check if VM exists
$vmInfo = & $VBoxManage showvminfo $VMName 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "VM '$VMName' not found." -ForegroundColor Red
    exit 1
}

# Confirm deletion unless -Force is used
if (!$Force) {
    $confirmation = Read-Host "Are you sure you want to destroy VM '$VMName'? This will delete all data. (yes/no)"
    if ($confirmation -ne "yes") {
        Write-Host "Destruction cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "Stopping VM '$VMName' if running..." -ForegroundColor Cyan
& $VBoxManage controlvm $VMName poweroff 2>&1 | Out-Null

# Wait a moment for the VM to fully stop
Start-Sleep -Seconds 2

Write-Host "Destroying VM '$VMName' and deleting all files..." -ForegroundColor Cyan
& $VBoxManage unregistervm $VMName --delete

if ($LASTEXITCODE -eq 0) {
    Write-Host "VM '$VMName' has been completely destroyed." -ForegroundColor Green
} else {
    Write-Host "Failed to destroy VM with error code: $LASTEXITCODE" -ForegroundColor Red
    exit 1
}
