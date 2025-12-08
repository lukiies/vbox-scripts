param(
    [Parameter(Mandatory=$true)]
    [string]$VMName
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

# Check if VM is already running
$RunningVMs = & $VBoxManage list runningvms
$IsRunning = $false
foreach ($line in $RunningVMs) {
    if ($line -match "`"$VMName`"") {
        $IsRunning = $true
        break
    }
}

if ($IsRunning) {
    Write-Host "VM '$VMName' is already running." -ForegroundColor Yellow
    exit 0
}

# Start the VM in headless mode
Write-Host "Starting VM '$VMName' in headless mode..." -ForegroundColor Cyan
& $VBoxManage startvm $VMName --type headless

if ($LASTEXITCODE -eq 0) {
    Write-Host "VM '$VMName' started successfully!" -ForegroundColor Green

    # Get the SSH port forwarding info
    $VMInfo = & $VBoxManage showvminfo $VMName --machinereadable
    $SSHPort = ($VMInfo | Select-String 'Forwarding.*?Rule1.*?tcp.*?(\d+).*?22').Matches.Groups[1].Value

    if ($SSHPort) {
        Write-Host "`nTo SSH into it:" -ForegroundColor Yellow
        Write-Host "ssh user@localhost -p $SSHPort" -ForegroundColor White
    }
} else {
    Write-Host "Failed to start VM '$VMName'" -ForegroundColor Red
    exit 1
}
