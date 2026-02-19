#!/bin/bash
#
# Build setup script for p4c on illumos/Helios
# This script configures the cmake build directory but does not build.
# After running this script, cd into the build directory and run 'gmake'.
#
set -e

if [ "$(uname -s)" != "SunOS" ]; then
    echo "This script is intended for illumos/Helios only"
    exit 1
fi

function usage() {
    printf "$0 [-h] [-j <jobs>] [-t <build_type>]\n"
    printf "    -h            This message\n"
    printf "    -j <jobs>     Number of parallel jobs for make (default: 8)\n"
    printf "    -t <type>     Build type: Release, Debug, RelWithDebInfo (default: Release)\n"
    printf "    -b            Also run the build after configure\n"
}

# Get the repo root
P4C=$(git rev-parse --show-toplevel)
echo "Building p4c at git root: ${P4C}"

# Defaults
JOBS=8
BUILD_TYPE="Release"
RUN_BUILD=0

while getopts hj:t:b opt; do
    case $opt in
        h)
            usage
            exit 0
            ;;
        j)
            JOBS=$OPTARG
            ;;
        t)
            BUILD_TYPE=$OPTARG
            ;;
        b)
            RUN_BUILD=1
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

# Clone rapidjson if needed (header-only library)
RAPIDJSON_DIR=${P4C}/oxide/rapidjson
if [ ! -d "$RAPIDJSON_DIR" ]; then
    echo "Cloning rapidjson..."
    (cd "${P4C}/oxide" && git clone https://github.com/Tencent/rapidjson.git)
fi

# Create build directory
BUILD_DIR=${P4C}/build
mkdir -p "${BUILD_DIR}"

# illumos-specific flags
LINKER_FLAGS="-lnsl -lsocket"
C_FLAGS="-D__EXTENSIONS__ -D_POSIX_PTHREAD_SEMANTICS"

# Ensure GNU tools and pip-installed binaries are in PATH
export PATH="${PATH}:/usr/gnu/bin:${HOME}/.local/bin"

cd "${BUILD_DIR}"

# Use the oxide wrapper CMakeLists.txt which sets C++17 before including p4c
cmake "${P4C}/oxide" \
    -DCMAKE_UNITY_BUILD=ON \
    -DCMAKE_PROGRAM_PATH="${HOME}/.local/bin:/usr/gnu/bin" \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DCMAKE_INSTALL_PREFIX="${P4C}/install" \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DCMAKE_C_FLAGS="${C_FLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="${LINKER_FLAGS}" \
    -DCMAKE_PREFIX_PATH="/opt/ooce" \
    -DRAPIDJSON_DIR="${RAPIDJSON_DIR}/include" \
    -DENABLE_BMV2=OFF \
    -DENABLE_EBPF=OFF \
    -DENABLE_P4TC=OFF \
    -DENABLE_UBPF=OFF \
    -DENABLE_DPDK=OFF \
    -DENABLE_TOFINO=ON \
    -DENABLE_P4TEST=OFF \
    -DENABLE_P4FMT=OFF \
    -DENABLE_P4C_GRAPHS=OFF \
    -DENABLE_TEST_TOOLS=OFF \
    -DENABLE_GTESTS=OFF \
    -DENABLE_DOCS=OFF \
    -DENABLE_GC=ON \
    -DP4C_USE_PREINSTALLED_ABSEIL=ON \
    -Dabsl_DIR=/opt/ooce/absl/lib/cmake/absl \
    -DBoost_INCLUDE_DIR=/opt/ooce/boost/include \
    -DBoost_USE_STATIC_RUNTIME=ON

echo ""
echo "=========================================="
echo "Configuration complete!"
echo "Build directory: ${BUILD_DIR}"
echo ""
echo "To build, run:"
echo "  export PATH=$PATH:~/.local/bin"
echo "  cd ${BUILD_DIR} && gmake -j ${JOBS}"
echo ""
echo "To install after building:"
echo "  gmake install"
echo "=========================================="

if [ $RUN_BUILD -eq 1 ]; then
    echo ""
    echo "Running build..."
    gmake -j "${JOBS}"
fi
