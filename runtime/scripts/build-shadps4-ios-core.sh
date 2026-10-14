#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FEX_SOURCE="${PROJECT_ROOT}/runtime/sources/fexcore-darwin"
FEX_BUILD_DIR="${PROJECT_ROOT}/runtime/build/fexcore-ios-arm64"
CORE_BUILD_DIR="${PROJECT_ROOT}/runtime/build/shadps4-ios"
HISTORICAL_CMAKE_COMMIT="74f94b61b213fbc231b59a3917cb404cbb25e098"

for tool in git cmake ninja xcrun ruby; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "error: required tool not found: ${tool}" >&2
    exit 1
  }
done

[[ -d "${FEX_SOURCE}" && -f "${FEX_SOURCE}/CMakeLists.txt" ]] || {
  echo "error: FEXCore Darwin source is missing at ${FEX_SOURCE}" >&2
  exit 1
}

# The committed root CMakeLists.txt is the dependency-wrapper file. The full
# shadPS4 core build definition exists in this repo's history at the pinned commit.
# Use it only for this ephemeral CI job, restoring the tracked file on every exit.
HISTORICAL_CMAKE="$(mktemp)"
ORIGINAL_CMAKE="$(mktemp)"
if ! git show "${HISTORICAL_CMAKE_COMMIT}:CMakeLists.txt" > "${HISTORICAL_CMAKE}"; then
  echo "error: unable to retrieve the known shadPS4 core CMake definition" >&2
  exit 1
fi
grep -Fq 'add_library(shadps4_ios STATIC' "${HISTORICAL_CMAKE}" || {
  echo "error: pinned CMake definition has no shadps4_ios target" >&2
  exit 1
}
cp "${PROJECT_ROOT}/CMakeLists.txt" "${ORIGINAL_CMAKE}"
restore_root_cmake() {
  cp "${ORIGINAL_CMAKE}" "${PROJECT_ROOT}/CMakeLists.txt"
  rm -f "${ORIGINAL_CMAKE}" "${HISTORICAL_CMAKE}"
}
trap restore_root_cmake EXIT
cp "${HISTORICAL_CMAKE}" "${PROJECT_ROOT}/CMakeLists.txt"

# Initialize all direct and nested dependencies used by the core.
git -C "${PROJECT_ROOT}" submodule update --init --recursive

IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IOS_SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
IOS_CLANG="$(xcrun --sdk iphoneos -f clang)"
IOS_CLANGXX="$(xcrun --sdk iphoneos -f clang++)"

printf '== shadPS4 iOS ARM64 core build ==\n'
printf 'iOS SDK: %s (%s)\n' "${IOS_SDK}" "${IOS_SDK_VERSION}"
printf 'Deployment target: iOS 18.0\n'
printf 'FEX source: %s\n' "${FEX_SOURCE}"
printf 'Core build: %s\n' "${CORE_BUILD_DIR}"

# Rebuild FEXCore here: the core needs generated headers as well as its .a files.
bash "${PROJECT_ROOT}/runtime/scripts/build-fexcore-ios.sh"

# Work around known modern Apple SDK header/compiler quirks within this build only.
IOS_COMPAT_FLAGS='-include float.h -D__SWIFT_ATTR_SUPPORTS_SENDABLE_DECLS=1 -D__OBJC2__=1 -Wno-elaborated-enum-base'
rm -rf "${CORE_BUILD_DIR}"
cmake -S "${PROJECT_ROOT}" -B "${CORE_BUILD_DIR}" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_SYSTEM_PROCESSOR=arm64 \
  -DCMAKE_OSX_SYSROOT="${IOS_SDK}" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
  -DCMAKE_C_COMPILER="${IOS_CLANG}" \
  -DCMAKE_CXX_COMPILER="${IOS_CLANGXX}" \
  -DCMAKE_OBJC_COMPILER="${IOS_CLANG}" \
  -DCMAKE_OBJCXX_COMPILER="${IOS_CLANGXX}" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="${IOS_COMPAT_FLAGS}" \
  -DCMAKE_CXX_FLAGS="${IOS_COMPAT_FLAGS}" \
  -DCMAKE_OBJC_FLAGS="${IOS_COMPAT_FLAGS}" \
  -DCMAKE_OBJCXX_FLAGS="${IOS_COMPAT_FLAGS}" \
  -DENABLE_SHADPS4_IOS_LIB=ON \
  -DENABLE_FEX_GUEST_CPU=ON \
  -DFEXCORE_GUEST_CPU_SOURCE_DIR="${FEX_SOURCE}" \
  -DFEXCORE_GUEST_CPU_BUILD_DIR="${FEX_BUILD_DIR}" \
  -DENABLE_TESTS=OFF \
  -DENABLE_DISCORD_RPC=OFF \
  -DENABLE_UPDATER=OFF \
  -DENABLE_BACHATA_RUNTIME=OFF \
  -DENABLE_SYSTEM_LIBRARIES=OFF \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5

cmake --build "${CORE_BUILD_DIR}" --target shadps4_ios --parallel 3

CORE_ARCHIVE="${CORE_BUILD_DIR}/libshadps4_ios.a"
[[ -f "${CORE_ARCHIVE}" ]] || {
  echo "error: expected iOS core archive was not produced: ${CORE_ARCHIVE}" >&2
  find "${CORE_BUILD_DIR}" -maxdepth 5 -name '*.a' -print >&2 || true
  exit 1
}
ARCHS="$(xcrun lipo -archs "${CORE_ARCHIVE}")"
[[ "${ARCHS}" == *arm64* ]] || {
  echo "error: core archive does not contain ARM64: ${ARCHS}" >&2
  exit 1
}
printf 'Core archive produced: %s (%s)\n' "${CORE_ARCHIVE}" "${ARCHS}"
