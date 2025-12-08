param(
    [Parameter(Mandatory=$true)]
    [string]$VMName
)

# Set VBoxManage path
$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

# Get SSH port
$VMInfo = & $VBoxManage showvminfo $VMName --machinereadable 2>&1
$SSHPort = ($VMInfo | Select-String 'Forwarding.*?Rule1.*?tcp.*?,(\d+),.*?22').Matches.Groups[1].Value

if (-not $SSHPort) {
    Write-Host "Could not find SSH port for VM '$VMName'" -ForegroundColor Red
    exit 1
}

$SSHKeyPath = "$HOME\.ssh.windows\id_rsa"

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
vbox-ssh $VMName "sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv"

Write-Host "Step 4: Resize filesystem..." -ForegroundColor Yellow
vbox-ssh $VMName "sudo resize2fs /dev/ubuntu-vg/ubuntu-lv"

Write-Host "`nFinal state:" -ForegroundColor Green
vbox-ssh $VMName "df -h /"
