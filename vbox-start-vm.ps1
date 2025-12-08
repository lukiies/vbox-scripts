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
