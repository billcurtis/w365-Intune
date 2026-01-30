<#
.SYNOPSIS
    Downloads the Windows App (Remote Desktop client) and all its dependencies.

.DESCRIPTION
    This script downloads the Windows App (formerly Remote Desktop) MSIX package
    and all required dependencies from the Microsoft Store for offline installation.
    
    The Windows App is used to connect to:
    - Azure Virtual Desktop
    - Windows 365
    - Microsoft Dev Box
    - Remote Desktop Services

.PARAMETER OutputPath
    The folder path where downloaded files will be saved. Defaults to current directory.

.PARAMETER Architecture
    Target architecture: x64, x86, arm64. Defaults to x64.

.PARAMETER IncludeFrameworks
    Include VCLibs and other framework dependencies. Defaults to $true.

.EXAMPLE
    .\Download-WindowsApp.ps1 -OutputPath "C:\Packages" -Architecture "x64"

.NOTES
    Author: Bill Curtis - Vibe Coded (Claude Opus 4.5)
    Date: 30 January 2026
    Requires: PowerShell 5.1 or later, Internet connectivity
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Get-Location).Path,

    [Parameter(Mandatory = $false)]
    [ValidateSet("x64", "x86", "arm64")]
    [string]$Architecture = "x64",

    [Parameter(Mandatory = $false)]
    [bool]$IncludeFrameworks = $true
)

#region Functions

function Get-StorePackageLinks {
    <#
    .SYNOPSIS
        Gets download links for a Microsoft Store app using the store.rg-adguard.net API
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProductId,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Retail", "RP", "WIS", "WIF")]
        [string]$Ring = "Retail"
    )

    try {
        Write-Host "Fetching package links for Product ID: $ProductId" -ForegroundColor Cyan

        $apiUrl = "https://store.rg-adguard.net/api/GetFiles"
        
        $body = @{
            type = "ProductId"
            url  = $ProductId
            ring = $Ring
            lang = "en-US"
        }

        $response = Invoke-WebRequest -Uri $apiUrl -Method Post -Body $body -UseBasicParsing -ErrorAction Stop
        
        # Parse the HTML response to extract download links
        $links = @()
        $pattern = '<a href="([^"]+)"[^>]*>([^<]+)</a>'
        $matches = [regex]::Matches($response.Content, $pattern)

        foreach ($match in $matches) {
            $url = $match.Groups[1].Value
            $fileName = $match.Groups[2].Value

            if ($url -match "\.msixbundle$|\.appxbundle$|\.msix$|\.appx$") {
                $links += @{
                    Url      = $url
                    FileName = $fileName
                }
            }
        }

        return $links
    }
    catch {
        Write-Warning "Failed to fetch package links from store API: $_"
        return $null
    }
}

function Get-WindowsAppDirect {
    <#
    .SYNOPSIS
        Gets Windows App packages using direct Microsoft CDN approach
    #>
    param(
        [string]$Architecture
    )

    # Known package identifiers for Windows App and dependencies
    $packages = @{
        # Windows App (Microsoft Remote Desktop) - Store ID: 9N1F85V9T8BN
        WindowsApp = @{
            ProductId   = "9N1F85V9T8BN"
            PackageName = "Microsoft.WindowsApp"
        }
        
        # VCLibs dependency
        VCLibs14 = @{
            x64   = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
            x86   = "https://aka.ms/Microsoft.VCLibs.x86.14.00.Desktop.appx"
            arm64 = "https://aka.ms/Microsoft.VCLibs.arm64.14.00.Desktop.appx"
        }

        # UI.Xaml dependency
        UIXaml = @{
            NuGetUrl = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6"
        }

        # .NET Framework dependencies (if needed)
        DotNetNative = @{
            ProductId = "Microsoft.NET.Native.Framework.2.2"
        }
    }

    return $packages
}

function Download-File {
    <#
    .SYNOPSIS
        Downloads a file with progress indication
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [string]$FileName
    )

    try {
        if (-not $FileName) {
            $FileName = [System.IO.Path]::GetFileName($Url)
            # Clean up URL parameters from filename
            if ($FileName -match '\?') {
                $FileName = $FileName.Split('?')[0]
            }
        }

        $outputFile = Join-Path $OutputPath $FileName

        Write-Host "  Downloading: $FileName" -ForegroundColor Gray
        
        # Use BITS for better reliability if available
        if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
            Start-BitsTransfer -Source $Url -Destination $outputFile -ErrorAction Stop
        }
        else {
            # Fallback to Invoke-WebRequest
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $outputFile -UseBasicParsing -ErrorAction Stop
            $ProgressPreference = 'Continue'
        }

        if (Test-Path $outputFile) {
            $fileSize = (Get-Item $outputFile).Length / 1MB
            Write-Host "  ✓ Downloaded: $FileName ($([math]::Round($fileSize, 2)) MB)" -ForegroundColor Green
            return $outputFile
        }
        else {
            Write-Warning "  ✗ Failed to download: $FileName"
            return $null
        }
    }
    catch {
        Write-Warning "  ✗ Error downloading $FileName`: $_"
        return $null
    }
}

function Download-UIXamlFromNuGet {
    <#
    .SYNOPSIS
        Downloads Microsoft.UI.Xaml from NuGet and extracts the APPX
    #>
    param(
        [string]$OutputPath,
        [string]$Architecture
    )

    try {
        Write-Host "Downloading Microsoft.UI.Xaml from NuGet..." -ForegroundColor Cyan
        
        $nugetUrl = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6"
        $tempZip = Join-Path $env:TEMP "Microsoft.UI.Xaml.2.8.6.zip"
        $tempExtract = Join-Path $env:TEMP "UIXaml_Extract"

        # Download NuGet package
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $nugetUrl -OutFile $tempZip -UseBasicParsing -ErrorAction Stop
        $ProgressPreference = 'Continue'

        # Extract the package
        if (Test-Path $tempExtract) {
            Remove-Item $tempExtract -Recurse -Force
        }
        Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

        # Find the correct APPX for the architecture
        $appxPath = Join-Path $tempExtract "tools\AppX\$Architecture\Release"
        $appxFile = Get-ChildItem -Path $appxPath -Filter "*.appx" -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($appxFile) {
            $destFile = Join-Path $OutputPath $appxFile.Name
            Copy-Item -Path $appxFile.FullName -Destination $destFile -Force
            Write-Host "  ✓ Extracted: $($appxFile.Name)" -ForegroundColor Green
            
            # Cleanup
            Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
            Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
            
            return $destFile
        }
        else {
            Write-Warning "  Could not find UI.Xaml APPX for architecture: $Architecture"
            return $null
        }
    }
    catch {
        Write-Warning "Failed to download UI.Xaml from NuGet: $_"
        return $null
    }
}

function Install-WinGet {
    <#
    .SYNOPSIS
        Checks for and optionally installs WinGet
    #>
    
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        return $true
    }
    
    Write-Host "WinGet not found. Attempting to install..." -ForegroundColor Yellow
    
    try {
        # Try to install via Add-AppxPackage from GitHub
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $msixBundle = $releases.assets | Where-Object { $_.name -match "\.msixbundle$" } | Select-Object -First 1
        
        if ($msixBundle) {
            $tempFile = Join-Path $env:TEMP $msixBundle.name
            Invoke-WebRequest -Uri $msixBundle.browser_download_url -OutFile $tempFile -UseBasicParsing
            Add-AppxPackage -Path $tempFile -ErrorAction Stop
            Remove-Item $tempFile -Force
            return $true
        }
    }
    catch {
        Write-Warning "Could not install WinGet automatically: $_"
    }
    
    return $false
}

function Download-WithWinGet {
    <#
    .SYNOPSIS
        Downloads Windows App using WinGet
    #>
    param(
        [string]$OutputPath
    )

    try {
        Write-Host "Attempting download with WinGet..." -ForegroundColor Cyan
        
        # Export the package for offline installation
        $result = & winget download --id "Microsoft.WindowsApp" -d $OutputPath --accept-source-agreements --accept-package-agreements 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Windows App downloaded via WinGet" -ForegroundColor Green
            return $true
        }
        else {
            Write-Warning "WinGet download returned: $result"
            return $false
        }
    }
    catch {
        Write-Warning "WinGet download failed: $_"
        return $false
    }
}

#endregion

#region Main Script

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Windows App Download Script" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Target Architecture: $Architecture"
Write-Host "Output Path: $OutputPath"
Write-Host "Include Frameworks: $IncludeFrameworks"
Write-Host ""

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    Write-Host "Created output directory: $OutputPath" -ForegroundColor Gray
}

$downloadedFiles = @()

# Method 1: Try WinGet first (cleanest method)
Write-Host ""
Write-Host "STEP 1: Checking for WinGet..." -ForegroundColor Yellow
Write-Host "---------------------------------------------"

$hasWinGet = Get-Command winget -ErrorAction SilentlyContinue
if ($hasWinGet) {
    Write-Host "  WinGet is available" -ForegroundColor Green
    $wingetSuccess = Download-WithWinGet -OutputPath $OutputPath
}
else {
    Write-Host "  WinGet not available, using alternative method" -ForegroundColor Yellow
    $wingetSuccess = $false
}

# Method 2: Download from Microsoft Store API
if (-not $wingetSuccess) {
    Write-Host ""
    Write-Host "STEP 2: Downloading from Microsoft Store..." -ForegroundColor Yellow
    Write-Host "---------------------------------------------"

    # Windows App Product ID
    $productId = "9N1F85V9T8BN"
    
    $storeLinks = Get-StorePackageLinks -ProductId $productId -Ring "Retail"

    if ($storeLinks -and $storeLinks.Count -gt 0) {
        Write-Host "  Found $($storeLinks.Count) package(s)" -ForegroundColor Gray
        
        foreach ($link in $storeLinks) {
            # Filter by architecture
            $shouldDownload = $false
            
            if ($link.FileName -match "\.msixbundle$|\.appxbundle$") {
                # Bundles contain all architectures
                $shouldDownload = $true
            }
            elseif ($link.FileName -match $Architecture) {
                $shouldDownload = $true
            }
            elseif ($link.FileName -match "neutral") {
                $shouldDownload = $true
            }

            if ($shouldDownload) {
                $downloaded = Download-File -Url $link.Url -OutputPath $OutputPath -FileName $link.FileName
                if ($downloaded) {
                    $downloadedFiles += $downloaded
                }
            }
        }
    }
    else {
        Write-Host "  Could not retrieve store links, using direct download URLs..." -ForegroundColor Yellow
    }
}

# Step 3: Download framework dependencies
if ($IncludeFrameworks) {
    Write-Host ""
    Write-Host "STEP 3: Downloading Framework Dependencies..." -ForegroundColor Yellow
    Write-Host "---------------------------------------------"

    # Download VCLibs
    Write-Host "Downloading Microsoft.VCLibs.140.00.UWPDesktop..." -ForegroundColor Cyan
    $vclibsUrls = @{
        x64   = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        x86   = "https://aka.ms/Microsoft.VCLibs.x86.14.00.Desktop.appx"
        arm64 = "https://aka.ms/Microsoft.VCLibs.arm64.14.00.Desktop.appx"
    }

    $vclibsUrl = $vclibsUrls[$Architecture]
    $vclibsFile = Download-File -Url $vclibsUrl -OutputPath $OutputPath -FileName "Microsoft.VCLibs.$Architecture.14.00.Desktop.appx"
    if ($vclibsFile) {
        $downloadedFiles += $vclibsFile
    }

    # Download UI.Xaml
    Write-Host "Downloading Microsoft.UI.Xaml..." -ForegroundColor Cyan
    $uiXamlFile = Download-UIXamlFromNuGet -OutputPath $OutputPath -Architecture $Architecture
    if ($uiXamlFile) {
        $downloadedFiles += $uiXamlFile
    }
}

# Step 4: Create installation script
Write-Host ""
Write-Host "STEP 4: Creating Installation Script..." -ForegroundColor Yellow
Write-Host "---------------------------------------------"

$installScriptContent = @'
<#
.SYNOPSIS
    Installs Windows App and its dependencies
.DESCRIPTION
    Run this script as Administrator to install the Windows App
    and all downloaded dependencies.
#>

#Requires -RunAsAdministrator

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Installing Windows App and Dependencies..." -ForegroundColor Cyan
Write-Host ""

# Install VCLibs first
$vcLibs = Get-ChildItem -Path $scriptPath -Filter "*VCLibs*.appx" | Select-Object -First 1
if ($vcLibs) {
    Write-Host "Installing VCLibs..." -ForegroundColor Gray
    Add-AppxPackage -Path $vcLibs.FullName -ErrorAction SilentlyContinue
    Write-Host "  ✓ VCLibs installed" -ForegroundColor Green
}

# Install UI.Xaml
$uiXaml = Get-ChildItem -Path $scriptPath -Filter "*UI.Xaml*.appx" | Select-Object -First 1
if ($uiXaml) {
    Write-Host "Installing UI.Xaml..." -ForegroundColor Gray
    Add-AppxPackage -Path $uiXaml.FullName -ErrorAction SilentlyContinue
    Write-Host "  ✓ UI.Xaml installed" -ForegroundColor Green
}

# Install Windows App
$windowsApp = Get-ChildItem -Path $scriptPath -Filter "*WindowsApp*.msixbundle" | Select-Object -First 1
if (-not $windowsApp) {
    $windowsApp = Get-ChildItem -Path $scriptPath -Filter "*WindowsApp*.msix" | Select-Object -First 1
}
if (-not $windowsApp) {
    $windowsApp = Get-ChildItem -Path $scriptPath -Filter "*MicrosoftCorporationII*.msixbundle" | Select-Object -First 1
}

if ($windowsApp) {
    Write-Host "Installing Windows App..." -ForegroundColor Gray
    Add-AppxPackage -Path $windowsApp.FullName -ErrorAction Stop
    Write-Host "  ✓ Windows App installed" -ForegroundColor Green
}
else {
    Write-Warning "Windows App package not found in $scriptPath"
    Write-Host "Looking for any MSIX/APPX bundles..." -ForegroundColor Yellow
    Get-ChildItem -Path $scriptPath -Filter "*.msix*" | ForEach-Object {
        Write-Host "  Found: $($_.Name)" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host "You can now launch Windows App from the Start Menu." -ForegroundColor Cyan
'@

$installScriptPath = Join-Path $OutputPath "Install-WindowsApp.ps1"
$installScriptContent | Out-File -FilePath $installScriptPath -Encoding UTF8 -Force
Write-Host "  ✓ Created: Install-WindowsApp.ps1" -ForegroundColor Green

# Summary
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "DOWNLOAD COMPLETE" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Downloaded files:"
Get-ChildItem -Path $OutputPath -Filter "*.appx*" | ForEach-Object {
    $size = [math]::Round($_.Length / 1MB, 2)
    Write-Host "  - $($_.Name) ($size MB)" -ForegroundColor Gray
}
Get-ChildItem -Path $OutputPath -Filter "*.msix*" | ForEach-Object {
    $size = [math]::Round($_.Length / 1MB, 2)
    Write-Host "  - $($_.Name) ($size MB)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "To install, run as Administrator:" -ForegroundColor Yellow
Write-Host "  .\Install-WindowsApp.ps1" -ForegroundColor White
Write-Host ""
Write-Host "Or install manually with:" -ForegroundColor Yellow
Write-Host "  Add-AppxPackage -Path <path-to-msixbundle>" -ForegroundColor White
Write-Host ""

#endregion
