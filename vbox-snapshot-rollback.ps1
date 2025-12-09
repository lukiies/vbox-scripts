param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,

    [Parameter(Mandatory=$false)]
    [string]$SnapshotName = "initial-baseline",

    [Parameter(Mandatory=$false)]
    [switch]$NoStart
)

# Load configuration from .vbox-setup file
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir ".vbox-setup"

if (Test-Path $ConfigFile) {
    # Parse configuration file
    $Config = @{}
    Get-Content $ConfigFile | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '=' } | ForEach-Object {
        $key, $value = $_ -split '=', 2
        $value = $value.Trim()
        # Remove surrounding quotes if present
        if ($value -match '^"(.*)"$') { $value = $matches[1] }
        $Config[$key.Trim()] = $ExecutionContext.InvokeCommand.ExpandString($value)
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
$VMInfo = & $VBoxManage showvminfo $VMName --machinereadable 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "VM '$VMName' not found." -ForegroundColor Red
    Write-Host "`nAvailable VMs:" -ForegroundColor Yellow
    & $VBoxManage list vms
    exit 1
}

Write-Host "Checking for snapshot '$SnapshotName' on VM '$VMName'..." -ForegroundColor Cyan

# Get list of snapshots for this VM
$SnapshotList = & $VBoxManage snapshot $VMName list --machinereadable 2>&1

# Check if snapshot exists
$SnapshotExists = $false
if ($LASTEXITCODE -eq 0) {
    # Parse snapshot output to find our snapshot
    $SnapshotList | ForEach-Object {
        if ($_ -match "SnapshotName.*=.*`"$SnapshotName`"") {
            $SnapshotExists = $true
        }
    }
}

if (-not $SnapshotExists) {
    Write-Host "Snapshot '$SnapshotName' not found for VM '$VMName'." -ForegroundColor Red
    Write-Host "`nCreate the initial snapshot first:" -ForegroundColor Yellow
    Write-Host "  vbox-snapshot-set $VMName" -ForegroundColor White

    # Show existing snapshots if any
    $AllSnapshots = & $VBoxManage snapshot $VMName list 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nExisting snapshots:" -ForegroundColor Cyan
        & $VBoxManage snapshot $VMName list
    } else {
        Write-Host "`nNo snapshots found for this VM." -ForegroundColor Yellow
    }
    exit 1
}

Write-Host "Snapshot found. Preparing to rollback..." -ForegroundColor Cyan

# Check if VM is running and stop it if necessary
$IsRunning = & $VBoxManage list runningvms | Select-String -Pattern "`"$VMName`""

if ($IsRunning) {
    Write-Host "VM is currently running. Powering off..." -ForegroundColor Yellow
    & $VBoxManage controlvm $VMName poweroff 2>&1 | Out-Null

    # Wait for VM to fully stop
    Write-Host "Waiting for VM to stop..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
}

# Restore the snapshot
Write-Host "Restoring snapshot '$SnapshotName'..." -ForegroundColor Cyan
& $VBoxManage snapshot $VMName restore "$SnapshotName"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to restore snapshot!" -ForegroundColor Red
    exit 1
}

Write-Host "`nSnapshot restored successfully!" -ForegroundColor Green
Write-Host "All changes since the snapshot was created have been discarded." -ForegroundColor Yellow

# Start the VM unless -NoStart was specified
if (-not $NoStart) {
    Write-Host "`nStarting VM..." -ForegroundColor Cyan
    & $VBoxManage startvm $VMName --type headless

    if ($LASTEXITCODE -eq 0) {
        Write-Host "VM '$VMName' started successfully!" -ForegroundColor Green

        # Get the SSH port forwarding info if available
        $VMInfoAfter = & $VBoxManage showvminfo $VMName --machinereadable
        $SSHPort = ($VMInfoAfter | Select-String 'Forwarding.*?Rule1.*?tcp.*?,(\d+),.*?22').Matches.Groups[1].Value

        if ($SSHPort) {
            Write-Host "`nVM is ready for testing!" -ForegroundColor Cyan
            Write-Host "To SSH into it:" -ForegroundColor Yellow
            Write-Host "  vbox-ssh $VMName" -ForegroundColor White
        }
    } else {
        Write-Host "Failed to start VM. You can start it manually." -ForegroundColor Yellow
    }
} else {
    Write-Host "`nVM is powered off (use -NoStart flag was set)." -ForegroundColor Yellow
    Write-Host "Start it manually with: vbox-start-vm $VMName" -ForegroundColor White
}

Write-Host "`nWorkflow reminder:" -ForegroundColor Cyan
Write-Host "  1. Test your restore script" -ForegroundColor White
Write-Host "  2. When ready for next iteration: vbox-snapshot-rollback $VMName" -ForegroundColor White
Write-Host "  3. Repeat" -ForegroundColor White
