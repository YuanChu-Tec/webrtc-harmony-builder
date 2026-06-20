#!/bin/bash
# Full architecture build script for WebRTC-OHOS
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

source config.sh
source user_config.sh 2>/dev/null

# Setup PATH
export PATH="${DEPOT_TOOLS_DIR}:${PATH}"
echo "[INFO] depot_tools in PATH: $(which gn.py 2>/dev/null)"
echo "[INFO] WEBRTC_SRC_DIR=${WEBRTC_SRC_DIR}"

for cpu in arm64 arm x86_64; do
    echo ""
    echo "========================================"
    echo "  Compiling: ${cpu}"
    echo "========================================"
    export TARGET_CPU="${cpu}"
    export OUTPUT_DIR="out/webrtc_${cpu}"
    out_dir="${WEBRTC_SRC_DIR}/${OUTPUT_DIR}"
    
    echo "[INFO] TARGET_CPU=${TARGET_CPU}, OUTPUT_DIR=${OUTPUT_DIR}"
    
    rm -rf "${out_dir}"
    mkdir -p "${out_dir}"
    
    # Generate GN args
    echo ">> [${cpu}] Generating GN args..."
    cat > "${out_dir}/args.gn" << GNEOF
is_clang=true
target_cpu="${cpu}"
target_os="ohos"
ohos_sdk_native_root="${OHOS_SDK_NATIVE_ROOT}"

# Disable Linux-specific features that fail in OHOS cross-compilation
use_glib=false
use_pulseaudio=false
rtc_use_pipewire=false
rtc_link_pipewire=false
use_gtk=false
rtc_include_tests=false
rtc_build_examples=false
rtc_include_ilbc=true
rtc_use_dummy_audio_file_devices=true
GNEOF
    cat "${out_dir}/args.gn"
    
    # Run gn gen (use gn.py directly to avoid CRLF wrapper issues)
    echo ">> [${cpu}] Running gn gen (via gn.py)..."
    (cd "${WEBRTC_SRC_DIR}" && python3 "${DEPOT_TOOLS_DIR}/gn.py" gen "${out_dir}") 2>&1
    
    if [ $? -ne 0 ]; then
        echo "[ERROR] ${cpu} gn gen failed"
        continue
    fi
    
    # Run ninja build
    echo ">> [${cpu}] Running ninja build..."
    (cd "${WEBRTC_SRC_DIR}" && python3 "${DEPOT_TOOLS_DIR}/ninja.py" -C "${out_dir}" -v 2>&1)
    
    if [ $? -eq 0 ]; then
        echo "[OK] ${cpu} build succeeded"
    else
        echo "[ERROR] ${cpu} build failed"
    fi
done

echo ""
echo "[DONE] All architectures completed"
