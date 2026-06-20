#!/bin/bash
# ============================================================================
# WebRTC for HarmonyOS - 主构建脚本
# 支持单架构/全架构编译、打包、清理
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/scripts/common.sh"

setup_path

# ============================================================================
# 打印
# ============================================================================
print_header() {
    clear 2>/dev/null || true
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║       WebRTC for HarmonyOS 构建工具                 ║"
    echo "║       支持 arm64 / arm / x86_64 三架构             ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
}

press_enter() { read -p "  按回车键继续..."; }

# ============================================================================
# 配置向导
# ============================================================================
config_wizard() {
    print_header
    echo "  配置向导"
    echo "  ───────────────────────────────────────"
    echo ""

    local cfg="${SCRIPT_DIR}/user_config.sh"

    # SDK 路径
    local cur_sdk="${OHOS_SDK_NATIVE_ROOT}"
    read -p "  OHOS SDK native 路径 [${cur_sdk}]: " input_sdk
    OHOS_SDK_NATIVE_ROOT="${input_sdk:-$cur_sdk}"
    if [[ -d "$OHOS_SDK_NATIVE_ROOT" ]]; then
        echo "  ✅ SDK 路径有效"
    else
        echo "  ⚠️  路径不存在，已保存供后续设置"
    fi

    # 默认架构
    local cur_cpu="${TARGET_CPU}"
    echo ""
    echo "  默认目标架构:"
    echo "    1) arm64"
    echo "    2) arm"
    echo "    3) x86_64"
    echo "    4) 全架构 (arm64 + arm + x86_64)"
    read -p "  选择 [1-4] (当前: ${cur_cpu}): " arch
    case $arch in
        1) TARGET_CPU="arm64" ;;
        2) TARGET_CPU="arm" ;;
        3) TARGET_CPU="x86_64" ;;
        4) TARGET_CPU="all" ;;
        *) TARGET_CPU="${cur_cpu}" ;;
    esac

    # 线程数
    local cur_jobs="${PARALLEL_JOBS}"
    echo ""
    read -p "  并行线程数 [${cur_jobs}]: " input_jobs
    if [[ -n "$input_jobs" && "$input_jobs" =~ ^[0-9]+$ && "$input_jobs" -gt 0 ]]; then
        PARALLEL_JOBS="$input_jobs"
    fi

    # 保存
    cat > "$cfg" << EOF
#!/bin/bash
export OHOS_SDK_NATIVE_ROOT="${OHOS_SDK_NATIVE_ROOT}"
export TARGET_CPU="${TARGET_CPU}"
export PARALLEL_JOBS="${PARALLEL_JOBS}"
EOF
    echo ""
    echo "  ✅ 配置已保存到: user_config.sh"
}

# ============================================================================
# 帮助
# ============================================================================
show_help() {
    echo "  用法: $0 [选项]"
    echo ""
    echo "  选项:"
    echo "    --download    下载全部（depot_tools + 源码 + third_party）"
    echo "    --check       检查下载状态"
    echo "    --build       编译单个架构（由 TARGET_CPU 指定）"
    echo "    --full        编译全部三架构 (arm64 + arm + x86_64)"
    echo "    --package     打包单个架构产物"
    echo "    --package-all 打包全部架构产物"
    echo "    --clean       清理单个架构输出"
    echo "    --clean-all   清理全部架构输出"
    echo "    --info        显示配置信息和下载状态"
    echo "    --config      配置向导"
    echo ""
    echo "  环境变量:"
    echo "    OHOS_SDK_NATIVE_ROOT    SDK 路径"
    echo "    TARGET_CPU              架构 (arm64/arm/x86_64)"
    echo "    PARALLEL_JOBS           编译线程数"
    echo ""
    echo "  示例:"
    echo "    $0                          交互菜单"
    echo "    $0 --download               下载全部依赖"
    echo "    $0 --config                 配置 SDK 路径"
    echo "    OHOS_SDK_NATIVE_ROOT=/path $0 --build"
    echo "    OHOS_SDK_NATIVE_ROOT=/path $0 --full"
    echo "    $0 --package"
    echo "    $0 --package-all"
    echo ""
}

# ============================================================================
# CLI 模式
# ============================================================================
if [[ $# -gt 0 ]]; then
    setup_path
    case "$1" in
        --download|-d)
            print_header
            do_download_all
            exit $?
            ;;
        --check|-c)
            print_header
            check_downloads_status
            exit $?
            ;;
        --build|-b)
            print_header
            validate_config || exit 1
            do_build_arch "$TARGET_CPU"
            list_outputs "$TARGET_CPU"
            exit $?
            ;;
        --full|-f)
            print_header
            do_build_all
            list_outputs_all
            exit $?
            ;;
        --package|-p)
            print_header
            do_package "$TARGET_CPU"
            exit $?
            ;;
        --package-all)
            print_header
            do_package_all
            exit $?
            ;;
        --clean)
            print_header
            do_clean "$TARGET_CPU"
            exit 0
            ;;
        --clean-all)
            print_header
            do_clean_all
            exit 0
            ;;
        --config)
            config_wizard
            exit 0
            ;;
        --info|-i)
            print_header
            show_config
            echo ""
            check_downloads_status
            echo ""
            validate_config
            echo ""
            echo "  全部架构: ${ALL_ARCHS[*]}"
            echo ""
            echo "  产物状态:"
            for cpu in "${ALL_ARCHS[@]}"; do
                local out_dir="${WEBRTC_SRC_DIR}/$(get_output_dir "$cpu")/obj/libwebrtc.a"
                if [[ -f "$out_dir" ]]; then
                    local size
                    size=$(du -h "$out_dir" 2>/dev/null | cut -f1)
                    echo "    ✅ ${cpu}: libwebrtc.a (${size})"
                else
                    echo "    ❌ ${cpu}: 未编译"
                fi
            done
            echo ""
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "  未知选项: $1"
            show_help
            exit 1
            ;;
    esac
fi

# ============================================================================
# 交互菜单
# ============================================================================
while true; do
    print_header
    show_config

    echo "  ${BOLD}下载${NC}"
    echo "    ${GREEN}1${NC}) 下载全部（depot_tools + 源码 + third_party）"
    echo "    ${GREEN}2${NC}) 检查下载状态"
    echo ""
    echo "  ${BOLD}编译${NC}"
    echo "    ${GREEN}3${NC}) 编译 ${TARGET_CPU}（单架构）"
    echo "    ${GREEN}4${NC}) 编译全部三架构（arm64 + arm + x86_64）"
    echo ""
    echo "  ${BOLD}打包${NC}"
    echo "    ${GREEN}5${NC}) 打包 ${TARGET_CPU} 产物"
    echo "    ${GREEN}6${NC}) 打包全部架构产物"
    echo ""
    echo "  ${BOLD}清理${NC}"
    echo "    ${GREEN}7${NC}) 清理 ${TARGET_CPU} 输出"
    echo "    ${GREEN}8${NC}) 清理全部架构输出"
    echo ""
    echo "  ${BOLD}配置${NC}"
    echo "    ${GREEN}9${NC}) 配置向导"
    echo "    ${GREEN}10${NC}) 显示信息"
    echo ""
    echo "    ${GREEN}0${NC}) 退出"
    echo ""

    read -p "  请输入 [0-10]: " choice
    echo ""

    case $choice in
        1)
            echo ""
            do_download_all
            press_enter
            ;;
        2)
            echo ""
            check_downloads_status
            press_enter
            ;;
        3)
            validate_config
            if [[ $? -eq 0 ]]; then
                do_build_arch "$TARGET_CPU"
                list_outputs "$TARGET_CPU"
            fi
            press_enter
            ;;
        4)
            do_build_all
            list_outputs_all
            press_enter
            ;;
        5)
            do_package "$TARGET_CPU"
            press_enter
            ;;
        6)
            do_package_all
            press_enter
            ;;
        7)
            do_clean "$TARGET_CPU"
            press_enter
            ;;
        8)
            do_clean_all
            press_enter
            ;;
        9)
            config_wizard
            press_enter
            ;;
        10)
            echo ""
            show_config
            check_downloads_status
            echo ""
            validate_config
            echo ""
            echo "  全部架构: ${ALL_ARCHS[*]}"
            echo ""
            echo "  产物状态:"
            for cpu in "${ALL_ARCHS[@]}"; do
                local out_dir="${WEBRTC_SRC_DIR}/$(get_output_dir "$cpu")/obj/libwebrtc.a"
                if [[ -f "$out_dir" ]]; then
                    local size
                    size=$(du -h "$out_dir" 2>/dev/null | cut -f1)
                    echo "    ✅ ${cpu}: libwebrtc.a (${size})"
                else
                    echo "    ❌ ${cpu}: 未编译"
                fi
            done
            echo ""
            press_enter
            ;;
        0)
            echo "  再见！"
            exit 0
            ;;
        *)
            echo "  无效选项"
            press_enter
            ;;
    esac
done
