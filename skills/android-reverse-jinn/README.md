# Android 逆向还原代码 Skill

适用于 **OpenCode** 的标准 Claude/Agent Skills 格式技能，用于系统化地对安卓 APK 进行逆向分析、源码还原、资源解码、原生 so 分析、重打包签名与动态调试。

## 安装到 OpenCode

1. 把本目录（`android-reverse/`）复制到用户级 skill 目录：

   ```bash
   mkdir -p ~/.config/opencode/skill
   cp -r android-reverse ~/.config/opencode/skill/
   ```

2. 重启 OpenCode，在启用 skills 后即可通过自然语言触发，例如：
   - "对 xxx.apk 逆向还原代码"
   - "用 jadx 反编译这个 apk"
   - "解码资源 + Smali 重打包"

## 目录结构

```
android-reverse/
├── SKILL.md        # 技能主文件（YAML frontmatter + 工作流程）
├── README.md       # 本说明
└── scripts/
    ├── extract.sh       # 阶段 0~1：确认目标 + apktool 解码 + 提取 so
    ├── decompile.sh     # 阶段 2：jadx 反编译（含 multi-dex 检测）
    ├── analyze_so.sh    # 阶段 3：so 库分析（strings + readelf/rabin2 导出符号，--deep 深度分析）
    └── repack_sign.sh   # 阶段 5：重打包 → 对齐 → 签名 → 验证
```

## 技能能力

| 阶段 | 说明 | 核心工具 |
|------|------|----------|
| 保护识别 | 检测加固/加壳/混淆 | apkid |
| 资源还原 | 解码 Manifest / res / smali | apktool |
| Java 源码还原 | 反编译 DEX 为可读 Java | jadx |
| 批量静态分析 | 导出权限/组件/字符串/调用关系 | androguard |
| 原生 so 分析 | 反汇编 lib/*.so（开源） | radare2（r2/rabin2）+ strings |
| 动态调试 | 运行时 Hook / 方法拦截 | Frida / objection |
| 重打包签名 | 修改后重新打包并签名 | apktool + apksigner |
| 复刻可编译项目 | 把逆向结果整理成可导入 Android Studio 的工程（可选进阶） | JADX（`--export-gradle`）/ AndroidProjectCreator / apktool / 反混淆 simplify / Android Studio |

> 原生 so 分析以 **radare2（开源、命令行适配）为主路径**。付费 / 非开源 / 不适合命令行自动操作的高级逆向工具
> （IDA Pro、Ghidra、Binary Ninja）已作为**备选手动补充**写入 SKILL.md「阶段 3 补充」小节，仅供用户在本机手动
> GUI/批处理调用，**Agent 默认不自动调用**。

## 针对本项目

应用可能同时含 Java 层与原生 C/C++ 层，逆向时三层目标（资源/Java/so）均需覆盖，流程已内置。
**开始前建议先做保护识别**：`apkid 目标.apk` 判断是否加固/加壳。若检测到 packer（加固壳），直接 jadx 会得到壳代码，需先考虑脱壳或改走动态调试；若为普通 dex 则可直接走静态分析主线（详见 SKILL.md 阶段 0）。

> 若为全新工作区、**无历史拆解产物**，逆向从零开始，产物目录（`apk_extract/`、`jadx_out/`、`libs/`、`patched/`）由脚本在首次执行时新建；若该目录此前已跑过逆向、残留过产物（如 `dex_cache/`、`res_extract/`），可复用或按需清理以免覆盖手动修改。