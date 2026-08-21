#!/bin/bash
# decompile.sh — 阶段 2：jadx 反编译（含 multi-dex 处理）
# 用法：./decompile.sh <目标.apk> [输出目录，默认 jadx_out]

APK="$1"
OUTDIR="${2:-jadx_out}"

if [ -z "$APK" ]; then
    echo "用法：$0 <目标.apk> [输出目录]"
    exit 1
fi

if [ ! -f "$APK" ]; then
    echo "错误：APK 文件不存在：$APK"
    exit 1
fi

echo "=== 阶段 2：jadx 反编译 ==="
echo "目标：$APK"
echo "输出：$OUTDIR"
echo ""

# 检查是否为 multi-dex（含多个 classes.dex）
DEX_COUNT=$(unzip -l "$APK" | grep -c 'classes[0-9]*\.dex' || true)
if [ "$DEX_COUNT" -gt 1 ]; then
    echo "检测到 multi-dex（共 $DEX_COUNT 个 dex 文件），jadx 将自动合并处理..."
fi

jadx -d "$OUTDIR" "$APK"

echo ""
echo "=== 完成 ==="
echo "Java 源码目录：$OUTDIR/sources/"
echo "资源目录：$OUTDIR/resources/"
echo ""
echo "提示："
echo "  - 若部分类反编译失败，可回退到 apktool 的 smali/ 人工分析"
echo "  - 使用 grep 定位关键逻辑：grep -rn '关键方法名' $OUTDIR/sources/"