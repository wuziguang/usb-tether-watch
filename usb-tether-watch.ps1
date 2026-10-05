# ============================================================
#  usb-tether-watch.ps1
#
#  Auto-enable USB tethering as soon as an Android phone is
#  plugged into this Windows PC.
#
#  Verified on:
#    Redmi Turbo 4 Pro / HyperOS 3 (OS3.0.305.0.WOLCNXM) / Android 16
#    Windows 10 / 11
#
#  Needs: adb in PATH (or set $adb below), USB debugging authorised.
#  Does NOT need: root, Shizuku, TetheringManager, admin rights.
#
#  See README.md
# ============================================================

param(
    [int]$PollSeconds = 3,
    [switch]$Console
)

$ErrorActionPreference = 'Continue'

# --- single instance guard -------------------------------------
$mutex = New-Object System.Threading.Mutex($false, 'Local\UsbTetherWatch')
if (-not $mutex.WaitOne(0)) {
    Write-Host 'usb-tether-watch is already running.'
    exit 0
}

# --- locate adb ------------------------------------------------
$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) { $adb = 'C:\Windows\adb.exe' }   # <- change if your adb lives elsewhere
if (-not (Test-Path $adb)) { throw "adb not found. Set the path in this script." }

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path $here 'usb-tether-watch.log'
$pidFile = Join-Path $here 'usb-tether-watch.pid'

function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try { Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 } catch { }
    if ($Console) { Write-Host $line }
}

function Get-AdbState {
    $out = ((& $adb devices 2>&1) -join "`n")
    if ($out -match "\tdevice\b")       { return 'ok' }
    if ($out -match "\tunauthorized\b") { return 'unauthorized' }
    return 'none'
}

function Test-TetherUp {
    # rndis0 only gets an IPv4 address while USB tethering is really running
    $out = ((& $adb shell "ip -4 -o addr show rndis0 2>/dev/null" 2>&1) -join "`n")
    return ($out -match 'inet ')
}

function Wait-Up([int]$seconds) {
    for ($i = 0; $i -lt $seconds; $i++) {
        Start-Sleep -Seconds 1
        if (Test-TetherUp) { return $true }
    }
    return $false
}

function Enable-Tether {
    Write-Log "tethering is DOWN -> enabling"

    # THE command that works. Note: "adb,rndis" is silently ignored by MIUI.
    & $adb shell "svc usb setFunctions rndis" | Out-Null
    if (Wait-Up 15) { Write-Log "OK: USB tethering is UP"; return $true }

    # fallback for builds that only apply the function on screen-unlock
    Write-Log "attempt 1 failed, setting screen-unlocked functions then retrying"
    & $adb shell "svc usb setScreenUnlockedFunctions rndis" | Out-Null
    & $adb shell "svc usb setFunctions rndis" | Out-Null
    if (Wait-Up 15) { Write-Log "OK: USB tethering is UP (via screen-unlock path)"; return $true }

    Write-Log "FAILED: could not enable USB tethering automatically"
    return $false
}

# --- main loop -------------------------------------------------
Set-Content -LiteralPath $pidFile -Value $PID -Encoding ASCII

try {
    Write-Log "watcher started (pid=$PID, adb=$adb, poll=${PollSeconds}s)"
    $prev     = 'init'
    $failures = 0

    while ($true) {
        $st = Get-AdbState
        if ($st -ne $prev) {
            Write-Log "adb state: $prev -> $st"
            if ($st -eq 'unauthorized') {
                Write-Log "phone not authorized: tap 'Allow USB debugging' on the phone"
            }
            $prev = $st
            if ($st -eq 'ok') { $failures = 0 }
        }

        if ($st -eq 'ok') {
            Start-Sleep -Seconds 2
            if (-not (Test-TetherUp)) {
                if (Enable-Tether) {
                    $failures = 0
                } else {
                    $failures++
                    Write-Log "failure count = $failures; backing off 30s"
                    Start-Sleep -Seconds 30
                }
            } else {
                $failures = 0
            }
        }

        Start-Sleep -Seconds $PollSeconds
    }
}
finally {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    try { $mutex.ReleaseMutex() } catch { }
}
