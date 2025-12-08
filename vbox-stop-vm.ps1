param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Set VBoxManage path
$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

if (-not (Test-Path $VBoxManage)) {
    Write-Host "VBoxManage not found at: $VBoxManage" -ForegroundColor Red
    Write-Host "Please install VirtualBox or update the path in this script." -ForegroundColor Red
    exit 1
}

# Check if VM exists
$VMList = & $VBoxManage list vms
$VMExists = $false
foreach ($line in $VMList) {
    if ($line -match "`"$VMName`"") {
        $VMExists = $true
        break
    }
}

if (-not $VMExists) {
    Write-Host "VM '$VMName' not found." -ForegroundColor Red
    Write-Host "`nAvailable VMs:" -ForegroundColor Yellow
    & $VBoxManage list vms
    exit 1
}

# Check if VM is running
$RunningVMs = & $VBoxManage list runningvms
$IsRunning = $false
foreach ($line in $RunningVMs) {
    if ($line -match "`"$VMName`"") {
        $IsRunning = $true
        break
    }
}

if (-not $IsRunning) {
    Write-Host "VM '$VMName' is not running." -ForegroundColor Yellow
    exit 0
}

# Stop the VM
if ($Force) {
    Write-Host "Force stopping VM '$VMName'..." -ForegroundColor Cyan
    & $VBoxManage controlvm $VMName poweroff
} else {
    Write-Host "Gracefully shutting down VM '$VMName'..." -ForegroundColor Cyan
    & $VBoxManage controlvm $VMName acpipowerbutton
    Write-Host "Waiting for graceful shutdown (this may take a minute)..." -ForegroundColor Yellow
}

if ($LASTEXITCODE -eq 0) {
    if ($Force) {
        Write-Host "VM '$VMName' has been powered off." -ForegroundColor Green
    } else {
        Write-Host "Shutdown signal sent to VM '$VMName'." -ForegroundColor Green
        Write-Host "Note: Use -Force parameter to force immediate poweroff." -ForegroundColor Yellow
    }
} else {
    Write-Host "Failed to stop VM '$VMName'" -ForegroundColor Red
    exit 1
}
