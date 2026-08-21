#!/bin/bash
# extract.sh — 阶段 0~1：确认目标 + apktool 解码 + unzip 提取 so
# 用法：./extract.sh <目标.apk> [输出目录前缀，默认当前目录]

APK="$1"
WORKDIR="${2:-.}"

if [ -z "$APK" ]; then
    echo "用法：$0 <目标.apk> [输出目录前缀]"
    exit 1
fi

if [ ! -f "$APK" ]; then
    echo "错误：APK 文件不存在：$APK"
    exit 1
fi

echo "=== 阶段 0：确认目标 ==="
ls -lh "$APK"
echo ""

echo "=== 阶段 1：apktool 解码 ==="
# 解析 apktool 调用方式（通用，不绑定任何具体路径）：
#   1) 优先使用 PATH 中已安装的 apktool 命令；
#   2) 否则用环境变量 APKTOOL_JAR 指定的 jar（若设置）；
#   3) 否则在脚本所在目录的上级目录（通常为 skill 工作区根）及当前目录，
#      自动探测 apktool*.jar 并用 java -jar 调用。
APKTOOL="apktool"
if ! command -v apktool >/dev/null 2>&1; then
    JAR=""
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    # 探测候选 jar 路径：APKTOOL_JAR > <script 上级>/apktool*.jar > ./apktool*.jar
    if [ -n "$APKTOOL_JAR" ] && [ -f "$APKTOOL_JAR" ]; then
        JAR="$APKTOOL_JAR"
    else
        PARENT_JAR=$(find "$SCRIPT_DIR/.." "$SCRIPT_DIR" -maxdepth 1 -name 'apktool*.jar' 2>/dev/null | head -1)
        [ -n "$PARENT_JAR" ] && JAR="$PARENT_JAR"
    fi
    if [ -n "$JAR" ]; then
        APKTOOL="java -jar \"$JAR\""
        echo "提示：未检测到 apktool 命令，使用 java -jar 调用 $JAR"
    else
        echo "错误：既无 PATH 中的 apktool 命令，也未找到 apktool jar。"
        echo "请安装 apktool（见 SKILL.md 环境前置表），或设置 APKTOOL_JAR 指向 jar 文件。"
        exit 1
    fi
fi
eval "$APKTOOL" d -f "$APK" -o "$WORKDIR/apk_extract"
echo "解码完成：$WORKDIR/apk_extract/"
echo ""

echo "=== 提取原生 so 库 ==="
unzip -o "$APK" 'lib/*.so' -d "$WORKDIR/libs/" 2>/dev/null || echo "（无 lib/ 目录或 so 文件，跳过）"
echo ""

echo "=== 完成 ==="
echo "产物目录："
echo "  - $WORKDIR/apk_extract/  (apktool 解码结果)"
echo "  - $WORKDIR/libs/         (原生 so 库)"
echo ""
echo "下一步：运行 decompile.sh 进行 Java 源码还原"