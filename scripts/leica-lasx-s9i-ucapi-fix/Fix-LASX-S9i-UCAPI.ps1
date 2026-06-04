<#
Repair-LASX-S9i.ps1

One-click conservative repair for Leica LAS X 3.x + Leica S9i/UVC issues.

Typical symptoms this script is intended for:
- LAS X can detect "Leica S9I Stereozoom", but Live view is black.
- Windows Camera app can show the microscope, but LAS X cannot.
- LAS X resolution list is corrupted, for example only 4:3 modes are shown.
- LAS X can show 1080p/2160p modes, but capture/white balance/brightness control hangs.

What this script changes:
1. UCAPI DirectShow compatibility
   File:
     C:\ProgramData\Leica Microsystems\UCAPI\ucapi-ahmconfig.installed
   It adds this line inside the %{ ... }% block if missing:
     UCDSHOW_ACCEPT_UNEXPECTED_FORMAT="1"
   Why:
     S9i is exposed to LAS X through UVC/DirectShow. Older LAS X/UCAPI builds can
     reject or mishandle a video format that Windows Camera accepts. This switch
     makes ucDShow.dll accept the returned DirectShow format more permissively.

2. LAS X dynamic hardware tree duplicate UCAPI camera nodes
   File:
     C:\ProgramData\Leica Microsystems\LAS X\Calibration Data\DefaultDynamicWidefieldTree.xlhw
   It removes duplicate:
     //CLObTreeNode[m_pData/CDrvOOCAMIUCAPI/sName]
   nodes while keeping the first occurrence of each camera name.
   Why:
     Duplicate S9i/Demo camera nodes can corrupt LAS X camera capability
     enumeration, causing bad or incomplete resolution lists.

What this script does NOT do:
- It does not uninstall or reinstall Leica software.
- It does not change Windows camera drivers.
- It does not delete original config files.
- It does not edit microscope firmware.

Backup and restore:
- Every edited file is backed up in two places before modification:
  1. A timestamped folder:
     Documents\Leica-LASX-Repair-Backups\yyyyMMdd-HHmmss\
  2. Next to the original file with a .bak-yyyyMMdd-HHmmss suffix.

Manual restore if the repair needs to be undone:
1. Close LAS X.
2. Open Task Manager and end LCS.exe if it is still running.
3. Copy the backup file from the timestamped backup folder back to its original path:
   - ucapi-ahmconfig.installed
     back to:
       C:\ProgramData\Leica Microsystems\UCAPI\ucapi-ahmconfig.installed
   - DefaultDynamicWidefieldTree.xlhw
     back to:
       C:\ProgramData\Leica Microsystems\LAS X\Calibration Data\DefaultDynamicWidefieldTree.xlhw
4. Start LAS X again.

Run examples:
  powershell -ExecutionPolicy Bypass -File .\Repair-LASX-S9i.ps1
  powershell -ExecutionPolicy Bypass -File .\Repair-LASX-S9i.ps1 -NoRestart
  powershell -ExecutionPolicy Bypass -File .\Repair-LASX-S9i.ps1 -NoPause

Parameters:
  -NoRestart
    Apply repairs but do not start LAS X after finishing.

  -NoPause
    Do not wait for Enter at the end. Useful for remote or scripted execution.

Important:
- Run this while you are not acquiring data.
- The script will close LAS X/LCS-related processes to release the camera and
  safely edit config files.
#>

[CmdletBinding()]
param(
    [switch]$NoRestart,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Relaunch-AsAdministrator {
    if (-not $PSCommandPath) {
        throw "This script must be saved as a .ps1 file before it can self-elevate."
    }

    $argsList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`""
    )
    if ($NoRestart) { $argsList += "-NoRestart" }
    if ($NoPause) { $argsList += "-NoPause" }

    Write-Host "Administrator rights are required. Relaunching elevated..."
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argsList
    exit
}

function New-BackupFolder {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $root = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Leica-LASX-Repair-Backups"
    $folder = Join-Path $root $stamp
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    return $folder
}

function Backup-File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BackupFolder
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $fileName = Split-Path -Leaf $Path
    $backupPath = Join-Path $BackupFolder $fileName
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force

    $sideBackupPath = "$Path.bak-$(Split-Path -Leaf $BackupFolder)"
    Copy-Item -LiteralPath $Path -Destination $sideBackupPath -Force

    return $backupPath
}

function Write-RestoreInstructions {
    param([Parameter(Mandatory = $true)][string]$BackupFolder)

    Write-Host ""
    Write-Host "Restore instructions:"
    Write-Host "1. Close LAS X."
    Write-Host "2. End LCS.exe in Task Manager if it is still running."
    Write-Host "3. Restore files from this backup folder:"
    Write-Host "   $BackupFolder"
    Write-Host "4. Copy backup files back to these original paths as needed:"
    Write-Host "   ucapi-ahmconfig.installed -> C:\ProgramData\Leica Microsystems\UCAPI\ucapi-ahmconfig.installed"
    Write-Host "   DefaultDynamicWidefieldTree.xlhw -> C:\ProgramData\Leica Microsystems\LAS X\Calibration Data\DefaultDynamicWidefieldTree.xlhw"
    Write-Host "5. Start LAS X again."
}

function Stop-LasXProcesses {
    $names = @(
        "LMSApplication",
        "LCS",
        "HWConfigurator",
        "CAMServer",
        "DyeDatabase"
    )

    $processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $names -contains $_.ProcessName
    })

    if ($processes.Count -eq 0) {
        Write-Host "No running LAS X/LCS process found."
        return
    }

    Write-Host "Stopping LAS X/LCS related processes..."
    Write-Host "This releases the camera handle and prevents config files from being rewritten during repair."

    foreach ($p in $processes) {
        try {
            if ($p.MainWindowHandle -ne 0) {
                [void]$p.CloseMainWindow()
            }
        } catch {
            Write-Verbose "CloseMainWindow failed for $($p.ProcessName): $_"
        }
    }

    Start-Sleep -Seconds 3

    foreach ($name in $names) {
        $remaining = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
        foreach ($p in $remaining) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                Write-Host "Stopped $($p.ProcessName) [$($p.Id)]."
            } catch {
                Write-Warning "Could not stop $($p.ProcessName) [$($p.Id)]: $_"
            }
        }
    }
}

function Repair-UcapiDirectShowConfig {
    param([Parameter(Mandatory = $true)][string]$BackupFolder)

    $path = Join-Path $env:ProgramData "Leica Microsystems\UCAPI\ucapi-ahmconfig.installed"
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Warning "UCAPI config not found: $path"
        Write-Warning "Skipping DirectShow compatibility repair."
        return [pscustomobject]@{ Path = $path; Status = "Missing"; Changed = $false }
    }

    $backupPath = Backup-File -Path $path -BackupFolder $BackupFolder
    Write-Host "Backed up UCAPI config to: $backupPath"

    $encoding = [Text.Encoding]::ASCII
    $text = [IO.File]::ReadAllText($path, $encoding)

    if ($text -match 'UCDSHOW_ACCEPT_UNEXPECTED_FORMAT\s*=\s*"1"') {
        Write-Host "UCAPI DirectShow compatibility switch already present."
        return [pscustomobject]@{ Path = $path; Status = "AlreadyPresent"; Changed = $false }
    }

    $line = 'UCDSHOW_ACCEPT_UNEXPECTED_FORMAT="1"'
    $closingBlock = [regex]::Match($text, '(?m)^\}%\s*$')

    if ($closingBlock.Success) {
        $newText = $text.Substring(0, $closingBlock.Index) + $line + "`r`n" + $text.Substring($closingBlock.Index)
    } else {
        $newText = $text.TrimEnd() + "`r`n%{`r`n$line`r`n}%`r`n"
    }

    [IO.File]::WriteAllText($path, $newText, $encoding)
    Write-Host "Added UCAPI DirectShow compatibility switch:"
    Write-Host "  UCDSHOW_ACCEPT_UNEXPECTED_FORMAT=`"1`""
    return [pscustomobject]@{ Path = $path; Status = "AddedSwitch"; Changed = $true }
}

function Save-XmlNoBom {
    param(
        [Parameter(Mandatory = $true)][xml]$Xml,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $settings = [Xml.XmlWriterSettings]::new()
    $settings.Encoding = [Text.UTF8Encoding]::new($false)
    $settings.Indent = $false
    $settings.NewLineHandling = [Xml.NewLineHandling]::None

    $writer = [Xml.XmlWriter]::Create($Path, $settings)
    try {
        $Xml.Save($writer)
    } finally {
        $writer.Close()
    }
}

function Repair-DynamicHardwareTree {
    param([Parameter(Mandatory = $true)][string]$BackupFolder)

    $path = Join-Path $env:ProgramData "Leica Microsystems\LAS X\Calibration Data\DefaultDynamicWidefieldTree.xlhw"
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Warning "LAS X dynamic hardware tree not found: $path"
        Write-Warning "Skipping hardware tree duplicate-node repair."
        return [pscustomobject]@{ Path = $path; Status = "Missing"; Changed = $false; Removed = 0 }
    }

    $xml = [Xml.XmlDocument]::new()
    $xml.PreserveWhitespace = $true
    $xml.Load($path)

    $nodes = @($xml.SelectNodes("//CLObTreeNode[m_pData/CDrvOOCAMIUCAPI/sName]"))
    if ($nodes.Count -eq 0) {
        Write-Host "No UCAPI camera nodes found in dynamic hardware tree."
        return [pscustomobject]@{ Path = $path; Status = "NoCameraNodes"; Changed = $false; Removed = 0 }
    }

    $seen = @{}
    $removed = 0
    $countsBefore = @{}

    foreach ($node in $nodes) {
        $nameNode = $node.SelectSingleNode("m_pData/CDrvOOCAMIUCAPI/sName")
        if ($null -eq $nameNode) { continue }

        $cameraName = $nameNode.InnerText
        if ([string]::IsNullOrWhiteSpace($cameraName)) { continue }

        if (-not $countsBefore.ContainsKey($cameraName)) {
            $countsBefore[$cameraName] = 0
        }
        $countsBefore[$cameraName]++

        if ($seen.ContainsKey($cameraName)) {
            [void]$node.ParentNode.RemoveChild($node)
            $removed++
        } else {
            $seen[$cameraName] = $true
        }
    }

    if ($removed -eq 0) {
        Write-Host "Dynamic hardware tree has no duplicate UCAPI camera nodes."
        Write-Host "Camera node counts:"
        foreach ($name in ($countsBefore.Keys | Sort-Object)) {
            Write-Host "  $name : $($countsBefore[$name])"
        }
        return [pscustomobject]@{ Path = $path; Status = "NoDuplicates"; Changed = $false; Removed = 0 }
    }

    $backupPath = Backup-File -Path $path -BackupFolder $BackupFolder
    Write-Host "Backed up dynamic hardware tree to: $backupPath"
    Save-XmlNoBom -Xml $xml -Path $path

    Write-Host "Removed $removed duplicate UCAPI camera node(s) from the dynamic hardware tree."
    Write-Host "Camera node counts before repair:"
    foreach ($name in ($countsBefore.Keys | Sort-Object)) {
        Write-Host "  $name : $($countsBefore[$name])"
    }
    return [pscustomobject]@{ Path = $path; Status = "RemovedDuplicates"; Changed = $true; Removed = $removed }
}

function Start-LasX {
    if ($NoRestart) {
        Write-Host "Skipping LAS X restart because -NoRestart was provided."
        return
    }

    $candidates = @(
        "$env:ProgramFiles\Leica Microsystems CMS GmbH\LAS X\BIN\LMSApplication.exe",
        "${env:ProgramFiles(x86)}\Leica Microsystems CMS GmbH\LAS X\BIN\LMSApplication.exe"
    )

    $exe = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if ($exe) {
        Start-Process -FilePath $exe
        Write-Host "Started LAS X: $exe"
    } else {
        Write-Warning "Could not find LMSApplication.exe. Please start LAS X manually."
    }
}

if (-not (Test-IsAdministrator)) {
    Relaunch-AsAdministrator
}

$backupFolder = New-BackupFolder
$transcriptPath = Join-Path $backupFolder "repair.log"

try {
    Start-Transcript -Path $transcriptPath -Force | Out-Null
} catch {
    Write-Warning "Could not start transcript: $_"
}

Write-Host ""
Write-Host "Leica LAS X / S9i repair started."
Write-Host "Backups will be written to: $backupFolder"
Write-Host "A full run log will be written to: $transcriptPath"
Write-Host ""
Write-Host "Planned actions:"
Write-Host "1. Stop LAS X/LCS related processes."
Write-Host "2. Back up UCAPI and LAS X hardware-tree configuration files."
Write-Host "3. Add the UCAPI DirectShow compatibility switch if missing."
Write-Host "4. Remove duplicate UCAPI camera nodes from the dynamic hardware tree if present."
Write-Host "5. Restart LAS X unless -NoRestart was specified."
Write-Host ""

$results = @()

try {
    Stop-LasXProcesses
    $results += Repair-UcapiDirectShowConfig -BackupFolder $backupFolder
    $results += Repair-DynamicHardwareTree -BackupFolder $backupFolder
    Start-LasX

    Write-Host ""
    Write-Host "Repair summary:"
    $results | Format-Table Status, Changed, Removed, Path -AutoSize
    Write-Host ""
    Write-Host "Done. If LAS X is open, test Live view now."
    Write-Host "If anything gets worse, restore the backups from: $backupFolder"
    Write-RestoreInstructions -BackupFolder $backupFolder
} catch {
    Write-Error $_
    Write-Host ""
    Write-Host "Repair failed. Backups, if created, are in: $backupFolder"
    Write-RestoreInstructions -BackupFolder $backupFolder
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch {}
    if (-not $NoPause) {
        Write-Host ""
        Read-Host "Press Enter to close"
    }
}
