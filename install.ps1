<#
.SYNOPSIS
    Install or remove the USB Tether Watcher autostart entry.

.DESCRIPTION
    Writes a tiny hidden VBS launcher into the current user's Startup folder so
    the watcher starts (invisibly) at every logon, then starts it once and
    verifies that it is really running.

    No administrator rights are required - the Startup folder belongs to you.
    The generated .vbs is written as UTF-16LE, so paths containing non-ASCII
    characters (e.g. a Chinese user name) work correctly. Windows Script Host
    reads ANSI .vbs files, which is the classic way these launchers break.

.PARAMETER Uninstall
    Remove the autostart entry and stop the running watcher.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$watcher = Join-Path $here 'usb-tether-watch.ps1'
$pidFile = Join-Path $here 'usb-tether-watch.pid'
$logFile = Join-Path $here 'usb-tether-watch.log'
$startup = [Environment]::GetFolderPath('Startup')
$launcher = Join-Path $startup 'USB-Tether-Watch.vbs'

function Stop-Watcher {
    if (-not (Test-Path $pidFile)) { return }
    $wpid = (Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($wpid -and $wpid -match '^\d+$') {
        $p = Get-Process -Id ([int]$wpid) -ErrorAction SilentlyContinue
        if ($p -and $p.ProcessName -eq 'powershell') {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] stopped watcher (pid $($p.Id))"
        }
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------
if ($Uninstall) {
    if (Test-Path $launcher) {
        Remove-Item -LiteralPath $launcher -Force
        Write-Host "[OK] removed autostart: $launcher"
    } else {
        Write-Host "[i] no autostart entry found"
    }
    Stop-Watcher
    Write-Host ''
    Write-Host 'Uninstalled.'
    return
}

if (-not (Test-Path $watcher)) { throw "usb-tether-watch.ps1 not found next to install.ps1" }

# --- write the hidden launcher ---------------------------------
# NB: single-quoted here-string + placeholder -> no PowerShell escaping at all.
$tpl = @'
' Auto-start USB Tether Watcher (no visible window)
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""__WATCHER__""", 0, False
'@
$content = $tpl.Replace('__WATCHER__', $watcher)
[IO.File]::WriteAllText($launcher, $content, [Text.Encoding]::Unicode)
Write-Host "[OK] autostart installed: $launcher"

# --- start it and verify ---------------------------------------
Stop-Watcher
Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue

$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
if (Test-Path $wscript) {
    & $wscript $launcher
} else {
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList '-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$watcher`"" `
        -WindowStyle Hidden | Out-Null
}

Write-Host '[i] waiting for the watcher to come up ...'
$ok = $false
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path $pidFile) { $ok = $true; break }
}

Write-Host ''
if ($ok) {
    $wpid = (Get-Content -LiteralPath $pidFile | Select-Object -First 1)
    Write-Host "[OK] watcher is running (pid $wpid)" -ForegroundColor Green
} else {
    Write-Host "[!] watcher did not start - check $logFile" -ForegroundColor Yellow
}

Write-Host ''
Write-Host "  Log       : $logFile"
Write-Host "  Autostart : $launcher"
Write-Host '  Uninstall : powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall'
