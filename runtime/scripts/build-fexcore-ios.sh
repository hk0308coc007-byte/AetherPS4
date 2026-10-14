#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FEX_SOURCE="${PROJECT_ROOT}/runtime/sources/fexcore-darwin"
BUILD_DIR="${PROJECT_ROOT}/runtime/build/fexcore-ios-arm64"
STAGE_DIR="${PROJECT_ROOT}/runtime/build/fexcore-ios-stage/fexcore-ios-libs"

for tool in cmake ninja xcrun lipo python3; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "error: required build tool not found: ${tool}" >&2
    exit 1
  }
done

[[ -f "${FEX_SOURCE}/CMakeLists.txt" ]] || {
  echo "error: FEXCore source snapshot not found at ${FEX_SOURCE}" >&2
  exit 1
}

# Fail early with a useful message if the vendored FEX dependencies were omitted
# from the repository snapshot. These paths are expected to be present in-tree.
for rel in \
  External/fmt/CMakeLists.txt \
  External/xxhash/CMakeLists.txt \
  External/rpmalloc/CMakeLists.txt \
  External/unordered_dense/CMakeLists.txt \
  External/tiny-json/CMakeLists.txt \
  External/range-v3/CMakeLists.txt \
  External/SoftFloat-3e/CMakeLists.txt \
  External/cephes/CMakeLists.txt \
  Source/Common/cpp-optparse/CMakeLists.txt; do
  [[ -f "${FEX_SOURCE}/${rel}" ]] || {
    echo "error: missing FEXCore dependency file: ${FEX_SOURCE}/${rel}" >&2
    exit 1
  }
done

IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IOS_SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
IOS_CLANG="$(xcrun --sdk iphoneos -f clang)"
IOS_CLANGXX="$(xcrun --sdk iphoneos -f clang++)"

# FEX's configuration helper imports Python's packaging module. Use an isolated
# venv so we do not modify the hosted runner's system Python installation.
VENV_DIR="${PROJECT_ROOT}/runtime/build/fexcore-ios-python-venv"
python3 -m venv "${VENV_DIR}"
"${VENV_DIR}/bin/python3" -m pip install --disable-pip-version-check --quiet packaging
export PATH="${VENV_DIR}/bin:${PATH}"

printf '== FEXCore iOS ARM64 stage ==\n'
printf 'SDK: %s (%s)\n' "${IOS_SDK}" "${IOS_SDK_VERSION}"
printf 'Compiler: %s\n' "${IOS_CLANGXX}"
printf 'Source: %s\n' "${FEX_SOURCE}"

rm -rf "${BUILD_DIR}" "${STAGE_DIR}"
mkdir -p "${BUILD_DIR}" "${STAGE_DIR}"

cmake -S "${FEX_SOURCE}" -B "${BUILD_DIR}" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_SYSTEM_PROCESSOR=arm64 \
  -DCMAKE_OSX_SYSROOT="${IOS_SDK}" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.4 \
  -DCMAKE_C_COMPILER="${IOS_CLANG}" \
  -DCMAKE_CXX_COMPILER="${IOS_CLANGXX}" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${STAGE_DIR}" \
  -DTUNE_CPU=none \
  -DBUILD_FEXCORE_ONLY=ON \
  -DBUILD_FEXCORE_SMOKE=OFF \
  -DBUILD_TESTING=OFF \
  -DBUILD_FEX_LINUX_TESTS=OFF \
  -DBUILD_THUNKS=OFF \
  -DBUILD_FEXCONFIG=OFF \
  -DENABLE_GDB_SYMBOLS=OFF \
  -DENABLE_LTO=OFF \
  -DENABLE_JEMALLOC_GLIBC_ALLOC=OFF \
  -DENABLE_OFFLINE_TELEMETRY=OFF \
  -DENABLE_VIXL_DISASSEMBLER=OFF \
  -DENABLE_VIXL_SIMULATOR=OFF \
  -DENABLE_ZYDIS=OFF \
  -DENABLE_FEXCORE_PROFILER=OFF

# Build only the embeddable CPU-engine libraries and their static dependencies.
# No iOS executable is linked or run in this stage.
cmake --build "${BUILD_DIR}" \
  --target FEXCore FEXCore_Base Common CommonTools JemallocLibs \
  --parallel 4

# Stage exactly the static archives referenced by the existing Xcode project.
# This stage deliberately does not claim to produce libshadps4_ios.a or an IPA.
required_archives=(
  libFEXCore.a
  libFEXCore_Base.a
  libCommon.a
  libCommonTools.a
  libJemallocLibs.a
  librpmalloc.a
  libfmt.a
  libxxhash.a
  libtiny-json.a
  libcpp-optparse.a
  libsoftfloat_3e.a
  libcephes_128bit.a
)

: > "${STAGE_DIR}/ARCHITECTURES.txt"
for archive in "${required_archives[@]}"; do
  candidate="$(find "${BUILD_DIR}" -type f -name "${archive}" -print -quit)"
  [[ -n "${candidate}" ]] || {
    echo "error: expected iOS static archive was not produced: ${archive}" >&2
    echo "Known archives in the build directory:" >&2
    find "${BUILD_DIR}" -type f -name '*.a' -print >&2 || true
    exit 1
  }
  archs="$(lipo -archs "${candidate}")"
  [[ "${archs}" == "arm64" ]] || {
    echo "error: ${archive} has unexpected architectures: ${archs}" >&2
    exit 1
  }
  cp "${candidate}" "${STAGE_DIR}/${archive}"
  printf '%s\t%s\n' "${archive}" "${archs}" | tee -a "${STAGE_DIR}/ARCHITECTURES.txt"
done

printf '\nFEXCore iOS ARM64 static-library stage succeeded.\n'
printf 'Staged %s archives at %s\n' "${#required_archives[@]}" "${STAGE_DIR}"
