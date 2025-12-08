param(
    [Parameter(Mandatory=$false)]
    [string]$ImportFile,

    [Parameter(Mandatory=$true)]
    [string]$NewVMName,

    [Parameter(Mandatory=$true)]
    [int]$HostPort,

    [Parameter(Mandatory=$false)]
    [string]$SSHUsername,

    [Parameter(Mandatory=$false)]
    [switch]$SkipHostnameChange
)

# Load configuration from .vbox-setup file
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir ".vbox-setup"

if (-not (Test-Path $ConfigFile)) {
    Write-Host "Configuration file not found: $ConfigFile" -ForegroundColor Red
    Write-Host "Please create .vbox-setup file in the scripts directory." -ForegroundColor Yellow
    Write-Host "See .vbox-setup.example for template." -ForegroundColor Yellow
    exit 1
}

# Parse configuration file
$Config = @{}
Get-Content $ConfigFile | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '=' } | ForEach-Object {
    $key, $value = $_ -split '=', 2
    $Config[$key.Trim()] = $ExecutionContext.InvokeCommand.ExpandString($value.Trim())
}

# Set defaults from config if not provided as parameters
if (-not $ImportFile) {
    $ImportFile = $Config['IMPORT_TEMPLATE_PATH']
}
if (-not $SSHUsername) {
    $SSHUsername = $Config['SSH_DEFAULT_USER']
    if (-not $SSHUsername) { $SSHUsername = "root" }
}

$VBoxManage = $Config['VBOX_MANAGE_PATH']
if (-not $VBoxManage) { $VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" }

$SSHKeyPath = $Config['SSH_KEY_PATH']
if (-not $SSHKeyPath) { $SSHKeyPath = "$HOME\.ssh.windows\id_rsa" }

$VMsFolder = $Config['VBOX_VMS_FOLDER']
if (-not $VMsFolder) { $VMsFolder = "C:\Users\$env:USERNAME\VirtualBox VMs" }

$DefaultDiskSize = $Config['DEFAULT_DISK_SIZE']
if (-not $DefaultDiskSize) { $DefaultDiskSize = 12.5 }

$LVMVolumeGroup = $Config['LVM_VOLUME_GROUP']
if (-not $LVMVolumeGroup) { $LVMVolumeGroup = "ubuntu-vg" }

$LVMLogicalVolume = $Config['LVM_LOGICAL_VOLUME']
if (-not $LVMLogicalVolume) { $LVMLogicalVolume = "ubuntu-lv" }

# Prompt for disk size if not provided
$DiskSizeInput = Read-Host "Enter disk size in GB (default: $DefaultDiskSize)"
if ([string]::IsNullOrWhiteSpace($DiskSizeInput)) {
    $DiskSizeGB = [double]$DefaultDiskSize
    $SkipDiskExpansion = $true
} else {
    $DiskSizeGB = [double]$DiskSizeInput
    $SkipDiskExpansion = $false
}

if (-not (Test-Path $VBoxManage)) {
    Write-Host "VBoxManage not found at: $VBoxManage" -ForegroundColor Red
    Write-Host "Please install VirtualBox or update VBOX_MANAGE_PATH in .vbox-setup" -ForegroundColor Red
    exit 1
}

# Resolve the full path of the import file
$FullImportPath = (Resolve-Path $ImportFile -ErrorAction SilentlyContinue).Path
if (-not $FullImportPath) {
    Write-Host "Import file not found: $ImportFile" -ForegroundColor Red
    exit 1
}

Write-Host "Importing VM from $FullImportPath as '$NewVMName'..." -ForegroundColor Cyan
Write-Host "This may take a few minutes..." -ForegroundColor Yellow

# Import the VM with options to suppress verbose output
# Redirect output but still show progress percentage
& $VBoxManage import $FullImportPath --vsys 0 --vmname $NewVMName --options keepallmacs --vsys 0 --unit 7 --ignore --vsys 0 --unit 8 --ignore --vsys 0 --unit 10 --ignore 2>&1 | ForEach-Object {
    if ($_ -match '^\d+%') {
        Write-Host $_ -NoNewline
        Write-Host "`r" -NoNewline
    } elseif ($_ -match 'Successfully imported') {
        Write-Host ""
        Write-Host $_ -ForegroundColor Green
    } elseif ($_ -match 'error|failed') {
        Write-Host ""
        Write-Host $_ -ForegroundColor Red
    }
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "Import failed with error code: $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

Write-Host "VM imported successfully. Configuring settings..." -ForegroundColor Cyan

# Resize disk if needed (only if user changed from default)
if (-not $SkipDiskExpansion) {
    Write-Host "Resizing disk to ${DiskSizeGB}GB..." -ForegroundColor Cyan

    # Get the disk file path - look for disk in VM's folder
    $VMFolder = Join-Path $VMsFolder $NewVMName
    $DiskPath = Get-ChildItem -Path $VMFolder -Filter "*.vmdk" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

    if (-not $DiskPath) {
        # Try .vdi format
        $DiskPath = Get-ChildItem -Path $VMFolder -Filter "*.vdi" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    }

    if (-not $DiskPath) {
        Write-Host "Warning: Could not find disk in $VMFolder. Skipping disk resize." -ForegroundColor Yellow
        $SkipDiskExpansion = $true
    } else {
        Write-Host "Found disk: $DiskPath" -ForegroundColor Cyan

        # Convert GB to MB (VBoxManage uses MB)
        $DiskSizeMB = $DiskSizeGB * 1024

        # Resize the disk
        & $VBoxManage modifyhd "$DiskPath" --resize $DiskSizeMB

        if ($LASTEXITCODE -eq 0) {
            Write-Host "Disk resized to ${DiskSizeGB}GB successfully." -ForegroundColor Green
        } else {
            Write-Host "Warning: Disk resize failed with error code: $LASTEXITCODE" -ForegroundColor Yellow
            $SkipDiskExpansion = $true
        }
    }
}

# Check if port forwarding rule already exists and remove it if needed
$ExistingRules = & $VBoxManage showvminfo $NewVMName --machinereadable | Select-String -Pattern "Forwarding.*Rule1"
if ($ExistingRules) {
    Write-Host "Removing existing port forwarding rule..." -ForegroundColor Yellow
    & $VBoxManage modifyvm $NewVMName --natpf1 delete "Rule1" 2>$null
}

# Configure port forwarding for SSH
Write-Host "Configuring port forwarding: localhost:$HostPort -> VM:22" -ForegroundColor Cyan
& $VBoxManage modifyvm $NewVMName --natpf1 "Rule1,tcp,,$HostPort,,22"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Port forwarding configuration failed with error code: $LASTEXITCODE" -ForegroundColor Red
    Write-Host "This usually means port $HostPort is already in use by another VM." -ForegroundColor Yellow
    Write-Host "Please choose a different port or check existing VMs." -ForegroundColor Yellow
    exit 1
}

Write-Host "Port forwarding configured: localhost:$HostPort -> VM:22" -ForegroundColor Green

if (-not $SkipHostnameChange) {
    # Start VM to change hostname
    Write-Host "`nStarting VM to configure hostname..." -ForegroundColor Cyan
    & vbox-start-vm $NewVMName

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to start VM. Hostname not changed." -ForegroundColor Red
        exit 1
    }

    # Wait for SSH to be available
    Write-Host "Waiting for SSH to be available (30 seconds)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30

    # Change hostname via SSH
    Write-Host "Changing hostname to '$NewVMName'..." -ForegroundColor Cyan

    $SSHCommands = @(
        "hostnamectl set-hostname $NewVMName",
        "sed -i 's/^127\.0\.1\.1.*/127.0.1.1 $NewVMName/' /etc/hosts",
        "echo '$NewVMName' > /etc/hostname"
    )

    # Check if SSH key exists
    if (-not (Test-Path $SSHKeyPath)) {
        Write-Host "SSH key not found at: $SSHKeyPath" -ForegroundColor Red
        Write-Host "Please ensure the Windows SSH key is set up correctly." -ForegroundColor Yellow
        Write-Host "Skipping hostname change..." -ForegroundColor Yellow
        $AllSuccess = $false
    } else {
        $AllSuccess = $true
        foreach ($cmd in $SSHCommands) {
            # Use Windows SSH key with no config file
            ssh -F none -i "$SSHKeyPath" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p $HostPort "$SSHUsername@localhost" $cmd 2>$null

            if ($LASTEXITCODE -ne 0) {
                $AllSuccess = $false
            }
        }

        # Expand disk partition and filesystem (only if disk was resized)
        if (-not $SkipDiskExpansion) {
            Write-Host "Expanding partition to use full disk space..." -ForegroundColor Cyan

            # Run each expansion command separately to handle failures gracefully
            vbox-ssh $NewVMName "sudo growpart /dev/sda 3 2>/dev/null || echo ''" | Out-Null
            vbox-ssh $NewVMName "sudo pvresize /dev/sda3 2>/dev/null" | Out-Null
            vbox-ssh $NewVMName "sudo lvextend -l +100%FREE /dev/$LVMVolumeGroup/$LVMLogicalVolume 2>/dev/null" | Out-Null
            vbox-ssh $NewVMName "sudo resize2fs /dev/$LVMVolumeGroup/$LVMLogicalVolume 2>/dev/null" | Out-Null

            # Get the final disk size
            $NewSize = vbox-ssh $NewVMName "df -h / | tail -1 | awk '{print \`$2}'" 2>$null

            if ($NewSize -and $NewSize.Trim()) {
                Write-Host "Disk expanded to: $($NewSize.Trim())" -ForegroundColor Green
            } else {
                Write-Host "Disk expansion completed." -ForegroundColor Green
            }
        }

        if ($AllSuccess) {
            Write-Host "Hostname successfully changed to '$NewVMName'!" -ForegroundColor Green
        } else {
            Write-Host "Some hostname change commands failed. You may need to change it manually." -ForegroundColor Yellow
        }

        # Verify hostname change
        Write-Host "Verifying hostname..." -ForegroundColor Cyan
        $NewHostname = ssh -F none -i "$SSHKeyPath" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $HostPort "$SSHUsername@localhost" "hostname" 2>$null
    }
    if ($AllSuccess) {
        if ($NewHostname -eq $NewVMName) {
            Write-Host "Hostname verified: $NewHostname" -ForegroundColor Green
        } else {
            Write-Host "Warning: Hostname is '$NewHostname', expected '$NewVMName'" -ForegroundColor Yellow
        }
    }

    # Stop the VM
    Write-Host "Stopping VM..." -ForegroundColor Cyan
    & vbox-stop-vm $NewVMName -Force

    Start-Sleep -Seconds 3
}

Write-Host "`nVM '$NewVMName' is ready!" -ForegroundColor Green
Write-Host "`nTo start it, run:" -ForegroundColor Yellow
Write-Host "  vbox-start-vm $NewVMName" -ForegroundColor White
Write-Host "`nTo SSH into it:" -ForegroundColor Yellow
Write-Host "  PowerShell: vbox-ssh $NewVMName" -ForegroundColor White
Write-Host "  Linux/Mac:  ssh -p $HostPort $SSHUsername@localhost" -ForegroundColor White