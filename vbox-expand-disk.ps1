param(
    [Parameter(Mandatory=$true)]
    [string]$VMName
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
    $LVMVolumeGroup = $Config['LVM_VOLUME_GROUP']
    $LVMLogicalVolume = $Config['LVM_LOGICAL_VOLUME']
}

if (-not $VBoxManage) { $VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" }
if (-not $LVMVolumeGroup) { $LVMVolumeGroup = "ubuntu-vg" }
if (-not $LVMLogicalVolume) { $LVMLogicalVolume = "ubuntu-lv" }

# Get SSH port
$VMInfo = & $VBoxManage showvminfo $VMName --machinereadable 2>&1
$SSHPort = ($VMInfo | Select-String 'Forwarding.*?Rule1.*?tcp.*?,(\d+),.*?22').Matches.Groups[1].Value

if (-not $SSHPort) {
    Write-Host "Could not find SSH port for VM '$VMName'" -ForegroundColor Red
    exit 1
}

Write-Host "Expanding disk on VM '$VMName'..." -ForegroundColor Cyan
Write-Host "Current layout:" -ForegroundColor Yellow

# Show current state
vbox-ssh $VMName "sudo lsblk && echo '---' && sudo lvdisplay | grep 'LV Size' && echo '---' && df -h /"

Write-Host "`nExpanding..." -ForegroundColor Cyan

# Run expansion commands - each separately to handle failures
Write-Host "Step 1: Grow partition..." -ForegroundColor Yellow
vbox-ssh $VMName "sudo growpart /dev/sda 3 2>/dev/null || echo 'Partition already at max size'"

Write-Host "Step 2: Resize physical volume..." -ForegroundColor Yellow
vbox-ssh $VMName "sudo pvresize /dev/sda3"

Write-Host "Step 3: Extend logical volume..." -ForegroundColor Yellow
vbox-ssh $VMName "sudo lvextend -l +100%FREE /dev/$LVMVolumeGroup/$LVMLogicalVolume"

Write-Host "Step 4: Resize filesystem..." -ForegroundColor Yellow
vbox-ssh $VMName "sudo resize2fs /dev/$LVMVolumeGroup/$LVMLogicalVolume"

Write-Host "`nFinal state:" -ForegroundColor Green
vbox-ssh $VMName "df -h /"
