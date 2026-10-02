#Requires -Version 5.1
<#
.SYNOPSIS
  Removes what setup-android-emulator.ps1 installed. Every step asks first.

.PARAMETER SdkRoot
  SDK folder to clean. Default: your ANDROID_HOME, or C:\Android\sdk.

.PARAMETER Yes
  Answer "yes" to everything: deletes all AVDs, the whole SDK folder, env vars,
  PATH entries and Desktop/Start Menu launchers. Does NOT touch %USERPROFILE%\.android.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\uninstall-android-emulator.ps1
#>
[CmdletBinding()]
param(
    [string]$SdkRoot = '',
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ----------------------------------------------------------------- helpers
function Write-Step([string]$Text) {
    Write-Host ''
    Write-Host "=== $Text" -ForegroundColor Green
}

function Invoke-Native([scriptblock]$Cmd) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Cmd } finally { $ErrorActionPreference = $old }
}

function Confirm-Action([string]$Question, [bool]$DefaultYes = $false) {
    if ($Yes) { return $true }
    $hint = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    $r = Read-Host "$Question $hint"
    if ([string]::IsNullOrWhiteSpace($r)) { return $DefaultYes }
    return ($r -match '^[yY]')
}

# Returns zero-based indexes. Enter = none, 'a' = all, otherwise "1,3,4"
function Read-Selection([string]$Prompt, [int]$Count) {
    if ($Yes) { return @(0..($Count - 1)) }
    $r = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($r)) { return @() }
    if ($r.Trim() -match '^[aA]$') { return @(0..($Count - 1)) }
    $out = @()
    foreach ($part in ($r -split '[,\s]+')) {
        $n = 0
        if ([int]::TryParse($part, [ref]$n) -and $n -ge 1 -and $n -le $Count) { $out += ($n - 1) }
    }
    return @($out | Sort-Object -Unique)
}

function Remove-Tree([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    } catch {
        # fallback for very long paths / read-only files
        Invoke-Native { cmd.exe /c rmdir /s /q $Path | Out-Null }
    }
    if (Test-Path -LiteralPath $Path) {
        Write-Warning "Could not fully delete $Path (a file may be in use). Close the emulator/IDE and retry."
    } else {
        Write-Host "Deleted $Path"
    }
}

function Test-UnderPath([string]$Child, [string]$Parent) {
    if (-not $Child -or -not $Parent) { return $false }
    $p = $Parent.TrimEnd('\') + '\'
    return ($Child.TrimEnd('\') + '\').StartsWith($p, [StringComparison]::OrdinalIgnoreCase)
}

# ----------------------------------------------------------------- resolve SDK root
if (-not $SdkRoot) {
    $SdkRoot = [Environment]::GetEnvironmentVariable('ANDROID_HOME', 'User')
    if (-not $SdkRoot) { $SdkRoot = $env:ANDROID_HOME }
    if (-not $SdkRoot) { $SdkRoot = 'C:\Android\sdk' }
}
$SdkRoot = $SdkRoot.TrimEnd('\')

# Safety: never operate on drive roots or system folders
$protected = @($env:USERPROFILE, $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA) |
    Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
if ($SdkRoot.Length -le 3 -or ($protected -contains $SdkRoot)) {
    throw "Refusing to use '$SdkRoot' as the SDK folder (too risky). Pass -SdkRoot with the real SDK path."
}

Write-Host "SDK folder: $SdkRoot" -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $SdkRoot)) {
    Write-Warning 'That folder does not exist. Only environment/AVD/launcher cleanup will be offered.'
}

# ----------------------------------------------------------------- 1. stop processes
Write-Step '1/6  Stopping emulator and adb'
$adb = Join-Path $SdkRoot 'platform-tools\adb.exe'
if (Test-Path -LiteralPath $adb) { Invoke-Native { & $adb kill-server 2>&1 | Out-Null } }
Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -match '^(emulator|qemu-system.*|adb|crashpad_handler)$' } |
    Where-Object { try { Test-UnderPath $_.Path $SdkRoot } catch { $false } } |
    ForEach-Object {
        Write-Host "Stopping $($_.ProcessName) (PID $($_.Id))"
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
Start-Sleep -Seconds 1

# ----------------------------------------------------------------- 2. AVDs
Write-Step '2/6  Virtual devices (AVDs)'
$avdHome = $env:ANDROID_AVD_HOME
if (-not $avdHome) {
    $userHome = $env:ANDROID_USER_HOME
    if (-not $userHome) { $userHome = Join-Path $env:USERPROFILE '.android' }
    $avdHome = Join-Path $userHome 'avd'
}
$avds = @()
if (Test-Path -LiteralPath $avdHome) {
    $avds = @(Get-ChildItem -LiteralPath $avdHome -Filter '*.ini' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName })
}
if ($avds.Count -eq 0) {
    Write-Host "No AVDs found in $avdHome"
} else {
    Write-Host "AVD folder: $avdHome"
    for ($i = 0; $i -lt $avds.Count; $i++) { Write-Host ('  [{0}] {1}' -f ($i + 1), $avds[$i]) }
    $sel = Read-Selection 'Delete which AVDs? (a = all, e.g. 1,3, Enter = none)' $avds.Count
    foreach ($i in $sel) {
        $n = $avds[$i]
        Remove-Tree (Join-Path $avdHome "$n.avd")
        $ini = Join-Path $avdHome "$n.ini"
        if (Test-Path -LiteralPath $ini) { Remove-Item -LiteralPath $ini -Force }
        Write-Host "Removed AVD '$n'"
    }
}

# ----------------------------------------------------------------- 3. SDK contents
Write-Step '3/6  SDK packages'
$wholeSdkRemoved = $false
if (Test-Path -LiteralPath $SdkRoot) {
    $mode = 3
    if ($Yes) {
        $mode = 1
    } else {
        Write-Host '  [1] Delete the ENTIRE SDK folder (emulator, images, platforms, tools - everything)'
        Write-Host '  [2] Choose individual packages to uninstall (needs Java)'
        Write-Host '  [3] Skip'
        $r = Read-Host 'Select 1-3 [Enter = 3]'
        if ($r -match '^[12]$') { $mode = [int]$r }
    }

    if ($mode -eq 1) {
        Write-Host "This will permanently delete: $SdkRoot" -ForegroundColor Yellow
        if (Confirm-Action 'Are you sure?' $false) {
            Remove-Tree $SdkRoot
            $wholeSdkRemoved = -not (Test-Path -LiteralPath $SdkRoot)
        }
    } elseif ($mode -eq 2) {
        $sdkmanager = Join-Path $SdkRoot 'cmdline-tools\latest\bin\sdkmanager.bat'
        if (-not (Test-Path -LiteralPath $sdkmanager)) {
            Write-Warning 'sdkmanager not found; cannot list packages. Use option 1 or delete folders manually.'
        } else {
            $env:SKIP_JDK_VERSION_CHECK = '1'
            $txt = ''
            Invoke-Native { $script:txt = (& $sdkmanager "--sdk_root=$SdkRoot" --list_installed 2>&1 | ForEach-Object { $_.ToString() }) -join "`n" }
            # old format:  "path | version | description | location"
            # Android CLI: "path    version"  (description on the next line)
            $pk = @($txt -split "[\r\n]+" | ForEach-Object { $_.Trim() } |
                Where-Object { $_ -match '^[A-Za-z0-9_.\-]+([;/][A-Za-z0-9_.\-]+)*\s*(\||\s\d)' } |
                ForEach-Object { ($_ -split '[\s|]+')[0] } |
                Where-Object { $_ -notmatch '^(Path|Installed|Available|Description|Version)$' -and $_ -notmatch '^cmdline-tools[;/]latest$' } |
                Sort-Object -Unique)
            if ($pk.Count -eq 0) {
                Write-Host 'No removable packages found.'
            } else {
                for ($i = 0; $i -lt $pk.Count; $i++) { Write-Host ('  [{0}] {1}' -f ($i + 1), $pk[$i]) }
                $sel = Read-Selection 'Uninstall which packages? (a = all, e.g. 1,3, Enter = none)' $pk.Count
                if ($sel.Count -gt 0) {
                    $targets = @($sel | ForEach-Object { $pk[$_] })
                    Invoke-Native { & $sdkmanager "--sdk_root=$SdkRoot" --uninstall @targets }
                }
            }
        }
    }
} else {
    Write-Host 'SDK folder not present, nothing to remove.'
}

# ----------------------------------------------------------------- 4. env vars + PATH
Write-Step '4/6  Environment variables and PATH'
if (Confirm-Action "Remove ANDROID_HOME / ANDROID_SDK_ROOT and PATH entries that point into $SdkRoot?" $true) {
    foreach ($name in 'ANDROID_HOME', 'ANDROID_SDK_ROOT') {
        $val = [Environment]::GetEnvironmentVariable($name, 'User')
        if ($val -and ($val.TrimEnd('\') -ieq $SdkRoot)) {
            [Environment]::SetEnvironmentVariable($name, $null, 'User')
            Write-Host "Removed user variable $name"
        } elseif ($val) {
            Write-Host "Kept $name (points elsewhere: $val)"
        }
        $pv = [Environment]::GetEnvironmentVariable($name, 'Process')
        if ($pv -and ($pv.TrimEnd('\') -ieq $SdkRoot)) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
    }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath) {
        $parts = @($userPath -split ';' | Where-Object { $_ })
        $keep  = @($parts | Where-Object { -not (Test-UnderPath $_ $SdkRoot) })
        $drop  = @($parts | Where-Object { Test-UnderPath $_ $SdkRoot })
        if ($drop.Count -gt 0) {
            [Environment]::SetEnvironmentVariable('Path', ($keep -join ';'), 'User')
            $drop | ForEach-Object { Write-Host "Removed from user PATH: $_" }
        } else {
            Write-Host 'No matching entries in user PATH.'
        }
    }
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($machinePath -and (@($machinePath -split ';') | Where-Object { Test-UnderPath $_ $SdkRoot }).Count -gt 0) {
        Write-Warning 'The system-wide PATH also contains SDK entries. Remove them manually (needs admin).'
    }
}

# ----------------------------------------------------------------- 5. launchers
Write-Step '5/6  Desktop / Start Menu launchers'
$folders = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs')) |
    Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$ws = New-Object -ComObject WScript.Shell
$launchers = @()
foreach ($f in $folders) {
    # older installer versions created Start-*.bat files
    $launchers += @(Get-ChildItem -LiteralPath $f -Filter 'Start-*.bat' -File -ErrorAction SilentlyContinue |
        Where-Object { (Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue) -match [regex]::Escape($SdkRoot) })
    # shortcuts that open the launcher window
    $launchers += @(Get-ChildItem -LiteralPath $f -Filter '*.lnk' -File -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $a = $ws.CreateShortcut($_.FullName).Arguments
                ($a -like '*emulator-launcher.ps1*') -and ($a.IndexOf($SdkRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0)
            } catch { $false }
        })
}
if ($launchers.Count -eq 0) {
    Write-Host 'No launchers created by the installer were found.'
} else {
    $launchers | ForEach-Object { Write-Host "  $($_.FullName)" }
    if (Confirm-Action 'Delete these launchers?' $true) {
        $launchers | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force; Write-Host "Deleted $($_.Name)" }
    }
}

# launcher script (inside the SDK folder) and its saved options
$launcherDir = Join-Path $SdkRoot 'launcher'
$launcherData = Join-Path $env:LOCALAPPDATA 'AndroidEmulatorLauncher'
$leftovers = @($launcherDir, $launcherData) | Where-Object { Test-Path -LiteralPath $_ }
if ($leftovers.Count -gt 0) {
    $leftovers | ForEach-Object { Write-Host "  $_" }
    if (Confirm-Action 'Delete the launcher script and its saved options?' $true) {
        $leftovers | ForEach-Object { Remove-Tree $_ }
    }
}

# ----------------------------------------------------------------- 6. .android folder
Write-Step '6/6  User settings folder (optional)'
$dotAndroid = Join-Path $env:USERPROFILE '.android'
if (Test-Path -LiteralPath $dotAndroid) {
    Write-Host "$dotAndroid holds adb keys and emulator settings."
    Write-Host 'It is SHARED with Android Studio, so only delete it if you use no other Android tools.' -ForegroundColor Yellow
    if ($Yes) {
        Write-Host 'Skipped (-Yes never deletes this folder).'
    } elseif (Confirm-Action 'Delete it?' $false) {
        Remove-Tree $dotAndroid
    }
} else {
    Write-Host 'Not present.'
}

# ----------------------------------------------------------------- done
Write-Host ''
Write-Host 'Uninstall finished. Open a NEW terminal for PATH changes to apply.' -ForegroundColor Green
Write-Host 'Not touched: Java, and Windows Hypervisor Platform. To disable the latter (admin PowerShell, then reboot):'
Write-Host '  Disable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform'
