param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\exports"
)

# Find VBoxManage
$vboxPath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if (!(Test-Path $vboxPath)) {
    Write-Host "VBoxManage not found at $vboxPath" -ForegroundColor Red
    Write-Host "Please update the path in the script or add VirtualBox to your PATH" -ForegroundColor Yellow
    exit 1
}

# Create exports directory if it doesn't exist
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath | Out-Null
}

$exportFile = Join-Path $OutputPath "$VMName.ova"

Write-Host "Exporting VM '$VMName' to $exportFile..." -ForegroundColor Cyan

& $vboxPath export $VMName -o $exportFile

if ($LASTEXITCODE -eq 0) {
    Write-Host "Export completed successfully: $exportFile" -ForegroundColor Green
} else {
    Write-Host "Export failed with error code: $LASTEXITCODE" -ForegroundColor Red
    exit 1
}