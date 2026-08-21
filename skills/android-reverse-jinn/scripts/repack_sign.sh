#!/bin/bash
# repack_sign.sh — 阶段 5：apktool b → zipalign → apksigner sign → verify → adb install
# 用法：./repack_sign.sh <apktool解码目录> [keystore路径，默认 debug.keystore]

OUT_DIR="$1"
KEYSTORE="${2:-debug.keystore}"

if [ -z "$OUT_DIR" ]; then
    echo "用法：$0 <apktool解码目录> [keystore路径]"
    exit 1
fi

if [ ! -d "$OUT_DIR" ]; then
    echo "错误：apktool 解码目录不存在：$OUT_DIR"
    exit 1
fi

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

echo "=== 阶段 5：重打包 → 对齐 → 签名 → 验证 ==="
echo ""

# 1. apktool 重打包
echo "[1/5] apktool 重打包..."
eval "$APKTOOL" b "$OUT_DIR" -o patched.apk
echo "  → patched.apk"
echo ""

# 2. zipalign 对齐
echo "[2/5] zipalign 对齐..."
zipalign -p -f 4 patched.apk aligned.apk
echo "  → aligned.apk"
echo ""

# 3. 生成 keystore（若不存在）
if [ ! -f "$KEYSTORE" ]; then
    echo "[3/5] 生成 debug keystore..."
    keytool -genkey -v -keystore "$KEYSTORE" -storepass android -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Debug,OU=Debug,O=Debug,L=Debug,ST=Debug,C=CN"
else
    echo "[3/5] 使用已有 keystore：$KEYSTORE"
fi
echo ""

# 4. apksigner 签名
echo "[4/5] apksigner 签名..."
apksigner sign --ks "$KEYSTORE" --ks-pass pass:android --out signed.apk aligned.apk
echo "  → signed.apk"
echo ""

# 5. 校验签名
echo "[5/5] 校验签名..."
apksigner verify --print-certs signed.apk
echo ""

echo "=== 完成 ==="
echo "签名后 APK：signed.apk"
echo ""
echo "安装验证（可选）："
echo "  adb install -r signed.apk"