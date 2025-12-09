param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,

    [Parameter(Mandatory=$false)]
    [string]$SnapshotName = "initial-baseline",

    [Parameter(Mandatory=$false)]
    [string]$Description = "Initial baseline snapshot for testing and rollback"
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

Write-Host "Checking for existing initial snapshot on '$VMName'..." -ForegroundColor Cyan

# Get list of snapshots for this VM
$SnapshotList = & $VBoxManage snapshot $VMName list --machinereadable 2>&1

# Check if the initial snapshot already exists
$SnapshotExists = $false
if ($LASTEXITCODE -eq 0) {
    # Parse snapshot output to find our snapshot
    $SnapshotList | ForEach-Object {
        if ($_ -match "SnapshotName.*=.*`"$SnapshotName`"") {
            $SnapshotExists = $true
        }
    }
}

if ($SnapshotExists) {
    Write-Host "Initial snapshot '$SnapshotName' already exists for VM '$VMName'." -ForegroundColor Yellow
    Write-Host "Only one initial snapshot is allowed per VM." -ForegroundColor Yellow
    Write-Host "`nTo recreate the snapshot, you must first delete it:" -ForegroundColor Yellow
    Write-Host "  VBoxManage snapshot $VMName delete `"$SnapshotName`"" -ForegroundColor White
    Write-Host "`nCurrent snapshots:" -ForegroundColor Cyan
    & $VBoxManage snapshot $VMName list
    exit 0
}

Write-Host "No initial snapshot found. Creating snapshot '$SnapshotName'..." -ForegroundColor Cyan

# Check if VM is running - we can snapshot running VMs
$IsRunning = & $VBoxManage list runningvms | Select-String -Pattern "`"$VMName`""

if ($IsRunning) {
    Write-Host "Note: VM is currently running. Creating live snapshot..." -ForegroundColor Yellow
}

# Create the snapshot
& $VBoxManage snapshot $VMName take "$SnapshotName" --description "$Description"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nInitial snapshot '$SnapshotName' created successfully!" -ForegroundColor Green
    Write-Host "`nYou can now:" -ForegroundColor Cyan
    Write-Host "  - Make changes to the VM" -ForegroundColor White
    Write-Host "  - Test your restore script" -ForegroundColor White
    Write-Host "  - Rollback to this state with: vbox-snapshot-rollback $VMName" -ForegroundColor White

    Write-Host "`nSnapshot details:" -ForegroundColor Cyan
    & $VBoxManage snapshot $VMName list
} else {
    Write-Host "Failed to create snapshot!" -ForegroundColor Red
    exit 1
}
