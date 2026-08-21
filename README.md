# jinn_AI_Agent_Skills

个人自建的 AI Agent（OpenCode）技能仓库。每个 skill 为一个独立目录，内含 `SKILL.md` 及配套资源（脚本、参考文档、Agent 配置）。

## 技能列表

| 技能 | 说明 |
| --- | --- |
| `skills/android-device-qa-jinn` | 安卓真机与模拟器测试。通过 ADB、PowerShell、UIAutomator 与截图控制设备，识别 App 页面，监控前台干扰，收集 Logcat 与结构化诊断日志，支持只读 KernelSU 权限。适用于安装/启动 App、点击滑动输入、UI 识别、日志增改、Bug 复现、证据收集。 |
| `skills/android-reverse-jinn` | 安卓 APK 逆向还原完整工作流。支持资源还原、DEX 反编译、Smali 改造、重打包签名、so 库分析、Frida Hook。 |
| `skills/commit-push-pr-release-jinn` | 安全提交、推送、创建 PR 与 Release，含文档整理与 `.gitignore`。Tag 强制 `vYYYYMMDD` 格式，资产文件名纯英文，README 与 Release Notes 中英双语。 |

## 安装使用

将需要使用的 skill 目录复制到 OpenCode 技能目录（默认 `~/.config/opencode/skills/`）即可：

```bash
cp -r skills/<skill-name> ~/.config/opencode/skills/
```

## 目录结构

```
skills/
  <skill-name>/
    SKILL.md          # 技能定义（名称、描述、触发词、工作流）
    scripts/          # 辅助脚本
    references/       # 参考文档
    agents/           # 子 Agent 配置
```

## 新增技能

将新技能目录放入 `skills/` 下，并更新上方技能列表，然后提交推送即可。
