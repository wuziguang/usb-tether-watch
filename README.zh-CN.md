# usb-tether-watch

插上安卓手机，**自动打开 USB 网络共享**。

[English](README.md)

---

## 为什么需要它

安卓不会记住你想开 USB 网络共享。拔掉数据线就没了；再插上，还得下拉通知栏 / 控制中心
手动点一次。**每次都要点。**

这是一个跑在**电脑端**的 PowerShell 守护脚本（约 3 KB），它发现手机在 ADB 上出现后，
自动把网络共享打开——一般 1~3 秒内完成。而且它会**自愈**：如果之后手机因为任何原因
（锁屏、USB 重新枚举等）掉了共享，它会在几秒内重新打开。

已在 **Redmi Turbo 4 Pro / 澎湃OS 3（`OS3.0.305.0.WOLCNXM`）/ Android 16** +
Windows 11 上实测通过。

## 关键就一条命令

```powershell
adb shell svc usb setFunctions rndis
```

真的只需要这一条。实测中两个值得记住的发现：

| 命令 | 结果 |
| --- | --- |
| `svc usb setFunctions adb,rndis` | ❌ **被静默忽略** —— 打印 `setCurrentFunctions opId:1`，实际什么都不做 |
| `svc usb setFunctions rndis` | ✅ 约 1 秒内共享起来，**而且 ADB 不会断** |

**不需要 root、不需要 Shizuku、不需要调 `TetheringManager` API。** 只设置 USB
功能就够了——网络共享框架会自己把网卡、DHCP 和 NAT 拉起来（`rndis0 - TetheredState`）。

另外做过对照实验：USB 端口复位后，手机**不会**自己恢复共享（等了 30 秒仍是断的）。
所以这个守护脚本不是多余的。

### 但它也不是每次都能一条命令搞定

同一台手机上，`rndis` 偶尔会拉不起来（实测：等了 16 秒仍是断的）。所以脚本会自动降级到：

```powershell
adb shell svc usb setScreenUnlockedFunctions rndis
adb shell svc usb setFunctions rndis
```

这会让 USB 功能切换在**解锁屏幕时**生效。上面那次实测中，降级路径 7 秒后就把共享救回来了。
两条路径都会写进日志，所以 `usb-tether-watch.log` 永远能告诉你当时用的是哪条。

## 前置条件

- Windows 10 / 11
- 能用 `adb`（在 `PATH` 里，或者改 `usb-tether-watch.ps1` 开头的兜底路径）
- 手机已开启 USB 调试，且本机已被授权
- 手机的 USB 网络共享**至少成功用过一次**，这样 Windows 就装好了 RNDIS 驱动。
  Windows 10/11 自带（"Remote NDIS Compatible Device"），一般无需额外安装。

## 安装

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

安装脚本会：

1. 往启动文件夹写一个隐藏窗口的 VBS 启动器
   （`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\USB-Tether-Watch.vbs`）；
2. 立刻把守护进程启动起来；
3. 等它的 PID 文件出现，并告诉你是否启动成功。

**不需要管理员权限。** 生成的 `.vbs` 用 UTF-16LE 编码写入，所以路径里含中文
（比如中文用户名）也能正常工作——Windows Script Host 读的是 ANSI 编码的 `.vbs`，
这是这类启动器最常见的静默失败原因。

## 卸载

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

## 工作原理

```text
每 3 秒：
  adb devices                          -> 手机在不在？
  adb shell ip -4 -o addr show rndis0  -> rndis0 有没有 IPv4 地址？
  没有 -> adb shell svc usb setFunctions rndis
```

`rndis0` 只有在共享真正运行时才会有 IPv4 地址，所以这是个很可靠的"开没开"探针——
比信 USB 功能列表靠谱得多，因为在 MIUI 上即使什么都没开，功能列表也可能显示 `rndis`。

日志：`usb-tether-watch.log`（和脚本同目录）
PID 文件：`usb-tether-watch.pid`（给 `-Uninstall` 用）

## 排错

| 现象 | 原因 / 解决 |
| --- | --- |
| 日志出现 `phone not authorized` | 在手机上点 **允许 USB 调试** |
| 日志出现 `FAILED: could not enable` | 手动跑 `adb shell svc usb getFunctions`；确认用的是 `rndis`，**不要**用 `adb,rndis` |
| 日志里什么都没有 | `adb` 路径不对，或者守护进程没在跑——看 PID 文件 |
| 平时正常但偶尔会掉 | 正常现象，脚本会自动拉回来。MIUI / 澎湃OS 上就是这样 |

## 备选：用计划任务方式运行

如果你更想用任务计划程序（好处是失败能自动重启），在**管理员**命令提示符里跑一次：

```bat
schtasks /Create /TN "USB Tether Watch" ^
  /TR "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File <完整路径>\usb-tether-watch.ps1" ^
  /SC ONLOGON /RL LIMITED /F
```

**不要两种方式同时装**——脚本里有单实例互斥锁，第二份会直接退出，但没必要装两遍。

## 许可

[MIT](LICENSE)
