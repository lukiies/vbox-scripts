param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,

    [Parameter(Mandatory=$true)]
    [string]$NewHostname,

    [Parameter(Mandatory=$true)]
    [string]$Username,

    [Parameter(Mandatory=$true)]
    [string]$Password
)

# Set VBoxManage path
$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

if (-not (Test-Path $VBoxManage)) {
    Write-Host "VBoxManage not found at: $VBoxManage" -ForegroundColor Red
    Write-Host "Please install VirtualBox or update the path in this script." -ForegroundColor Red
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
    Write-Host "VM '$VMName' is not running. Please start it first." -ForegroundColor Red
    exit 1
}

Write-Host "Setting hostname to '$NewHostname' on VM '$VMName'..." -ForegroundColor Cyan

# Change hostname using guestcontrol
$Commands = @(
    "hostnamectl set-hostname $NewHostname",
    "sed -i 's/^127\.0\.1\.1.*/127.0.1.1 $NewHostname/' /etc/hosts"
)

foreach ($cmd in $Commands) {
    Write-Host "Executing: $cmd" -ForegroundColor Yellow
    & $VBoxManage guestcontrol $VMName run --exe "/bin/bash" --username $Username --password $Password --wait-stdout -- bash -c $cmd

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to execute command: $cmd" -ForegroundColor Red
        Write-Host "Error code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host "`nNote: This requires VirtualBox Guest Additions to be installed in the VM." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "`nHostname successfully changed to '$NewHostname'!" -ForegroundColor Green
Write-Host "You may need to restart the VM for all changes to take effect." -ForegroundColor Yellow
