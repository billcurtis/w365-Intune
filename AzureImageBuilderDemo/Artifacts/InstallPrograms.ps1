<#

.DESCRIPTION 

This demo script installs necessary programs silently on a Windows VM image being built with Azure Image Builder. 

#>


# Installs Azure PowerShell module if not already installed from the web without any user interaction
# This installs as part of the Azure Image Builder demo setup
# Usage: .\InstallAzurePowershell.ps1   

# Setup logging
$logPath = "C:\temp\buildinstall.txt"
$logFolder = Split-Path -Path $logPath -Parent
if (-not (Test-Path -Path $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logPath -Append -Encoding UTF8
}

Write-Log "Installation script started"

 # Check if Az module is installed
if (-not (Get-Module -ListAvailable -Name Az)) {    
    Write-Log "Az module not found. Installing Azure PowerShell module..."
    
    # Install the Az module from PSGallery
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Install-Module -Name Az -AllowClobber -Force -Scope AllUsers
    Write-Log "Azure PowerShell module installed successfully"

} else {
    Write-Log "Az module is already installed"
}  

# Install Azure CLI if not already installed
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { 
    Write-Log "Installing Azure CLI..."
    
    # Download and install Azure CLI
    $installerPath = "$env:TEMP\AzureCLI.msi"
    Invoke-WebRequest -Uri "https://aka.ms/installazurecliwindows" -OutFile $installerPath
    Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" /quiet" -NoNewWindow -Wait
    Remove-Item $installerPath
    Write-Log "Azure CLI installed successfully"

} else {
    Write-Log "Azure CLI is already installed"
}

# Install Office 365 silently
$officeInstalled = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | 
    Where-Object { $_.DisplayName -like "*Microsoft 365*" -or $_.DisplayName -like "*Office 365*" }

if (-not $officeInstalled) {
    Write-Log "Installing Office 365..."
    
    # Create temp directory for Office installation
    $officeTemp = "$env:TEMP\OfficeInstall"
    New-Item -ItemType Directory -Path $officeTemp -Force | Out-Null
    
    # Download Office Deployment Tool
    $odtUrl = "https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_17328-20162.exe"
    $odtPath = "$officeTemp\ODTSetup.exe"
    Invoke-WebRequest -Uri $odtUrl -OutFile $odtPath
    
    # Extract ODT
    Start-Process -FilePath $odtPath -ArgumentList "/quiet /extract:`"$officeTemp`"" -Wait
    
    # Create configuration XML for Office 365 (Word and PowerPoint only)
    $configXml = @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="Current">
    <Product ID="O365ProPlusRetail">
      <Language ID="en-us" />
      <ExcludeApp ID="Access" />
      <ExcludeApp ID="Excel" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="Lync" />
      <ExcludeApp ID="OneNote" />
      <ExcludeApp ID="Outlook" />
      <ExcludeApp ID="Publisher" />
    </Product>
  </Add>
  <Display Level="None" AcceptEULA="TRUE" />
  <Property Name="AUTOACTIVATE" Value="1" />
</Configuration>
"@
    
    $configPath = "$officeTemp\configuration.xml"
    $configXml | Out-File -FilePath $configPath -Encoding ASCII
    
    # Install Office 365
    $setupPath = "$officeTemp\setup.exe"
    Start-Process -FilePath $setupPath -ArgumentList "/configure `"$configPath`"" -Wait -NoNewWindow
    
    # Cleanup
    Remove-Item -Path $officeTemp -Recurse -Force
    
    Write-Log "Office 365 installation completed"
} else {
    Write-Log "Office 365 is already installed"
}

Write-Log "Installation script completed"

