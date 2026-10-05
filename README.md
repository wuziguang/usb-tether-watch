# usb-tether-watch

Auto-enable **USB tethering** on an Android phone the moment it is plugged into a
Windows PC.

[中文说明](README.zh-CN.md)

---

## The problem

Android does not remember that you want USB tethering. Unplug the cable and it is
gone; plug it back in and you have to pull down the notification shade / control
centre and re-enable it. Every. Single. Time.

This is a ~3 KB PowerShell watcher that runs on the **PC**, notices the phone
appear on ADB and switches tethering on — typically within 1–3 seconds. It also
self-heals: if the phone drops tethering later (screen lock, USB re-enumeration,
whatever), it turns it back on.

Verified on **Redmi Turbo 4 Pro, HyperOS 3 (`OS3.0.305.0.WOLCNXM`), Android 16**,
Windows 11.

## The one command that matters

```powershell
adb shell svc usb setFunctions rndis
```

That is genuinely all it takes. Two findings from testing that are worth knowing:

| Command | Result |
| --- | --- |
| `svc usb setFunctions adb,rndis` | ❌ **silently ignored** — prints `setCurrentFunctions opId:1`, changes nothing |
| `svc usb setFunctions rndis` | ✅ tethering up in ~1 s, **and ADB keeps working** |

You do **not** need root, Shizuku, or the `TetheringManager` API. Setting the USB
gadget function is enough — the tethering framework brings up the interface, DHCP
and NAT by itself (`rndis0 - TetheredState`).

Also confirmed by a control test: after a USB port reset the phone does **not**
restore tethering on its own — 30 seconds later it was still down. So this watcher
is not redundant.

### It is not always that simple

On the same phone, `rndis` alone occasionally fails to bring the interface up
(observed: still down after 16 s). The watcher therefore falls back to:

```powershell
adb shell svc usb setScreenUnlockedFunctions rndis
adb shell svc usb setFunctions rndis
```

which makes the USB function switch apply when the screen is unlocked. In the
test above that recovered tethering 7 seconds later. Both paths are logged, so
`usb-tether-watch.log` always tells you which one was needed.

## Requirements

- Windows 10 / 11
- `adb` available (in `PATH`, or edit the fallback path at the top of
  `usb-tether-watch.ps1`)
- USB debugging enabled on the phone and this PC authorised
- The phone's USB tethering must have worked at least once, so Windows has the
  RNDIS driver. Windows 10/11 ships one ("Remote NDIS Compatible Device"), so
  usually there is nothing to install.

## Install

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

The installer:

1. writes a hidden VBS launcher into your Startup folder
   (`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\USB-Tether-Watch.vbs`),
2. starts the watcher immediately,
3. waits for its PID file and tells you whether it came up.

**No administrator rights are needed.** The generated `.vbs` is written as
UTF-16LE so that paths containing non-ASCII characters (a Chinese user name, for
example) work — Windows Script Host reads ANSI `.vbs` files, which is the classic
way these launchers silently break.

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

## How it works

```text
every 3 s:
  adb devices                     -> is the phone there?
  adb shell ip -4 -o addr show rndis0
                                  -> does rndis0 have an IPv4 address?
  if no  -> adb shell svc usb setFunctions rndis
```

`rndis0` only has an IPv4 address while tethering is actually running, which makes
it a reliable "is it on?" probe — much better than trusting the USB function list,
which on MIUI reports `rndis` even when nothing is up.

Log: `usb-tether-watch.log` (next to the script).
PID file: `usb-tether-watch.pid` (used by `-Uninstall`).

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Log says `phone not authorized` | Tap **Allow USB debugging** on the phone |
| Log says `FAILED: could not enable` | Run `adb shell svc usb getFunctions`; make sure you use `rndis` and **not** `adb,rndis` |
| Nothing in the log at all | `adb` path wrong, or the watcher is not running — check the PID file |
| Usually works, but drops sometimes | Expected; the watcher re-enables it. This is normal on MIUI/HyperOS |

## Alternative: run it as a scheduled task

If you prefer the Task Scheduler over the Startup folder (it can auto-restart on
failure), run this once in an **administrator** prompt:

```bat
schtasks /Create /TN "USB Tether Watch" ^
  /TR "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File <full path>\usb-tether-watch.ps1" ^
  /SC ONLOGON /RL LIMITED /F
```

Do not use both methods at once — the script has a single-instance mutex, so the
second copy just exits, but there is no reason to install it twice.

## License

[MIT](LICENSE)
