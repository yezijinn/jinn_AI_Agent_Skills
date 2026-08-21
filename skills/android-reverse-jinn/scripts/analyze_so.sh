#!/bin/bash
# analyze_so.sh — 阶段 3：so 库轻量分析（strings + readelf/rabin2 + 导出符号）
# 用法：./analyze_so.sh <libs目录> [关键词，多个用空格分隔] [--deep]
# 说明：radare2（r2/rabin2）为开源框架，纯命令行可用，适合脚本固化；
#       本脚本默认做轻量辅助分析；加 --deep 时若检测到 rabin2，则调用
#       rabin2 -I / -E / -S / -z 做更深的架构、符号、节与字符串分析。

LIBS_DIR="$1"
shift
DEEP=0
KEYWORDS=""
for a in "$@"; do
    if [ "$a" = "--deep" ]; then
        DEEP=1
    else
        KEYWORDS="$KEYWORDS $a"
    fi
done
KEYWORDS=$(echo $KEYWORDS | sed 's/^ //')

if [ -z "$LIBS_DIR" ]; then
    echo "用法：$0 <libs目录> [关键词...]"
    echo "示例：$0 libs/ native java ssl crypto"
    echo ""
    echo "说明："
    echo "  - 扫描 libs/ 下所有 .so 文件"
    echo "  - 对每个 so 输出：文件信息 / 架构 / 导出符号列表 / 匹配关键词的字符串"
    echo "  - 加 --deep 可调用 rabin2（radare2）做更深度的架构/符号/节分析"
    exit 1
fi

if [ ! -d "$LIBS_DIR" ]; then
    echo "错误：libs 目录不存在：$LIBS_DIR"
    exit 1
fi

# 收集所有 .so 文件
SO_LIST=$(find "$LIBS_DIR" -name '*.so' -type f 2>/dev/null)

if [ -z "$SO_LIST" ]; then
    echo "未在 $LIBS_DIR 下找到 .so 文件"
    echo "请确认已运行 extract.sh 提取 lib/*.so"
    exit 0
fi

SO_COUNT=$(echo "$SO_LIST" | wc -l)
echo "=== 阶段 3：so 库轻量分析 ==="
echo "扫描目录：$LIBS_DIR"
echo "发现 so 文件：$SO_COUNT 个"
if [ -n "$KEYWORDS" ]; then
    echo "关键词过滤：$KEYWORDS"
fi
if [ "$DEEP" = "1" ]; then
    echo "深度分析：--deep（rabin2 可用时启用）"
fi
echo ""

# 逐个分析
for so in $SO_LIST; do
    echo "──────────────────────────────────────"
    echo "文件：$so"
    echo ""

    # 1. 文件信息
    echo "[1/4] 文件信息："
    file "$so" 2>/dev/null || echo "  (file 命令不可用)"
    ls -lh "$so" | awk '{print "  大小："$5}'
    echo ""

    # 2. 架构（readelf）
    echo "[2/4] 架构信息："
    if command -v readelf >/dev/null 2>&1; then
        readelf -h "$so" 2>/dev/null | grep -E 'Class:|Machine:|Type:' | sed 's/^/  /'
    else
        echo "  (readelf 不可用，跳过)"
    fi
    echo ""

    # 3. 导出函数列表（readelf --dyn-syms）
    echo "[3/4] 导出函数（FUNC + GLOBAL）："
    if command -v readelf >/dev/null 2>&1; then
        EXPORT_COUNT=$(readelf --dyn-syms "$so" 2>/dev/null | grep -c ' FUNC .* GLOBAL' || true)
        echo "  共 $EXPORT_COUNT 个导出函数"
        if [ "$EXPORT_COUNT" -gt 0 ]; then
            readelf --dyn-syms "$so" 2>/dev/null | grep ' FUNC .* GLOBAL' | awk '{print "  "$8}' | head -30
            if [ "$EXPORT_COUNT" -gt 30 ]; then
                echo "  ...（仅显示前 30 个，共 $EXPORT_COUNT 个）"
            fi
        fi
    else
        echo "  (readelf 不可用，跳过)"
    fi
    echo ""

    # 4. strings 关键词匹配
    echo "[4/4] 字符串分析："
    if [ -n "$KEYWORDS" ]; then
        echo "  关键词匹配结果："
        for kw in $KEYWORDS; do
            MATCH=$(strings "$so" 2>/dev/null | grep -i "$kw" || true)
            if [ -n "$MATCH" ]; then
                echo "  [$kw]"
                echo "$MATCH" | head -10 | sed 's/^/    /'
                MATCH_COUNT=$(echo "$MATCH" | wc -l)
                if [ "$MATCH_COUNT" -gt 10 ]; then
                    echo "    ...（仅显示前 10 条，共 $MATCH_COUNT 条）"
                fi
            else
                echo "  [$kw] (无匹配)"
            fi
        done
    else
        STR_COUNT=$(strings "$so" 2>/dev/null | wc -l || true)
        echo "  共 $STR_COUNT 条字符串"
        echo "  建议使用关键词过滤：./analyze_so.sh $LIBS_DIR <关键词>"
    fi
    echo ""

    # 5. 深度分析（rabin2，radare2 开源框架，可选）
    if [ "$DEEP" = "1" ]; then
        echo "[5] rabin2 深度分析："
        if command -v rabin2 >/dev/null 2>&1; then
            echo "  a) 文件信息/架构（-I）："
            rabin2 -I "$so" 2>/dev/null | head -20 | sed 's/^/     /' || echo "     (rabin2 -I 失败)"
            echo "  b) 导出符号（-E，前 30 条）："
            rabin2 -E "$so" 2>/dev/null | head -30 | sed 's/^/     /' || echo "     (rabin2 -E 失败)"
            echo "  c) 节表（-S）："
            rabin2 -S "$so" 2>/dev/null | head -20 | sed 's/^/     /' || echo "     (rabin2 -S 失败)"
            echo "  d) 交互反汇编：r2 -A \"$so\"  进入后可用 aaa / afl / s sym.<函数> / pdf / axt / q"
        else
            echo "  (rabin2 未安装，跳过。安装：sudo apt install radare2 或 git clone https://github.com/radareorg/radare2 && ./sys/install.sh)"
        fi
        echo ""
    fi
done

echo "=== 分析完成 ==="
echo ""
echo "提示："
echo "  - 本脚本默认做轻量静态分析；对可疑 so 文件，加 --deep 用 rabin2 做架构/符号/节深度分析"
echo "  - 如需交互式深度反汇编，可用开源 radare2：r2 -A <so文件>"
echo "  - 对照 jadx 反编译结果中的 System.loadLibrary / native 方法声明"
echo "    定位 Java↔Native 调用边界"