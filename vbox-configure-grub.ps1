param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,

    [Parameter(Mandatory=$false)]
    [int]$Timeout = 1
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
    exit 1
}

# Check if VM is running
$IsRunning = & $VBoxManage list runningvms | Select-String -Pattern "`"$VMName`""

if (-not $IsRunning) {
    Write-Host "VM '$VMName' is not running. Please start it first." -ForegroundColor Red
    Write-Host "Run: vbox-start-vm $VMName" -ForegroundColor Yellow
    exit 1
}

Write-Host "Configuring GRUB timeout to $Timeout second(s) on VM '$VMName'..." -ForegroundColor Cyan

# Backup current GRUB configuration
Write-Host "Backing up current GRUB configuration..." -ForegroundColor Yellow
vbox-ssh $VMName "sudo cp /etc/default/grub /etc/default/grub.bak"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to backup GRUB configuration." -ForegroundColor Red
    exit 1
}

# Update GRUB timeout
Write-Host "Setting GRUB_TIMEOUT=$Timeout..." -ForegroundColor Yellow
vbox-ssh $VMName "sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$Timeout/' /etc/default/grub"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to update GRUB timeout." -ForegroundColor Red
    exit 1
}

# Also set GRUB_TIMEOUT_STYLE to reduce any additional delays
Write-Host "Setting GRUB_TIMEOUT_STYLE=hidden..." -ForegroundColor Yellow
vbox-ssh $VMName "sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub || echo 'GRUB_TIMEOUT_STYLE=hidden' | sudo tee -a /etc/default/grub > /dev/null"

# Update GRUB
Write-Host "Updating GRUB configuration..." -ForegroundColor Yellow
vbox-ssh $VMName "sudo update-grub"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nGRUB configuration updated successfully!" -ForegroundColor Green
    Write-Host "GRUB timeout is now set to $Timeout second(s)." -ForegroundColor Green
    Write-Host "`nThe VM will boot faster on next restart." -ForegroundColor Cyan
    Write-Host "`nRecommended next steps:" -ForegroundColor Yellow
    Write-Host "  1. Test the new configuration:" -ForegroundColor White
    Write-Host "     vbox-stop-vm $VMName" -ForegroundColor White
    Write-Host "     vbox-start-vm $VMName" -ForegroundColor White
    Write-Host "  2. If satisfied, create/update snapshot:" -ForegroundColor White
    Write-Host "     vbox-snapshot-set $VMName" -ForegroundColor White
} else {
    Write-Host "Failed to update GRUB configuration!" -ForegroundColor Red
    Write-Host "Restoring backup..." -ForegroundColor Yellow
    vbox-ssh $VMName "sudo cp /etc/default/grub.bak /etc/default/grub"
    exit 1
}
