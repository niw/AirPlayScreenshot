#!/bin/bash
#
# Build Cisco openh264 as an XCFramework with arm64-iphoneos and
# arm64-iphonesimulator slices. Decoder + common only — encoder and
# processing libraries are dropped.
#
# Pinned to v2.4.1 intentionally. v2.5.0 introduced a regression
# (commit c0e5ea28, "Fix regression in PR#3707 for multi-thread
# decoding") that silently removed picture-reorder logic for
# non-baseline streams. The result on iOS AirPlay High profile
# streams is heavy JPEG-like block noise. The fix landed in master
# (commit c2e7c4a3, March 2025) but as of v2.6.0 the regression
# is still present in tagged releases. v2.4.1 predates the
# regression and decodes our streams cleanly.

set -euo pipefail

# `readonly VAR=$(...)` would mask the command's exit status under `set -e`,
# so assign first and mark readonly separately.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR

readonly OPENH264_DIR="${SCRIPT_DIR}/openh264"
readonly OPENH264_REPO="https://github.com/cisco/openh264.git"
readonly OPENH264_REF="v2.4.1"
readonly BUILD_DIR="${SCRIPT_DIR}/build"
readonly OUT_DIR="${BUILD_DIR}/output"
readonly INSTALL_DIR="${SCRIPT_DIR}/../Sources"
readonly SDK_MIN="16.0"
readonly USE_ASM="Yes"

# Clone openh264 at the pinned ref, re-cloning if an existing checkout
# is at any other ref.
fetch_openh264() {
  local current
  if [[ ! -d "${OPENH264_DIR}/.git" ]]; then
    echo "==> Cloning ${OPENH264_REPO} @ ${OPENH264_REF}"
    rm -rf "${OPENH264_DIR}"
    git clone --depth 1 --branch "${OPENH264_REF}" --single-branch \
      "${OPENH264_REPO}" "${OPENH264_DIR}"
    return
  fi
  current=$(cd "${OPENH264_DIR}" \
    && git describe --tags --always 2>/dev/null || echo unknown)
  if [[ "${current}" != "${OPENH264_REF}" ]]; then
    echo "==> openh264 clone is at ${current}, re-cloning at ${OPENH264_REF}"
    rm -rf "${OPENH264_DIR}"
    git clone --depth 1 --branch "${OPENH264_REF}" --single-branch \
      "${OPENH264_REPO}" "${OPENH264_DIR}"
  fi
}

# Copy the public openh264 headers and a module map into a slice's
# include directory. The module map lets Swift import these headers as
# a Clang module. (codec_api.h includes codec_app_def.h and codec_def.h
# itself.)
# Arguments:
#   - Slice output directory, e.g. "${OUT_DIR}/iphoneos".
copy_headers() {
  local out="$1"
  cp "${OPENH264_DIR}"/codec/api/wels/*.h "${out}/include/openh264/"
  cat > "${out}/include/module.modulemap" <<'EOF'
module OpenH264 {
    header "openh264/codec_api.h"
    header "openh264/codec_ver.h"
    export *
}
EOF
}

# Build one arm64 slice and stage its static library and headers.
# Arguments:
#   - openh264 OS name, "ios" or "iossim".
#   - Slice name, "iphoneos" or "iphonesimulator".
build_slice() {
  local os="$1"
  local slice="$2"
  echo "==> Building arm64-${slice}"
  cd "${OPENH264_DIR}"
  make clean >/dev/null
  make OS="${os}" ARCH=arm64 SDK_MIN="${SDK_MIN}" USE_ASM="${USE_ASM}" \
    libraries -j8
  libtool -static -o "${OUT_DIR}/${slice}/lib/libopenh264_dec.a" \
    libdecoder.a libcommon.a
  copy_headers "${OUT_DIR}/${slice}"
}

main() {
  fetch_openh264

  # Drop in our simulator-arm64 platform makefile (openh264 ships only a
  # device-arm64 platform-ios.mk; the simulator target needs the
  # -simulator triple). We keep platform-iossim.mk alongside this script
  # so it survives openh264 re-clones.
  cp "${SCRIPT_DIR}/platform-iossim.mk" "${OPENH264_DIR}/build/platform-iossim.mk"

  rm -rf "${BUILD_DIR}"
  mkdir -p "${OUT_DIR}"/{iphoneos,iphonesimulator}/lib
  mkdir -p "${OUT_DIR}"/{iphoneos,iphonesimulator}/include/openh264

  build_slice ios iphoneos
  build_slice iossim iphonesimulator

  echo "==> Creating XCFramework"
  cd "${BUILD_DIR}"
  rm -rf OpenH264.xcframework
  xcodebuild -create-xcframework \
    -library "${OUT_DIR}/iphoneos/lib/libopenh264_dec.a" \
    -headers "${OUT_DIR}/iphoneos/include" \
    -library "${OUT_DIR}/iphonesimulator/lib/libopenh264_dec.a" \
    -headers "${OUT_DIR}/iphonesimulator/include" \
    -output OpenH264.xcframework

  echo "==> Installing to ${INSTALL_DIR}"
  mkdir -p "${INSTALL_DIR}"
  rm -rf "${INSTALL_DIR}/OpenH264.xcframework"
  cp -R "${BUILD_DIR}/OpenH264.xcframework" \
    "${INSTALL_DIR}/OpenH264.xcframework"

  echo
  echo "==> Done: ${INSTALL_DIR}/OpenH264.xcframework"
  ls -l "${INSTALL_DIR}/OpenH264.xcframework"
}

main "$@"
