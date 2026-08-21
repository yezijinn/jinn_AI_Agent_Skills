---
name: android-reverse-jinn
description: >-
  安卓 APK 逆向还原代码的完整工作流。当用户需要对 APK 进行逆向分析、还原 Java/Kotlin 源码、
  解码资源文件、反编译原生 so 库、重打包签名或动态调试时使用。覆盖从静态分析到动态调试的
  全流程，支持资源还原、DEX 反编译、Smali 改造、重打包签名、so 库分析、Frida Hook。
  触发词：逆向、反编译、还原代码、apk 分析、jadx、apktool、smali、so 库、frida、hook。
metadata:
  allowed-tools:
    - Bash
    - Read
    - Glob
    - Grep
    - Edit
    - Write
---

# 安卓 APK 逆向还原代码

安卓应用逆向工程的系统化工作流。用于分析一个 `.apk` 包，还原其 Java/Kotlin 逻辑、
解码资源、分析原生层，并在必要时修改、重打包和重签名。

## 环境前置

在开始前，确认以下工具已在电脑上可用（版本建议）：

| 工具 | 用途 | 安装/检查命令 |
|------|------|--------------|
| JDK 17+ | 运行环境（jadx/apktool 需要） | `java -version` |
| jadx | Java/Kotlin 源码反编译（首选命令行 CLI，适配 OpenCode；亦支持导出 Gradle 工程骨架） | `jadx --version` |
| apktool | 解码资源 / Smali / 重打包（PC 运行时需 `java -jar` 或 PATH 安装；`scripts/` 下的 `extract.sh`/`repack_sign.sh` 已自动适配：优先 PATH 命令，否则自动探测脚本上级/当前目录的 `apktool*.jar` 用 `java -jar` 调用，可用 `APKTOOL_JAR` 环境变量显式指定 jar 路径） | `apktool --version` |
| unzip | 查看 APK 原始包结构 | `which unzip` |
| zipalign | 重打包后 zip 对齐（签名前） | `zipalign`（位于 SDK build-tools） |
| radare2（r2 框架） | 反汇编/解析 lib/*.so 原生库（开源） | `r2 --version`、`rabin2 -v` |
| Frida + objection | 动态 Hook / 运行时分析 | `frida --version` |
| apksigner | 重打包后签名（Android SDK build-tools） | `apksigner --version` |
| strings / binwalk | 提取字符串、探测固件结构 | `which strings binwalk` |
| apkid | 保护识别（加固/加壳/混淆检测） | `apkid --version`（`pip install apkid`） |
| androguard | 批量静态分析（权限/组件/字符串/调用关系） | `python -c "import androguard; print(androguard.__version__)"`（`pip install androguard`） |
| 反混淆工具（simplify 等） | 字符串解密、控制流还原，恢复混淆的变量名/方法名/逻辑 | `simplify --version`（`brew install simplify` 或源码编译，可选） |
| Android Studio / VS Code + 插件 | 最终人工整理、补全并编译成本地可运行项目（`src`/`res`/`build.gradle`） | 本机 IDE，非命令行依赖，Agent 生成骨架后交给用户整理编译 |

> 若某些进阶工具（radare2/Frida）未安装，可明确告知用户需要先安装，本流程不会阻断在静态分析阶段。

## 工作流程

一个 APK 逆向通常分 **4 层目标**，按优先级推进：

### 阶段 0：确认目标与定级
1. 确认 APK 路径、大小（`ls -lh xxx.apk`）。若 APK 含 `lib/` 目录（原生 so 库）或 `assets/` 下有大体积数据文件（模型/图纸/资源包等），很可能同时含 Java 层与原生层，3 层目标都要做。
2. **保护识别（重要）**：先判断 APK 是否被加固/加壳/混淆，决定后续策略。
   ```bash
   apkid 目标.apk
   ```
   - 若输出含 `packer`（如腾讯乐固/梆梆/爱加密/360 等）或明显加壳迹象，说明是**加固壳**：直接 jadx 反编译会得到加密壳代码、难以还原真实逻辑，需告知用户可能要先**脱壳**，或改用**动态调试（阶段 4）抓取运行时解密后的 dex**。
   - 若为普通 `dex`（无 packer 标记），则可直接走阶段 1~2 正常反编译。
   - 同时可 `unzip -l 目标.apk | grep -E 'assets/(classes|.*dex$)|lib/.*\.so'` 快速浏览是否含 so 与多 dex。
3. 电脑为全新环境，无任何历史拆解产物；确认本次逆向的输出目录（`<workdir>/`）为空后，按下方「逆向产物目录规划」从零开始新建 `apk_extract/`、`jadx_out/`、`libs/`、`patched/`。

### 阶段 1：资源还原（apktool）
```bash
apktool d -f 目标.apk -o out_dir
```
- `-f` 为 `--force` 强制覆盖输出目录；首次执行无需顾虑，重跑前请确认 `out_dir/` 内无手动修改（否则会被静默覆盖）。
- 得到 `AndroidManifest.xml`（明文）、`res/`（布局/图片/字符串）、`smali/`（可读的 Dalvik 字节码）。
- 查看清单：`cat out_dir/AndroidManifest.xml`，关注 `application` 入口、`permission`、`activity`/`service`/`receiver` 组件。
- **批量静态分析（可选，androguard，纯 Python 命令行）**：如需一次性导出权限、组件、字符串与调用关系，可用 androguard 而不需逐行 grep：
  ```bash
  python -c "from androguard.misc import AnalyzeAPK; a,d,dx=AnalyzeAPK('目标.apk'); \
  [print(p) for p in a.get_permissions()]"                       # 全部权限清单
  python -c "from androguard.misc import AnalyzeAPK; a,d,dx=AnalyzeAPK('目标.apk'); \
  [print(x) for x in a.get_activities()+a.get_services()+a.get_receivers()+a.get_providers()]"  # 全部四大组件
  # 更完整的调用关系/方法分析可直接写 androguard 脚本（dx.get_methods() 等）做批量导出
  ```
  - 适合脚本化/批量抽取，作为 apktool 解码后 `grep` 的补充手段；若仅看单个类逻辑，直接用 grep jadx 源码更快。

### 阶段 2：Java/Kotlin 源码还原（jadx）
```bash
jadx -d jadx_out 目标.apk
# GUI 版：jadx-gui 目标.apk
```
- 从 `jadx_out/sources/**` 得到可读的 Java 源码，快速浏览类结构与逻辑。
- 用 `grep` 定位关键逻辑：`grep -rn "关键方法名" jadx_out/sources/`。
- 若 jadx 反编译失败的类，回退到 apktool 的 `smali/` 人工分析字节码。

### 阶段 3：原生 so 库分析（radare2, 开源）
- 先看目标架构：`unzip -l 目标.apk | grep 'lib/'`，找到 `lib/arm64-v8a/`、`lib/armeabi-v7a/` 等。
- 解出 so：`unzip 目标.apk 'lib/*.so' -d libs/`
- 用 **radare2**（r2，完全开源）对 `.so` 做静态分析。r2 是命令行驱动，天然适配 OpenCode 终端，常用操作如下：

```bash
# ① 快速浏览二进制信息 / 架构 / 导出符号（rabin2，无需进入交互）
rabin2 -I libs/lib/arm64-v8a/libxxx.so        # 文件信息、架构、字节序
rabin2 -E libs/lib/arm64-v8a/libxxx.so        # 列出导出符号（可 grep 定位 native 方法）
rabin2 -S libs/lib/arm64-v8a/libxxx.so        # 节表
rabin2 -z libs/lib/arm64-v8a/libxxx.so        # 字符串（等价增强版 strings）

# ② 深度反汇编 / 交叉引用分析（r2，-A 自动分析后进入）
r2 -A libs/lib/arm64-v8a/libxxx.so
#   进入 r2 后常用命令：
#   aaa      # 全量自动分析（函数、引用、类型）
#   afl      # 列出所有函数
#   s sym.<函数名>   # 跳到指定函数
#   pdf      # 反汇编当前函数
#   axt @ sym.<函数名>   # 查看该函数被谁调用（xref 交叉引用）
#   is       # 列出所有符号 / 导入导出
#   iz       # 字符串列表
#   ?v FLAG   # 计算地址，随后可 s 跳转 / 打断点
#   退出：q
```

- 定位 native 方法（对照 jadx 中的 `System.loadLibrary` / native 声明）：`rabin2 -E libs/lib/arm64-v8a/*.so | grep -i 'java_\|JNI\|关键符号'`
- 辅助：`strings xxx.so | grep -i '关键符号'` 快速定位 export。

> radare2 为纯开源（GPL），安装方式：`git clone https://github.com/radareorg/radare2 && cd radare2 && ./sys/install.sh`，或各发行版包管理器 `sudo apt install radare2`。
> **Rizin 备选（等价 fork）**：若偏好 radare2 的活跃分支 Rizin，可用 `rizin`/`rz-bin`（命令 `rizin -A xxx.so`、`rz-bin -I/-E/-S/-z xxx.so`），命令参数与 rabin2 高度同源，可作等价的纯开源命令行替代。

### 阶段 3 补充：备选手动工具（付费 / 非开源 / 不适合命令行自动操作）
以下工具**仅供用户手动调用，Agent 不自动调用**。它们多为 GUI 优先或授权受限的付费商业软件，
与 OpenCode 纯命令行环境的契合度低，因此仅作为 **radare2 主路径的备选补充**，用于用户希望
在图形界面里做更精细交互式逆向时的场景。**优先原则：Agent 一律使用开源工具（radare2/rabin2），
仅在用户明确要求手动操作时才提示以下备选项。**

- **IDA Pro（付费，GUI 优先，授权多绑定单机 GUI）**
  - 适用场景：用户本机已安装并激活 IDA，希望对关键 so 做精细的伪代码（F5 Hex-Rays）、类型还原、复杂交叉引用分析。
  - 手动入口示例（非自动调用，产物为 `.idb/.i64` 二进制数据库，不可直接 grep）：
    ```bash
    # 无界面/批处理模式：自动分析后退出（受授权与 GUI 依赖限制，可能不可用）
    ida64 -A -c target.so
    # headless 模式 + 自动运行 IDAPython 脚本导出结果
    idat64 -A -S"export_funcs.py" target.so
    ```
  - 说明：`-A` 为 autonomous（分析完成后退出）；`-S"脚本"` 自动执行 IDC/IDAPython 脚本；
    `idat` 为无 GUI 版本。这些模式通常**不适合** Agent 自动调用（加载大 so 慢、授权可能限制
    headless、输出为二进制数据库），推荐用户在 GUI 中手动打开 `.so` 做精细分析。
- **Ghidra（开源但 Java/Swing GUI 优先，命令行 headless 模式存在但脚本较复杂）**
  - 适用场景：用户偏好 NSA 团队的免费逆向套件，做函数还原/反编译。
  - 手动入口示例（可选）：`analyzeHeadless <projdir> <proj> -import target.so -postScript CheckTypes.java -deleteProject`。因配置成本较高，一般作为手动 GUI 使用。
- **Binary Ninja（付费，GUI/脚本 API）**
  - 适用场景：用户有授权且偏好其反编译器/脚本化可视化。
  - 手动入口示例（可选）：`binaryninja -A target.so` 或 `bn` Python API。同样以手动 GUI 使用为主。

> 备选工具录入原则：**Agent 不得将上述付费/ GUI 工具作为自动依赖**。若用户未装这些工具或未明确要求，
> 一律走 radare2 开源主路径；仅当用户本机已装并主动要求手动精调时，才给出对应手动命令示例。

### 阶段 4：动态调试 / Hook（Frida，可选，需 root/模拟器）
```bash
# 追加 Hook 脚本（objection 更省事）
objection -g 包名 explore
# 或编写 frida JS 脚本 hook 指定方法
frida -U -f 包名 -l hook.js
```

### 阶段 5：修改 → 重打包 → 对齐 → 签名 → 验证（需要改行为时）
```bash
# 修改 smali 或资源后，用 apktool 重新打包
apktool b out_dir -o patched.apk
```
- `apktool b` 的 `-f` 为强制覆盖输出 APK；若 `patched.apk` 已存在，不加 `-f` 会报错，加 `-f` 则直接覆盖。建议首次打包时确认输出路径无同名文件，或显式使用 `-f` 避免交互提示。
# zip 对齐（签名前必须做，否则部分场景安装失败）
zipalign -p -f 4 patched.apk aligned.apk

# 生成签名 keystore（若无）
keytool -genkey -v -keystore debug.keystore -storepass android -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000

# 用 apksigner 签名
apksigner sign --ks debug.keystore --ks-pass pass:android --out signed.apk aligned.apk

# 校验签名结果
apksigner verify --print-certs signed.apk

# 安装验证（如需真机/模拟器验证）
adb install -r signed.apk
```

> 说明：`zipalign` 与 `apksigner` 均位于 Android SDK 的 `build-tools/` 下，需先 `export PATH=$PATH:$ANDROID_HOME/build-tools/<版本>`。
> 安装前若报签名异常，先 `adb uninstall 包名` 再装，避免签名不匹配导致安装失败。

### 阶段 6：复刻为可编译的完整 Android 项目（还原工程，可选进阶）

> 阶段 1~5 产出的是**分析/反编译资料**（源码快照、资源、so、伪代码），本阶段把前三阶段得到的
> 伪代码、反编译代码、资源等**进一步整理成一个可导入 Android Studio / IntelliJ 并尝试编译运行的
> 完整工程**。属于可选进阶，适用于用户希望"把逆向结果复刻成项目"的场景。

#### 6.1 还原难度等级（先对齐预期）
向用户说明"能还原到什么程度"，避免过度承诺：

| 还原等级 | 可行度 | 说明与典型做法 |
|---|---|---|
| L1 可读源码 | 较高 | JADX + Apktool 反编译即达，得到可读 Java/Kotlin 伪代码与资源 |
| L2 接近原始项目结构 | 中等 | AndroidProjectCreator / JADX 导出 Gradle 骨架 + 手动整理目录 |
| L3 可直接编译运行 | 较低 | 大量人工修复 + 反混淆，洗掉重复/混淆类与方法 |
| L4 完全等同原项目 | 几乎不可能 | 需原始源码、原始构建配置（gradle 版本/依赖/签名），逆向无法还原 |

#### 6.2 四步流程（复刻主线）
1. **取代码与资源**：`jadx -d jadx_out 目标.apk`（Java/Kotlin 源码）+ `apktool d 目标.apk -o apk_extract`（Manifest/res/smali）——阶段 1、2 的产物即为此步输入。
2. **生成工程骨架**：把源码与资源组装成标准 Android Gradle 结构（`app/src/main/java|res|AndroidManifest.xml` + `build.gradle`）。
   - 方式 A（推荐）：JADX 原生导出 `jadx --export-gradle`，一键生成可导入的 Gradle 骨架。
   - 方式 B：AndroidProjectCreator（综合反编译器输出 → 汇聚成标准 Android Studio 项目目录）。
   - 方式 C：人工从 `jadx_out/` + `apk_extract/res` 手工搬运到 `app/src/main/`。
3. **人工清理/重命名/补全**：删除混淆保留类、修路径、把 `smali` 语义还原到 Java、补依赖与 `build.gradle` 的 `compileSdk`/`minSdk`、加缺失的 `res`。
4. **IDE 修复编译**：把生成的工程交给 **Android Studio / VS Code + Kotlin/Java 插件**，逐条修复编译错误（缺失资源、API 差异、混淆方法），直至 `./gradlew assembleDebug` 通过。

#### 6.3 涉及工具（对应环境前置表）
- **JADX 工程导出**：`jadx --export-gradle -d project/ 目标.apk` → 生成 Gradle 骨架。
- **AndroidProjectCreator**：合并多反编译器输出，产出可导入的 Android Studio 工程目录。
- **Apktool**：还原布局/图片/字符串/AndroidManifest（阶段 1 已有，作为资源来源）。
- **反混淆工具（simplify 等）**：对混淆的字节码做字符串解密、控制流还原，恢复被混淆的变量名/方法名/逻辑，提升 L3 可行度。
- **Android Studio / VS Code + 插件**：最终人工整理补全并编译，非命令行依赖。

#### 6.4 产出位置
按「逆向产物目录规划」统一落入 `project/`：Gradle 工程骨架 / 整理后的 `src + res + build.gradle`。
可在 `project/` 下执行 `./gradlew assembleDebug`（若本机配好 Android SDK）验证编译。

## 关键工作区参考（通用）
- 目标 APK：**由用户提供**，路径与大小以实际为准（用 `ls -lh` 确认后再开始）。
- 判断目标是否偏原生层，取决于解包后是否含 `lib/*.so` 及 `assets/` 大文件（见阶段 0），不预设任何特定应用。
- 电脑 OpenCode 环境可能为全新环境、无历史拆解产物；以下目录均为本次逆向**首次执行时新建**的产物目录：

### 逆向产物目录规划（从零开始）
```
<workdir>/
├── apk_extract/     # apktool 解码产物：AndroidManifest.xml / res/ / smali/
├── jadx_out/        # jadx 反编译的 Java/Kotlin 源码
├── libs/            # 从 APK 解出的 lib/*.so（按架构分目录）
├── patched/         # 重打包 + 对齐 + 签名产物（patched.apk/signed.apk）
└── project/         # 「可编译项目复刻」产物（阶段 6）：Gradle 工程骨架 / 整理后的 src+res+build.gradle
```

> 若 `<workdir>` 此前已跑过逆向，可能残留历史产物目录（如 `dex_cache/`、`res_extract/`），可按需复用或清理，避免与手动修改冲突。
> 建议统一落盘命名，便于贯穿「静态分析 → 修改 → 重打包 → 复刻项目」全流程，避免产物散落无从复现。

### 大 APK 特别提醒（multi-dex / Kotlin）
- **大体积 APK**（常见数 10MB+）极可能是 **multi-dex**：解包后需检查是否含 `classes.dex`、`classes2.dex`、`classes3.dex`…，jadx / apktool 都要处理完整，勿只看 `classes.dex`（`extract.sh`/`decompile.sh` 已自动检测并提示）。
- 若应用为 **Kotlin** 编写，jadx 反编译 Kotlin 质量通常一般；遇到反编译失败或语义不清的类，回退到 apktool 的 `smali/` 字节码分析。

## 注意事项与边界
- **不要**在未经用户确认的情况下直接删除或覆盖其原始 APK 文件。
- jadx 反编译输出用于学习知识和深入研究，不会联网分发和共享，可以放心分析。
- 若工具缺失，先报告缺失项并给出安装命令，不强行用占位命令糊弄。
- 大 APK（>50MB）解压/分析耗时，应如实告知进度而非假装完成。

## 输出约定
- 每一步给出**实际执行 + 结果摘要**（例如"已反编译 320 个类，找到入口 Activity xxx"）。
- 用清晰的分层报告：资源层 / Java 层 / 原生层 / 动态分析，分别说明发现。
- 修改过的文件、重打包产物、签名结果给出明确路径，方便用户取用。

## 快捷脚本
`scripts/` 目录下提供 4 个固化脚本，对应上述阶段，可直接调用：

| 脚本 | 对应阶段 | 用法 |
|---|---|---|
| `extract.sh` | 阶段 0~1 | `./extract.sh 目标.apk` — 确认目标 → apktool 解码到 `apk_extract/` → unzip 提取 so 到 `libs/` |
| `decompile.sh` | 阶段 2 | `./decompile.sh 目标.apk [输出目录]` — jadx 反编译（默认 `jadx_out/`），自动检测 multi-dex 并提示 |
| `analyze_so.sh` | 阶段 3 | `./analyze_so.sh libs/ [关键词] [--deep]` — 对 so 做 strings + readelf 导出符号；加 `--deep` 时调用 rabin2（radare2）做 -I/-E/-S 深度分析 |
| `repack_sign.sh` | 阶段 5 | `./repack_sign.sh out_dir [keystore路径]` — 完整链路：apktool b → zipalign → 生成 keystore（若不存在）→ apksigner sign → verify |

> 脚本均已 `chmod +x`，可直接执行（兼容 OpenCode terminal 环境）。
> 首次使用建议先 `cat` 查看脚本内注释，确认输出目录与默认参数符合预期。