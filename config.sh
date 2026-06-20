#!/bin/bash
# ============================================================================
# WebRTC for HarmonyOS - 编译配置文件
# 支持三种架构：arm64 / arm / x86_64
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 所有支持的架构
ALL_ARCHS=("arm64" "arm" "x86_64")

# 默认架构映射
declare -A ARCH_LABELS=([arm64]="arm64" [arm]="arm" [x86_64]="x86_64")
declare -A ARCH_OUT_DIRS=([arm64]="out/webrtc_arm64" [arm]="out/webrtc_arm" [x86_64]="out/webrtc_x86_64")

# 用户配置（可被 user_config.sh 覆盖）
export OHOS_SDK_NATIVE_ROOT="${OHOS_SDK_NATIVE_ROOT:-}"
export TARGET_CPU="${TARGET_CPU:-arm64}"
export PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc 2>/dev/null || echo 4)}"
export DEPOT_TOOLS_DIR="${DEPOT_TOOLS_DIR:-${SCRIPT_DIR}/work/depot_tools}"
export WEBRTC_SRC_DIR="${WEBRTC_SRC_DIR:-${SCRIPT_DIR}/work/src}"

# 加载用户自定义配置
if [[ -f "${SCRIPT_DIR}/user_config.sh" ]]; then
    source "${SCRIPT_DIR}/user_config.sh"
fi

# ── 下载源配置 ──
export DEPOT_TOOLS_REPO="${DEPOT_TOOLS_REPO:-https://gitee.com/YuanChu-Tec/depot_tools.git}"
export WEBRTC_REPO="${WEBRTC_REPO:-https://gitcode.com/CPF-ApplicationTPC/ohos_webrtc.git}"
export THIRD_PARTY_REPO="${THIRD_PARTY_REPO:-https://gitee.com/YuanChu-Tec/webrtc_third_party.git}"
export GIT_DEPTH="${GIT_DEPTH:-1}"        # shallow clone，节省带宽
export DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-0}" # 0=不限制

# 派生路径（输出目录依赖 TARGET_CPU）
get_output_dir() {
    local cpu="${1:-$TARGET_CPU}"
    echo "${ARCH_OUT_DIRS[$cpu]:-out/webrtc_${cpu}}"
}
export -f get_output_dir

export DIST_DIR="${DIST_DIR:-${SCRIPT_DIR}/dist}"
export LOGS_DIR="${LOGS_DIR:-${SCRIPT_DIR}/logs}"

mkdir -p "${DIST_DIR}" "${LOGS_DIR}"

# GN 参数（参考官方 build.sh）
get_gn_args() {
    local cpu="${1:-$TARGET_CPU}"
    local sdk="${2:-$OHOS_SDK_NATIVE_ROOT}"
    cat << EOF
is_clang=true
target_cpu="${cpu}"
target_os="ohos"
ohos_sdk_native_root="${sdk}"
rtc_use_dummy_audio_file_devices=true
rtc_include_tests=false
rtc_build_examples=false
rtc_enable_protobuf=false
EOF
}

# 显示配置
show_config() {
    local cpu="${1:-$TARGET_CPU}"
    local out_dir
    out_dir=$(get_output_dir "$cpu")
    echo ""
    echo "═══════════════════════════════════════"
    echo "  构建配置"
    echo "═══════════════════════════════════════"
    echo "  OHOS SDK:      ${OHOS_SDK_NATIVE_ROOT:-<未设置>}"
    echo "  目标架构:      ${cpu}"
    echo "  并行线程:      ${PARALLEL_JOBS}"
    echo "  WebRTC 源码:   ${WEBRTC_SRC_DIR}"
    echo "  输出目录:      ${WEBRTC_SRC_DIR}/${out_dir}"
    echo "  发布目录:      ${DIST_DIR}"
    echo "  depot_tools:   ${DEPOT_TOOLS_DIR}"
    echo ""
}

# 验证配置（含下载状态）
validate_config() {
    local errors=0

    if [[ -z "$OHOS_SDK_NATIVE_ROOT" ]]; then
        echo "  ❌ OHOS_SDK_NATIVE_ROOT 未设置"
        errors=1
    elif [[ ! -d "$OHOS_SDK_NATIVE_ROOT" ]]; then
        echo "  ❌ SDK 路径不存在: $OHOS_SDK_NATIVE_ROOT"
        errors=1
    fi

    if [[ ! -d "$WEBRTC_SRC_DIR" ]]; then
        echo "  ❌ WebRTC 源码未下载: $WEBRTC_SRC_DIR"
        echo "     请运行 ./builder.sh --download 或通过菜单下载"
        errors=1
    fi

    if [[ ! -f "${WEBRTC_SRC_DIR}/.gn" ]]; then
        echo "  ❌ WebRTC 源码目录无效（缺少 .gn 文件）"
        errors=1
    fi

    if [[ ! -d "${WEBRTC_SRC_DIR}/third_party" ]]; then
        echo "  ❌ third_party 依赖未下载"
        echo "     请运行 ./builder.sh --download 或通过菜单下载"
        errors=1
    fi

    if [[ ! -f "${DEPOT_TOOLS_DIR}/gclient.py" ]]; then
        echo "  ❌ depot_tools 未下载: $DEPOT_TOOLS_DIR"
        echo "     请运行 ./builder.sh --download 或通过菜单下载"
        errors=1
    fi

    if [[ ! -f "${WEBRTC_SRC_DIR}/.gclient" ]]; then
        echo "  ⚠️  .gclient 未配置（gclient sync 时需要）"
    fi

    if [[ $errors -gt 0 ]]; then
        echo ""
        echo "  💡 首次使用请依次执行:"
        echo "     ./builder.sh --download     # 下载全部源码和依赖"
        echo "     ./builder.sh --config       # 配置 SDK 路径"
        echo "     ./builder.sh --build        # 开始编译"
        return 1
    fi
    echo "  ✅ 配置验证通过"
    return 0
}
