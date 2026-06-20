#!/bin/bash
# ============================================================================
# WebRTC for HarmonyOS - 编译工具函数
# 支持三种架构：arm64 / arm / x86_64
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

# ============================================================================
# 日志
# ============================================================================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${CYAN}▶${NC} ${BOLD}$1${NC}"; }
log_success() { echo -e "${GREEN}✅${NC} $1"; }
log_failure() { echo -e "${RED}❌${NC} $1"; }

# ============================================================================
# 添加 depot_tools 到 PATH
# ============================================================================
setup_path() {
    if [[ ":$PATH:" != *":${DEPOT_TOOLS_DIR}:"* ]]; then
        export PATH="${DEPOT_TOOLS_DIR}:$PATH"
    fi
}

# ============================================================================
# 下载工具函数
# ============================================================================

# 安全 git clone（支持重试、超时、增量更新）
git_safe_clone() {
    local url="$1"
    local dir="$2"
    local name="$3"
    local depth="${4:-$GIT_DEPTH}"

    if [[ -d "$dir/.git" ]]; then
        # 已有仓库，尝试更新
        log_info "${name} 已存在，检查更新..."
        (cd "$dir" && git pull --ff-only 2>/dev/null) && log_info "${name} 已更新" || log_warning "${name} 更新失败，使用已有版本"
        return 0
    fi

    if [[ -d "$dir" ]]; then
        log_warning "${name} 目录存在但非 git 仓库，跳过"
        return 1
    fi

    log_info "正在下载 ${name}..."
    log_info "  源: ${url}"
    log_info "  目: ${dir}"

    local start_time
    start_time=$(date +%s)

    local cmd="git clone"
    [[ "$depth" -gt 0 ]] && cmd+=" --depth ${depth}"
    cmd+=" ${url} ${dir}"

    if eval "$cmd" 2>&1; then
        local end_time elapsed
        end_time=$(date +%s)
        elapsed=$((end_time - start_time))
        local size
        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        log_success "${name} 下载完成 (${elapsed}s, ${size})"
        return 0
    fi

    log_failure "${name} 下载失败"
    rm -rf "$dir"
    return 1
}

# 下载 depot_tools
download_depot_tools() {
    log_step "下载 depot_tools"
    echo ""
    mkdir -p "$(dirname "$DEPOT_TOOLS_DIR")"
    git_safe_clone "$DEPOT_TOOLS_REPO" "$DEPOT_TOOLS_DIR" "depot_tools" || return 1
    setup_path
    return 0
}

# 下载 ohos_webrtc 源码（自动清理无效缓存）
download_webrtc_source() {
    log_step "下载 ohos_webrtc 源码"
    echo ""
    mkdir -p "$(dirname "$WEBRTC_SRC_DIR")"

    # 如果存在无效源码（目录存在但没有 .gn 文件），删除重下
    if [[ -d "$WEBRTC_SRC_DIR" && ! -f "${WEBRTC_SRC_DIR}/.gn" ]]; then
        log_warning "检测到无效源码目录（缺少 .gn），正在清理..."
        rm -rf "$WEBRTC_SRC_DIR"
    fi

    git_safe_clone "$WEBRTC_REPO" "$WEBRTC_SRC_DIR" "ohos_webrtc" || return 1

    if [[ ! -f "${WEBRTC_SRC_DIR}/.gn" ]]; then
        log_failure "源码下载不完整（缺少 .gn 文件）"
        return 1
    fi
    return 0
}

# 下载 third_party 依赖
download_third_party() {
    log_step "下载 third_party 依赖"
    echo ""

    if [[ -d "${WEBRTC_SRC_DIR}/third_party/.git" ]]; then
        log_info "third_party 已下载，检查更新..."
        (cd "${WEBRTC_SRC_DIR}/third_party" && git pull --ff-only 2>/dev/null) && log_info "third_party 已更新" || log_warning "third_party 更新失败，使用已有版本"
        return 0
    fi

    log_info "third_party 单独仓库，下载至: ${WEBRTC_SRC_DIR}/third_party"

    local start_time
    start_time=$(date +%s)

    if git clone --depth "${GIT_DEPTH}" "$THIRD_PARTY_REPO" "${WEBRTC_SRC_DIR}/third_party" 2>&1; then
        local end_time elapsed
        end_time=$(date +%s)
        elapsed=$((end_time - start_time))
        local size
        size=$(du -sh "${WEBRTC_SRC_DIR}/third_party" 2>/dev/null | cut -f1)
        log_success "third_party 下载完成 (${elapsed}s, ${size})"
        return 0
    fi

    log_failure "third_party 下载失败"
    rm -rf "${WEBRTC_SRC_DIR}/third_party"
    return 1
}

# 创建 .gclient 文件
create_gclient() {
    local gclient_file
    gclient_file="$(dirname "${WEBRTC_SRC_DIR}")/.gclient"
    if [[ -f "$gclient_file" ]]; then
        local existing_url
        existing_url=$(grep -oP "url\s*=\s*'\K[^']+" "$gclient_file" 2>/dev/null)
        if [[ "$existing_url" == *"ohos_webrtc"* ]]; then
            log_info ".gclient 已存在，无需重新创建"
            return 0
        fi
        log_warning ".gclient 内容不匹配，重新生成"
    fi

    cat > "$gclient_file" << EOF
solutions = [
  {
    "name"        : "src",
    "url"         : "${WEBRTC_REPO}",
    "deps_file"   : "DEPS",
    "managed"     : False,
    "custom_deps" : {
    },
  },
]
EOF
    log_info ".gclient 已创建: ${gclient_file}"
}

# 下载全部（完整流程）
do_download_all() {
    log_step "开始下载全部依赖"
    echo ""

    local total_start
    total_start=$(date +%s)

    # 1. depot_tools
    download_depot_tools || log_warning "depot_tools 下载失败，部分功能可能受限"

    # 2. WebRTC 源码
    echo ""
    download_webrtc_source || { log_failure "WebRTC 源码下载失败，终止"; return 1; }

    # 3. third_party
    echo ""
    download_third_party || log_warning "third_party 下载失败，编译将中断"

    # 4. .gclient
    echo ""
    create_gclient

    # 5. 汇总
    local total_end elapsed
    total_end=$(date +%s)
    elapsed=$((total_end - total_start))

    echo ""
    echo "═══════════════════════════════════════════"
    echo "  下载汇总"
    echo "═══════════════════════════════════════════"
    echo "  总耗时: $((elapsed / 60)) 分 $((elapsed % 60)) 秒"
    echo ""
    check_downloads_status
    echo ""
}

# 检查下载状态
check_downloads_status() {
    local all_ok=0
    echo "  下载状态:"
    echo "  ───────────────────────────────────────"

    if [[ -f "${DEPOT_TOOLS_DIR}/gclient.py" ]]; then
        local dt_size
        dt_size=$(du -sh "$DEPOT_TOOLS_DIR" 2>/dev/null | cut -f1)
        log_success "depot_tools    ${dt_size}"
    else
        log_failure "depot_tools    未下载"
        all_ok=1
    fi

    if [[ -f "${WEBRTC_SRC_DIR}/.gn" ]]; then
        local src_size
        src_size=$(du -sh "$WEBRTC_SRC_DIR" 2>/dev/null | cut -f1)
        log_success "ohos_webrtc    ${src_size}"
    else
        log_failure "ohos_webrtc    未下载"
        all_ok=1
    fi

    if [[ -d "${WEBRTC_SRC_DIR}/third_party/.git" ]]; then
        local tp_size
        tp_size=$(du -sh "${WEBRTC_SRC_DIR}/third_party" 2>/dev/null | cut -f1)
        log_success "third_party    ${tp_size}"
    else
        log_failure "third_party    未下载"
        all_ok=1
    fi

    if [[ -f "${WEBRTC_SRC_DIR}/.gclient" ]]; then
        log_success ".gclient       已配置"
    else
        log_warning ".gclient       未配置"
    fi

    echo ""
    if [[ $all_ok -eq 0 ]]; then
        log_success "全部下载完毕，可以开始编译"
    else
        echo "  💡 运行 ./builder.sh --download 补全下载"
    fi
    return $all_ok
}

# ============================================================================
# GN 构建配置生成
# 使用独立的输出目录: out/webrtc_<arch>
# ============================================================================
do_gn_gen() {
    local cpu="${1:-$TARGET_CPU}"
    local sdk="${2:-$OHOS_SDK_NATIVE_ROOT}"
    local out_dir="${WEBRTC_SRC_DIR}/$(get_output_dir "$cpu")"

    log_step "生成 GN 构建配置 [${cpu}]"

    mkdir -p "$out_dir"
    get_gn_args "$cpu" "$sdk" > "${out_dir}/args.gn"

    echo "  args.gn 内容:"
    sed 's/^/    /' "${out_dir}/args.gn"

    if (cd "${WEBRTC_SRC_DIR}" && gn gen "$(get_output_dir "$cpu")" 2>&1); then
        log_info "gn gen [${cpu}] 成功"
        return 0
    fi
    return 1
}

# ============================================================================
# Ninja 编译
# ============================================================================
do_ninja() {
    local cpu="${1:-$TARGET_CPU}"
    local out_subdir
    out_subdir=$(get_output_dir "$cpu")
    local out_dir="${WEBRTC_SRC_DIR}/${out_subdir}"

    log_step "执行 Ninja 编译 [${cpu}]"

    if [[ ! -f "${out_dir}/build.ninja" ]]; then
        log_error "build.ninja 不存在，请先执行 gn gen [${cpu}]"
        return 1
    fi

    local start_time
    start_time=$(date +%s)

    log_info "输出: ${out_subdir} | 线程: ${PARALLEL_JOBS}"
    if ninja -C "${WEBRTC_SRC_DIR}" "${out_subdir}" -v -j "${PARALLEL_JOBS}" 2>&1; then
        local end_time elapsed
        end_time=$(date +%s)
        elapsed=$((end_time - start_time))
        log_info "编译 [${cpu}] 成功！耗时: $((elapsed / 60)) 分 $((elapsed % 60)) 秒"
        return 0
    fi
    return 1
}

# ============================================================================
# 编译单个架构 (gn gen + ninja)
# ============================================================================
do_build_arch() {
    local cpu="$1"
    log_step "构建 [${cpu}]"
    echo ""

    do_gn_gen "$cpu" || return 1
    echo ""
    do_ninja "$cpu" || return 1
    echo ""
    log_success "[${cpu}] 构建完成"
    return 0
}

# ============================================================================
# 编译所有架构
# 依次编译 arm64, arm, x86_64
# ============================================================================
do_build_all() {
    log_step "开始全架构编译: ${ALL_ARCHS[*]}"
    echo ""

    validate_config || return 1
    setup_path

    local success_archs=()
    local failed_archs=()
    local total_start
    total_start=$(date +%s)

    for cpu in "${ALL_ARCHS[@]}"; do
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_step "编译架构: ${cpu}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        if do_build_arch "$cpu"; then
            success_archs+=("$cpu")
        else
            failed_archs+=("$cpu")
        fi
    done

    local total_end elapsed
    total_end=$(date +%s)
    elapsed=$((total_end - total_start))

    # 结果汇总
    echo ""
    echo "═══════════════════════════════════════════"
    echo "  编译结果汇总"
    echo "═══════════════════════════════════════════"
    echo "  总耗时: $((elapsed / 60)) 分 $((elapsed % 60)) 秒"
    echo ""

    for cpu in "${ALL_ARCHS[@]}"; do
        local out_dir="${WEBRTC_SRC_DIR}/$(get_output_dir "$cpu")/obj/libwebrtc.a"
        if [[ -f "$out_dir" ]]; then
            local size
            size=$(du -h "$out_dir" 2>/dev/null | cut -f1)
            log_success "[${cpu}] libwebrtc.a ${size}"
        else
            log_failure "[${cpu}] 未生成"
        fi
    done

    if [[ ${#failed_archs[@]} -eq 0 ]]; then
        echo ""
        log_success "全部架构编译成功"
    else
        echo ""
        log_failure "失败架构: ${failed_archs[*]}"
        return 1
    fi

    return 0
}

# ============================================================================
# 列示产物
# ============================================================================
list_outputs_arch() {
    local cpu="${1:-$TARGET_CPU}"
    local out_dir="${WEBRTC_SRC_DIR}/$(get_output_dir "$cpu")"

    local lib="${out_dir}/obj/libwebrtc.a"
    if [[ ! -f "$lib" ]]; then
        echo "  [${cpu}] 无产物"
        return
    fi

    local size
    size=$(du -h "$lib" 2>/dev/null | cut -f1)
    echo "  [${cpu}] libwebrtc.a   ${size}"
}

list_outputs() {
    local cpu="${1:-$TARGET_CPU}"
    local out_dir="${WEBRTC_SRC_DIR}/$(get_output_dir "$cpu")"
    echo ""
    echo "  📦 编译产物 [${cpu}]:"
    echo "  ───────────────────────────────────"

    # libwebrtc.a
    local lib="${out_dir}/obj/libwebrtc.a"
    if [[ -f "$lib" ]]; then
        local size
        size=$(du -h "$lib" 2>/dev/null | cut -f1)
        echo "  🎯 libwebrtc.a      ${size}"
    fi

    # .so 文件
    while IFS= read -r so; do
        local size
        size=$(du -h "$so" 2>/dev/null | cut -f1)
        echo "  📄 $(basename "$so")  ${size}"
    done < <(find "$out_dir" -name "*.so" -type f 2>/dev/null)

    # .a 文件（其他）
    while IFS= read -r a; do
        local size
        size=$(du -h "$a" 2>/dev/null | cut -f1)
        echo "  📦 $(basename "$a")  ${size}"
    done < <(find "$out_dir" -name "*.a" -type f -size +500k 2>/dev/null | grep -v "libwebrtc.a" | head -10)

    echo ""
}

list_outputs_all() {
    echo ""
    echo "  全部架构产物:"
    echo "  ───────────────────────────────────"
    for cpu in "${ALL_ARCHS[@]}"; do
        list_outputs_arch "$cpu"
    done
    echo ""
}

# ============================================================================
# 打包产物（单架构）
# ============================================================================
do_package() {
    local cpu="${1:-$TARGET_CPU}"
    local out_dir="${WEBRTC_SRC_DIR}/$(get_output_dir "$cpu")"

    if [[ ! -f "${out_dir}/obj/libwebrtc.a" ]]; then
        log_error "[${cpu}] libwebrtc.a 不存在，请先编译"
        return 1
    fi

    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    local pkg_name="webrtc_ohos_${cpu}_${ts}"
    local pkg_dir="${DIST_DIR}/${pkg_name}"

    log_step "打包 [${cpu}] 产物到 ${DIST_DIR}/"

    mkdir -p "${pkg_dir}/lib"

    # 复制主库
    cp "${out_dir}/obj/libwebrtc.a" "${pkg_dir}/lib/" 2>/dev/null

    # 复制动态库
    find "$out_dir" -name "*.so" -type f -exec cp {} "${pkg_dir}/lib/" \; 2>/dev/null

    # 复制依赖静态库（>50KB的第三方依赖库）
    local dep_count=0
    while IFS= read -r a; do
        cp "$a" "${pkg_dir}/lib/" 2>/dev/null
        ((dep_count++))
    done < <(find "$out_dir/obj/third_party" -name "*.a" -type f -size +50k 2>/dev/null)

    # 复制依赖 .a（来自所有核心模块，不限深度）
    while IFS= read -r a; do
        cp "$a" "${pkg_dir}/lib/" 2>/dev/null
        ((dep_count++))
    done < <(find "$out_dir/obj" -name "*.a" -type f -size +50k \
        ! -name "libwebrtc.a" \
        ! -path "*/third_party/*" 2>/dev/null)

    # 生成库清单（按大小降序排列）
    {
        echo "WebRTC for HarmonyOS - 库清单"
        echo "架构: ${cpu}"
        echo "构建时间: $(date)"
        echo "───── 主库 ─────"
        if [[ -f "${pkg_dir}/lib/libwebrtc.a" ]]; then
            local ws
            ws=$(du -h "${pkg_dir}/lib/libwebrtc.a" 2>/dev/null | cut -f1)
            printf "  %-40s %s\n" "libwebrtc.a" "$ws"
        fi
        echo ""
        echo "───── 依赖库 (${dep_count}个) ─────"
        for f in "${pkg_dir}/lib/"*.a; do
            local bn
            bn=$(basename "$f")
            [[ "$bn" = "libwebrtc.a" ]] && continue
            local fs
            fs=$(du -h "$f" 2>/dev/null | cut -f1)
            printf "  %-40s %s\n" "$bn" "$fs"
        done | sort -k2 -rh
    } > "${pkg_dir}/lib_list.txt"

    # 生成构建信息
    cat > "${pkg_dir}/build_info.txt" << EOF
WebRTC for HarmonyOS
构建时间: $(date)
目标架构: ${cpu}
OHOS SDK: ${OHOS_SDK_NATIVE_ROOT}
库数量: 1 个主库 + ${dep_count} 个依赖库
GN 参数:
$(get_gn_args "$cpu")
EOF

    # 打包
    (cd "${DIST_DIR}" && tar -czf "${pkg_name}.tar.gz" "${pkg_name}" 2>/dev/null)
    rm -rf "${pkg_dir}"

    local pkg_file="${DIST_DIR}/${pkg_name}.tar.gz"
    if [[ -f "$pkg_file" ]]; then
        local size
        size=$(du -h "$pkg_file" 2>/dev/null | cut -f1)
        log_info "打包完成: ${pkg_name}.tar.gz (${size}) (1主库+${dep_count}依赖库)"
        return 0
    fi
    log_error "打包失败"
    return 1
}

# ============================================================================
# 打包全部架构
# ============================================================================
do_package_all() {
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    local pkg_name="webrtc_ohos_all_${ts}"
    local pkg_dir="${DIST_DIR}/${pkg_name}"

    log_step "打包全部架构产物到 ${DIST_DIR}/"

    local arch_with_libs=""
    local any_found=0
    for cpu in "${ALL_ARCHS[@]}"; do
        local out_dir="${WEBRTC_SRC_DIR}/$(get_output_dir "$cpu")"
        local lib="${out_dir}/obj/libwebrtc.a"
        if [[ -f "$lib" ]]; then
            any_found=1
            mkdir -p "${pkg_dir}/${cpu}/lib"
            # 主库
            cp "$lib" "${pkg_dir}/${cpu}/lib/" 2>/dev/null
            # .so
            find "$out_dir" -name "*.so" -type f -exec cp {} "${pkg_dir}/${cpu}/lib/" \; 2>/dev/null
            # 依赖静态库（第三方）
            find "$out_dir/obj/third_party" -name "*.a" -type f -size +50k \
                -exec cp {} "${pkg_dir}/${cpu}/lib/" \; 2>/dev/null
            # 依赖静态库（所有核心模块，不限深度）
            find "$out_dir/obj" -name "*.a" -type f -size +50k \
                ! -name "libwebrtc.a" \
                ! -path "*/third_party/*" -exec cp {} "${pkg_dir}/${cpu}/lib/" \; 2>/dev/null
            local count
            count=$(find "${pkg_dir}/${cpu}/lib" -name "*.a" -type f | wc -l)
            local size
            size=$(du -h "$lib" 2>/dev/null | cut -f1)
            log_success "[${cpu}] ${count} 个库, libwebrtc.a ${size}"
            arch_with_libs="${arch_with_libs}${cpu}:${count}个库 "
        else
            log_failure "[${cpu}] 未找到产物，跳过"
        fi
    done

    if [[ $any_found -eq 0 ]]; then
        log_error "没有任何架构的产物，请先编译"
        rm -rf "${pkg_dir}"
        return 1
    fi

    # 生成全部构建设置信息
    cat > "${pkg_dir}/build_info.txt" << EOF
WebRTC for HarmonyOS - 全架构包
构建时间: $(date)
包含架构: ${ALL_ARCHS[*]}
架构详情: ${arch_with_libs}
OHOS SDK: ${OHOS_SDK_NATIVE_ROOT}
EOF

    # 打包
    (cd "${DIST_DIR}" && tar -czf "${pkg_name}.tar.gz" "${pkg_name}" 2>/dev/null)
    rm -rf "${pkg_dir}"

    local pkg_file="${DIST_DIR}/${pkg_name}.tar.gz"
    if [[ -f "$pkg_file" ]]; then
        local size
        size=$(du -h "$pkg_file" 2>/dev/null | cut -f1)
        echo ""
        log_info "打包完成: ${pkg_name}.tar.gz (${size})"
        echo "  架构详情: ${arch_with_libs}"
        return 0
    fi
    log_error "打包失败"
    return 1
}

# ============================================================================
# 清理
# ============================================================================
do_clean() {
    local cpu="${1:-$TARGET_CPU}"
    local out_dir="${WEBRTC_SRC_DIR}/$(get_output_dir "$cpu")"
    log_step "清理 [${cpu}] 构建输出"
    if [[ -d "$out_dir" ]]; then
        rm -rf "$out_dir"
        log_info "已删除: $(get_output_dir "$cpu")"
    else
        log_info "[${cpu}] 输出目录不存在，无需清理"
    fi
}

do_clean_all() {
    log_step "清理所有架构输出"
    for cpu in "${ALL_ARCHS[@]}"; do
        local out_dir="${WEBRTC_SRC_DIR}/$(get_output_dir "$cpu")"
        if [[ -d "$out_dir" ]]; then
            rm -rf "$out_dir"
            log_info "已删除: $(get_output_dir "$cpu")"
        fi
    done
}
