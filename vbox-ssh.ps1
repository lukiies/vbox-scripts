param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$VMName,

    [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
    [string[]]$RemainingArgs
)

# Set VBoxManage path
$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

if (-not (Test-Path $VBoxManage)) {
    Write-Host "VBoxManage not found at: $VBoxManage" -ForegroundColor Red
    exit 1
}

# Get the SSH port forwarding info
$VMInfo = & $VBoxManage showvminfo $VMName --machinereadable 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "VM '$VMName' not found." -ForegroundColor Red
    exit 1
}

$SSHPort = ($VMInfo | Select-String 'Forwarding.*?Rule1.*?tcp.*?,(\d+),.*?22').Matches.Groups[1].Value

if (-not $SSHPort) {
    Write-Host "No SSH port forwarding found for VM '$VMName'" -ForegroundColor Red
    Write-Host "Make sure the VM was created with vbox-create-vm" -ForegroundColor Yellow
    exit 1
}

# Define SSH key path
$SSHKeyPath = "$HOME\.ssh.windows\id_rsa"

if (-not (Test-Path $SSHKeyPath)) {
    Write-Host "SSH key not found at: $SSHKeyPath" -ForegroundColor Red
    exit 1
}

# Build SSH command - use array to properly handle arguments
$SSHCommand = @(
    'ssh'
    '-F'
    'none'
    '-i'
    $SSHKeyPath
    '-o'
    'StrictHostKeyChecking=no'
    '-o'
    'UserKnownHostsFile=/dev/null'
    '-o'
    'LogLevel=ERROR'
    '-p'
    $SSHPort
    'root@localhost'
)

# Add any remaining arguments (could be SSH options or remote commands)
if ($RemainingArgs) {
    $SSHCommand += $RemainingArgs
}

# Execute SSH with proper argument passing
# Use & with array splatting to preserve arguments correctly
& $SSHCommand[0] $SSHCommand[1..($SSHCommand.Length-1)]
