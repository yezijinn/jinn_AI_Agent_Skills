---
name: android-device-qa-jinn
description: 用于 Windows/OpenCode 的安卓真机与模拟器测试技能。通过 ADB、PowerShell、UIAutomator 和截图控制设备，识别 App 页面，监控用户切换造成的前台干扰，收集 Logcat、结构化诊断日志和手机诊断文件，并可选使用只读 KernelSU 权限。适用于安装或启动 App、点击滑动输入、识别 UI、增加或审查 App 日志、复现 Bug、收集测试证据，以及用户接管手机时暂停测试。英文关键词：Android QA, ADB, PowerShell, UIAutomator, screenshots, logcat, KernelSU, foreground-app interference.
---

# Android Device QA v2

Use ADB as the execution layer and UIAutomator as the primary semantic locator. Use screenshots for visual verification. Treat the phone as a shared, potentially user-controlled device: verify the target package before and after every meaningful action, and pause if the user has taken the foreground.

## Safety and device ownership

- Start with `adb devices -l`; never assume the first device is the target.
- Before install, clear-data, uninstall, permission changes, root commands, or externally visible actions, confirm scope and require user approval when not explicitly requested.
- KernelSU/root is read-only by default. Use `su -c` only for diagnosis or pulling files that ordinary ADB cannot read. Do not change system settings, disable security, freeze input, or modify another app without explicit approval.
- Never log or collect passwords, access tokens, cookies, private messages, or unrelated user data. Redact them in app diagnostics and reports.
- Do not try to block all physical touch input on a phone the user is actively using. Prefer a dedicated test phone/emulator. On a shared phone, use the foreground guard and pause.

## Standard test-session workflow

1. Discover the device and identify its serial.

   ```powershell
   .\scripts\adb_device_qa.ps1 list
   .\scripts\adb_device_qa.ps1 root-id -Serial <serial>
   ```

2. Create a run directory and clear only the relevant evidence. Keep a unique run-id in every artifact and app log.

   ```powershell
   .\scripts\adb_device_qa.ps1 clear-logcat -Serial <serial>
   .\scripts\adb_device_qa.ps1 install -Serial <serial> -Apk .\app-debug.apk
   .\scripts\adb_device_qa.ps1 launch -Serial <serial> -Package <package>
   .\scripts\adb_device_qa.ps1 collect -Serial <serial> -Package <package> -OutDir .\artifacts\run-<id>
   ```

3. Before each action, inspect the foreground app. If it is not the target package, report `USER_INTERFERENCE`, save evidence, and stop the flow.

   ```powershell
   .\scripts\adb_device_qa.ps1 foreground -Serial <serial>
   .\scripts\adb_device_qa.ps1 guard -Serial <serial> -Package <package> -DurationSec 10
   ```

4. Dump UI XML and locate controls using text, resource-id, or content-desc. Use coordinates only from the current dump.

   ```powershell
   .\scripts\adb_device_qa.ps1 snapshot -Serial <serial> -OutDir .\artifacts\run-<id>\step-01
   python .\scripts\query_ui.py .\artifacts\run-<id>\step-01\ui-*.xml --text "Login"
   .\scripts\adb_device_qa.ps1 tap -Serial <serial> -X <x> -Y <y>
   ```

5. After each action, verify foreground package/activity, UI state, screenshot, and expected result. Do not continue after a guard failure, crash, ANR, or unexpected external app.

6. At the end, collect logcat, app diagnostics, crash buffer, screenshots, UI XML, foreground evidence, device metadata, and a short manifest of the run. If UIAutomator is killed or returns no XML, continue collecting the other evidence, record `UiAvailable=false` and the exact error, and use screenshot/vision or app-specific accessibility APIs as fallback.

## App diagnostic logging

When the user asks to add detailed app logs, inspect the project first and read [references/diagnostic-logging.md](references/diagnostic-logging.md) for the matching Kotlin/Java/Compose/Flutter pattern.

Implement logging in the app itself, not only from the outside:

- Add a stable run-id and build/version/device context.
- Log lifecycle, navigation, user-intent boundaries, important state transitions, background jobs, network result summaries, exceptions, and timing.
- Use structured lines or JSON with timestamp, level, event, screen, thread, and safe fields.
- Add uncaught-exception and crash breadcrumbs where the framework allows it.
- Use bounded rolling files and avoid blocking the UI thread.
- Redact credentials, tokens, cookies, personal messages, and full request bodies.
- Prefer an app-owned diagnostic directory and provide an explicit export/copy-to-Download action for a human-readable bundle.

Do not blindly add logs everywhere. Select high-value boundaries, preserve behavior, build the app, and run a focused flow to prove the logs are emitted.

## Storage and pulling diagnostics

Use the app's scoped external directory for routine logs, for example:

```text
/storage/emulated/0/Android/data/<package>/files/diagnostics/
```

Use a shared Download path only for an explicit exported diagnostic bundle. On newer Android versions, do not assume the app can write arbitrary paths under `/storage/emulated/0/`; use the app's storage API or MediaStore. Pull files with:

```powershell
.\scripts\adb_device_qa.ps1 pull -Serial <serial> -RemotePath /sdcard/Download/<package>-diagnostics -OutDir .\artifacts\run-<id>
```

If ordinary ADB cannot read a path and root is available, the script may use a read-only `su -c` copy to a temporary shell-readable location. Preserve the original path in the report.

## KernelSU/root diagnostics

Run `root-id` first. Distinguish these states:

- `ROOT_AVAILABLE`: `su -c id` returns uid 0.
- `SU_PRESENT_NOT_ROOT`: `su` exists but does not return uid 0.
- `ROOT_UNAVAILABLE`: command denied, missing, or timed out.

Use root only for targeted read-only collection such as app-private diagnostic files, process state, or system evidence requested by the user. Never claim root was used unless the command output proves it.

## Foreground interference policy

The user may touch the phone while the test runs. Detect interference using foreground package/activity, not only the screenshot. Pause when:

- the foreground package is not the target package;
- the target activity disappears unexpectedly;
- a system permission dialog or keyboard changes the expected flow;
- the screen is locked, rotated unexpectedly, or the device becomes offline.

Save a screenshot, UI XML, foreground output, and timestamp on interruption. Ask whether to resume, reset to the target state, or stop. Do not silently relaunch over the user's current app.

## Failure diagnosis

- No device/unauthorized/offline: report the exact serial state and ask the user to unlock/authorize; do not repeatedly reset ADB.
- Element missing: re-dump, inspect scrollable nodes, scroll once, and retry. Consider WebView, Compose semantics, canvas, or a custom renderer.
- UIAutomator killed/unsupported: preserve the UI dump error, do not discard the rest of the evidence, and fall back to screenshot/vision plus foreground activity checks.
- Tap has no effect: check current foreground, enabled/clickable state, bounds, overlay, keyboard, and a fresh screenshot.
- Crash or ANR: collect package-scoped logcat, crash buffer, app diagnostic files, last screenshot, and UI XML; separate evidence from hypothesis.
- User interference: stop with `USER_INTERFERENCE`, preserve evidence, and wait for direction.

## Bundled tools

- `scripts/adb_device_qa.ps1`: device discovery, APK installation, launch, foreground inspection, root check, logcat clearing, screenshots, UI XML, snapshots, diagnostic collection, remote pulling, and foreground guard.
- `scripts/query_ui.py`: standard-library XML query tool returning matching nodes and center coordinates.
- `references/diagnostic-logging.md`: framework-specific guidance for adding safe, structured, file-backed app diagnostics.
