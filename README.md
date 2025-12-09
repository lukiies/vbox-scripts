# VirtualBox VM Management Scripts

A collection of PowerShell scripts for automating VirtualBox VM lifecycle management on Windows. These scripts provide a streamlined workflow for creating, managing, and accessing Ubuntu VMs with automatic disk expansion, SSH configuration, and hostname customization.

## 📋 Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Scripts Overview](#scripts-overview)
- [Usage Examples](#usage-examples)
- [Security Notes](#security-notes)

## ✨ Features

- **Automated VM creation** from OVA templates with custom disk sizes
- **Intelligent disk expansion** using LVM (only when needed)
- **SSH key-based authentication** with automatic port forwarding
- **Hostname customization** during VM creation
- **Headless VM management** (start, stop, destroy)
- **Transparent SSH proxy** for easy VM access
- **Snapshot management** for fast iterative testing (50-100x faster than recreating VMs)
- **Clean, color-coded output** for better user experience

## 📦 Prerequisites

- **Windows 10/11** with PowerShell 5.1 or later
- **Oracle VirtualBox** installed (tested with VirtualBox 7.x)
- **SSH client** (built-in on Windows 10/11)
- **SSH key pair** configured at `~\.ssh.windows\id_rsa`
- **Ubuntu OVA template** (e.g., Ubuntu 20.04 minimal with LVM)

## 🚀 Installation

1. Clone this repository or download the scripts:
   ```powershell
   git clone https://github.com/lukiies/vbox-scripts.git
   cd vbox-scripts
   ```

2. Add the scripts directory to your PATH (optional but recommended):
   ```powershell
   $env:PATH += ";C:\path\to\vbox-scripts"
   ```

3. Configure the `.vbox-setup` file (see [Configuration](#configuration) below)

## ⚙️ Configuration

Before using the scripts, edit the `.vbox-setup` file in the same directory as the scripts:

```ini
# VirtualBox installation path
VBOX_MANAGE_PATH=C:\Program Files\Oracle\VirtualBox\VBoxManage.exe

# Default OVA/OVF template file path for creating new VMs
IMPORT_TEMPLATE_PATH=C:\path\to\your\Ubuntu-20.04-minimal.ova

# VirtualBox VMs base directory
VBOX_VMS_FOLDER=C:\Users\$env:USERNAME\VirtualBox VMs

# SSH configuration
SSH_KEY_PATH=$HOME\.ssh.windows\id_rsa
SSH_DEFAULT_USER=root

# Default disk size for new VMs (in GB)
DEFAULT_DISK_SIZE=12.5

# LVM configuration (for Ubuntu VMs with LVM)
LVM_VOLUME_GROUP=ubuntu-vg
LVM_LOGICAL_VOLUME=ubuntu-lv
```

**Important**: Update `IMPORT_TEMPLATE_PATH` to point to your Ubuntu OVA template file.

## 📚 Scripts Overview

### vbox-create-vm.ps1

Creates a new VM from an OVA template with automatic configuration.

**Features**:
- Imports OVA and renames VM
- Configures SSH port forwarding
- Optionally resizes disk and expands LVM volumes
- Changes hostname to match VM name
- Supports custom disk sizes (default: 12.5 GB)

**Parameters**:
- `-ImportFile` (optional): Path to OVA template (uses config default if not specified)
- `-NewVMName` (required): Name for the new VM
- `-HostPort` (required): Local port for SSH forwarding (e.g., 2201, 2202)
- `-SSHUsername` (optional): SSH user (default: root)
- `-SkipHostnameChange` (optional): Skip hostname modification

**Usage**:
```powershell
vbox-create-vm -NewVMName "myvm" -HostPort 2201
# You'll be prompted for disk size (default: 12.5 GB)
# Press Enter to keep default, or enter custom size
```

**Interactive Prompts**:
- Disk size in GB (default: 12.5) - only expands if changed from default

**Output**:
- VM imported and configured
- SSH port forwarding: `localhost:2201 -> VM:22`
- Hostname set to VM name
- Disk expanded (if custom size specified)

---

### vbox-start-vm.ps1

Starts a VM in headless mode (no GUI window).

**Parameters**:
- `-VMName` (required): Name of the VM to start

**Usage**:
```powershell
vbox-start-vm myvm
```

**Output**:
- Displays SSH connection command with port number

---

### vbox-stop-vm.ps1

Stops a running VM gracefully or forcefully.

**Parameters**:
- `-VMName` (required): Name of the VM to stop
- `-Force` (optional): Force immediate poweroff instead of graceful shutdown

**Usage**:
```powershell
# Graceful shutdown (sends ACPI signal)
vbox-stop-vm myvm

# Force poweroff (immediate)
vbox-stop-vm myvm -Force
```

---

### vbox-destroy-vm.ps1

Completely removes a VM and all its files.

**Parameters**:
- `-VMName` (required): Name of the VM to destroy
- `-Force` (optional): Skip confirmation prompt

**Usage**:
```powershell
# With confirmation
vbox-destroy-vm myvm

# Without confirmation
vbox-destroy-vm myvm -Force
```

**Warning**: This permanently deletes all VM data including virtual disks!

---

### vbox-ssh.ps1

Transparent SSH proxy to connect to VMs using their name instead of port numbers.

**Features**:
- Automatically detects SSH port from VM configuration
- Uses configured SSH key
- Suppresses known_hosts warnings
- Passes through all SSH arguments and remote commands

**Parameters**:
- `-VMName` (required, position 0): Name of the VM
- Additional arguments: Passed directly to SSH

**Usage**:
```powershell
# Interactive SSH session
vbox-ssh myvm

# Run remote command
vbox-ssh myvm "df -h"

# Run multiple commands
vbox-ssh myvm "sudo apt update && sudo apt upgrade -y"

# SSH with port forwarding
vbox-ssh myvm -L 8080:localhost:80
```

---

### vbox-expand-disk.ps1

Manually expands disk and LVM volumes on an existing VM (debugging/repair tool).

**Features**:
- Shows current disk layout
- Expands partition using growpart
- Resizes LVM physical volume, logical volume, and ext4 filesystem
- Shows final disk size

**Parameters**:
- `-VMName` (required): Name of the VM to expand

**Usage**:
```powershell
vbox-expand-disk myvm
```

**Note**: VM must be running. First resize the VirtualBox disk using VBoxManage before running this script.

---

### vbox-snapshot-set.ps1

Creates an initial baseline snapshot for a VM to enable fast rollback during iterative testing.

**Features**:
- Creates single "initial-baseline" snapshot per VM (prevents snapshot accumulation)
- Can snapshot running VMs (creates live snapshot)
- Prevents duplicate snapshots with clear error messages
- Customizable snapshot name and description

**Parameters**:
- `-VMName` (required): Name of the VM to snapshot
- `-SnapshotName` (optional): Custom snapshot name (default: "initial-baseline")
- `-Description` (optional): Snapshot description

**Usage**:
```powershell
# Create initial snapshot with default name
vbox-snapshot-set myvm

# Custom snapshot name and description
vbox-snapshot-set myvm -SnapshotName "clean-state" -Description "Ready for restore testing"
```

**Output**:
- Creates snapshot and displays current snapshots
- Shows instructions for rollback

---

### vbox-snapshot-rollback.ps1

Quickly restores VM to initial baseline snapshot state (5-20 seconds vs 5-15 minutes to recreate).

**Features**:
- Automatically powers off VM if running
- Restores to baseline snapshot
- Automatically starts VM after restore (unless `-NoStart`)
- Shows SSH connection info after restore
- Provides workflow reminders

**Parameters**:
- `-VMName` (required): Name of the VM to rollback
- `-SnapshotName` (optional): Custom snapshot name (default: "initial-baseline")
- `-NoStart` (optional): Leave VM powered off after restore

**Usage**:
```powershell
# Rollback and restart VM (typical workflow)
vbox-snapshot-rollback myvm

# Rollback but leave VM powered off
vbox-snapshot-rollback myvm -NoStart

# Rollback to custom snapshot name
vbox-snapshot-rollback myvm -SnapshotName "clean-state"
```

**Output**:
- VM restored to snapshot state
- VM restarted and ready for testing
- Displays workflow reminder

**Performance**: ~50-100x faster than destroying and recreating VM

---

## 💡 Usage Examples

### Example 1: Create and access a new VM

```powershell
# Create VM with default disk size (12.5 GB)
vbox-create-vm -NewVMName "webserver" -HostPort 2201
# Press Enter when prompted for disk size

# Start the VM
vbox-start-vm webserver

# SSH into it
vbox-ssh webserver
```

### Example 2: Create VM with custom disk size

```powershell
# Create VM with 50 GB disk
vbox-create-vm -NewVMName "database" -HostPort 2202
# Enter "50" when prompted for disk size

# The script will automatically:
# - Resize VirtualBox disk to 50 GB
# - Expand partition to use full disk
# - Extend LVM logical volume
# - Resize ext4 filesystem
```

### Example 3: Manage multiple VMs

```powershell
# Create three VMs
vbox-create-vm -NewVMName "web1" -HostPort 2201
vbox-create-vm -NewVMName "web2" -HostPort 2202
vbox-create-vm -NewVMName "db1" -HostPort 2203

# Start all
vbox-start-vm web1
vbox-start-vm web2
vbox-start-vm db1

# Access specific VM
vbox-ssh web1

# Stop all
vbox-stop-vm web1
vbox-stop-vm web2
vbox-stop-vm db1
```

### Example 4: Remote command execution

```powershell
# Check disk space on all VMs
vbox-ssh web1 "df -h /"
vbox-ssh web2 "df -h /"
vbox-ssh db1 "df -h /"

# Update all VMs
vbox-ssh web1 "sudo apt update && sudo apt upgrade -y"
vbox-ssh web2 "sudo apt update && sudo apt upgrade -y"
vbox-ssh db1 "sudo apt update && sudo apt upgrade -y"

# Check hostname
vbox-ssh web1 "hostname"
```

### Example 5: Create VM with custom template

```powershell
vbox-create-vm -ImportFile "D:\VMs\Templates\Ubuntu-22.04.ova" -NewVMName "custom" -HostPort 2210
```

### Example 6: Iterative testing workflow with snapshots

```powershell
# 1. Create VM for testing
vbox-create-vm -NewVMName "restore-test" -HostPort 2210

# 2. Configure VM (install prerequisites, etc.)
vbox-ssh restore-test
# ... install packages, configure settings ...
exit

# 3. Create baseline snapshot
vbox-snapshot-set restore-test

# 4. Iterative testing cycle
# Run your restore script and test
vbox-ssh restore-test "bash /path/to/restore-script.sh"

# Check results
vbox-ssh restore-test "df -h && systemctl status myapp"

# 5. Rollback to clean state (5-20 seconds!)
vbox-snapshot-rollback restore-test

# 6. Make changes to restore script and repeat
# The VM is now back to pristine state - test again!
vbox-ssh restore-test "bash /path/to/restore-script-v2.sh"
```

**Performance Comparison**:
- **Without snapshots**: 5-15 minutes per test iteration (destroy + recreate VM)
- **With snapshots**: 5-20 seconds per test iteration (rollback)
- **Speed improvement**: 50-100x faster

### Example 7: Multiple snapshot points

```powershell
# Create VM
vbox-create-vm -NewVMName "app-test" -HostPort 2211

# Create snapshot at clean state
vbox-snapshot-set app-test -SnapshotName "clean" -Description "Fresh OS install"

# Install dependencies
vbox-ssh app-test "sudo apt update && sudo apt install -y nginx postgresql"

# Create snapshot after dependencies
vbox-snapshot-set app-test -SnapshotName "deps-installed" -Description "All dependencies installed"

# Now you can rollback to either snapshot:
vbox-snapshot-rollback app-test -SnapshotName "clean"  # Back to fresh OS
# or
vbox-snapshot-rollback app-test -SnapshotName "deps-installed"  # Back to ready state
```

## 🔒 Security Notes

### What's Safe to Commit

These scripts are designed to **NOT contain any sensitive information** when properly configured:

- ✅ All paths are read from `.vbox-setup` configuration file
- ✅ No hardcoded passwords or credentials
- ✅ SSH keys are referenced by path, not embedded
- ✅ No personal directory paths in committed code

### Sensitive Files (DO NOT COMMIT)

The following files should **NEVER** be committed to version control:

- ❌ `.vbox-setup` - Contains your local paths and configuration
- ❌ `~\.ssh.windows\id_rsa` - Your SSH private key
- ❌ Any OVA/OVF template files

### Git Configuration

This repository includes a `.gitignore` file that:
- ✅ Tracks only `vbox-*` scripts
- ❌ Ignores all other files in the directory
- ✅ Tracks `.gitignore` itself
- ❌ Excludes `.vbox-setup` (configuration)

### Recommendations

1. **Keep `.vbox-setup` local** - Each user should create their own configuration
2. **Use SSH keys** - Never use password authentication
3. **Restrict SSH key permissions** - Ensure private key is readable only by you
4. **Use unique ports** - Avoid port conflicts between VMs
5. **Regular backups** - VMs are easily destroyed; back up important data

## 🐛 Troubleshooting

### Port already in use

```
Error: A NAT rule for this host port already exists
```

**Solution**: Choose a different port number or stop the VM using that port.

### SSH key not found

```
SSH key not found at: C:\Users\USERNAME\.ssh.windows\id_rsa
```

**Solution**: Create an SSH key pair or update `SSH_KEY_PATH` in `.vbox-setup`.

### Disk expansion fails

```
Warning: Could not find disk path. Skipping disk resize.
```

**Solution**: Ensure VM was created successfully and check VirtualBox VMs folder path in configuration.

### VM doesn't start

```
Failed to start VM
```

**Solution**:
1. Check VirtualBox is running
2. Ensure no other VM is using the same resources
3. Try starting manually via VirtualBox GUI to see detailed error

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

## ✍️ Author

Created by [lukiies](https://github.com/lukiies)

## 🙏 Acknowledgments

- VirtualBox by Oracle
- PowerShell team at Microsoft
