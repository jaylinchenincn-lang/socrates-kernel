#!/usr/bin/env bash
# ==============================================================================
# Redmi K60 Pro (socrates / SM8550) - LineageOS 24.0 Custom Kernel Build Script
# Features: In-Tree KernelSU-Next + Docker Virtualization (Namespaces & Cgroups)
# ==============================================================================
set -e

WORK_DIR="$(pwd)/socrates_kernel_build"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

echo "[1/6] Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y \
    bc bison build-essential ccache curl flex \
    git gnupg gperf libxml2 libxml2-utils lzop pngcrush rsync schedtool \
    squashfs-tools xsltproc zip zlib1g-dev python3 libssl-dev libncurses5-dev \
    pkg-config libelf-dev libfl-dev dwarves cpio erofs-utils \
    binutils-aarch64-linux-gnu

echo "[2/6] Setting up Clang toolchain (AOSP r416183b)..."
mkdir -p toolchain
cd toolchain
if [ ! -d "clang" ]; then
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git clang || \
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 https://github.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r416183b.git clang
fi
if [ ! -d "gcc64" ]; then
    git clone --depth 1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 gcc64
fi
if [ ! -d "gcc32" ]; then
    git clone --depth 1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9 gcc32
fi
cd "${WORK_DIR}"

echo "[3/6] Cloning LineageOS 24.0 Socrates source trees..."
mkdir -p android
cd android

# Exact repos from build-manifest.xml
if [ ! -d "kernel" ]; then
    git clone --depth 1 -b lineage-24.0 https://github.com/LineageOS/android_kernel_xiaomi_sm8550.git kernel
fi
if [ ! -d "modules" ]; then
    git clone --depth 1 -b lineage-24.0 https://github.com/LineageOS/android_kernel_xiaomi_sm8550-modules.git modules
fi
if [ ! -d "devicetrees" ]; then
    git clone --depth 1 -b lineage-24.0 https://github.com/LineageOS/android_kernel_xiaomi_sm8550-devicetrees.git devicetrees
fi

echo "[4/6] Integrating KernelSU-Next into kernel source tree..."
cd kernel
curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s next

echo "[5/6] Injecting Docker configurations..."
cat << 'EOF' >> arch/arm64/configs/gki_defconfig

# --- Injected Docker Configurations ---
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_USER_NS=y
CONFIG_CGROUP_DEVICE=y
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
CONFIG_BRIDGE_NETFILTER=y
CONFIG_POSIX_MQUEUE=y
CONFIG_NET_CLS_ACT=y
CONFIG_NET_SCH_INGRESS=y
CONFIG_NET_SCH_HTB=y
CONFIG_NET_CLS_U32=y
CONFIG_NET_CLS_FW=y
CONFIG_IP_SET=y
CONFIG_IP_SET_HASH_IP=y
CONFIG_IP_SET_HASH_NET=y
CONFIG_KSU=y
EOF

echo "[6/6] Compiling Kernel Image..."
export PATH="${WORK_DIR}/toolchain/clang/bin:${WORK_DIR}/toolchain/gcc64/bin:${WORK_DIR}/toolchain/gcc32/bin:${PATH}"
export ARCH=arm64
export SUBARCH=arm64
export CC=clang
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-

mkdir -p out
MAKE_ARGS="O=out ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-"

make $MAKE_ARGS gki_defconfig
make $MAKE_ARGS vendor/kalama_GKI.config
make $MAKE_ARGS vendor/socrates_GKI.config

# Force ensure Docker configs remain enabled and ThinLTO is used
scripts/config --file out/.config \
    -e CONFIG_PID_NS \
    -e CONFIG_IPC_NS \
    -e CONFIG_USER_NS \
    -e CONFIG_CGROUP_DEVICE \
    -e CONFIG_NETFILTER_XT_MATCH_ADDRTYPE \
    -e CONFIG_BRIDGE_NETFILTER \
    -e CONFIG_POSIX_MQUEUE \
    -e CONFIG_KSU \
    -d CONFIG_LTO_CLANG_FULL \
    -e CONFIG_LTO_CLANG_THIN

make $MAKE_ARGS olddefconfig
make $MAKE_ARGS -j$(nproc) Image modules

echo "=========================================================="
echo " BUILD SUCCESSFUL! Output Image:"
echo " ${WORK_DIR}/android/kernel/out/arch/arm64/boot/Image"
echo "=========================================================="
