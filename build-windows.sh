#!/bin/bash
# Build script for Windows (Git Bash) - full local build, no GitHub Actions needed
# Usage: bash build-windows.sh [--skip-libv2ray] [--skip-hevtun]
set -o errexit
set -o pipefail
set -o nounset

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Config ──────────────────────────────────────────────────────────────────
ANDROID_SDK="${ANDROID_SDK:-/c/Users/admin/AppData/Local/Android/Sdk}"
NDK_VERSION="29.0.13113456"
NDK_HOME="${ANDROID_SDK}/ndk/${NDK_VERSION}"
GOBIN="${GOBIN:-/c/Users/admin/go/bin}"
export PATH="$PATH:$GOBIN"
export ANDROID_NDK_HOME="$NDK_HOME"

SKIP_LIBV2RAY=false
SKIP_HEVTUN=false
for arg in "$@"; do
  case $arg in
    --skip-libv2ray) SKIP_LIBV2RAY=true ;;
    --skip-hevtun)   SKIP_HEVTUN=true ;;
  esac
done

echo "=== v2rayNG Windows Build Script (fully local) ==="
echo "NDK: ${NDK_HOME}"
echo ""

# ── Validate NDK ─────────────────────────────────────────────────────────────
if [[ ! -d "$NDK_HOME" ]]; then
  echo "ERROR: NDK not found at ${NDK_HOME}"
  echo "Available NDK versions:"; ls "${ANDROID_SDK}/ndk/"; exit 1
fi

# ── Step 0: Fix Windows symlinks in submodules ────────────────────────────────
echo "=== Step 0: Fixing Windows symlinks ==="
bash "$__dir/fix-windows-symlinks.sh"

# ── Step 1: Compile libhevtun ─────────────────────────────────────────────────
if [[ "$SKIP_HEVTUN" == "false" ]]; then
  echo "=== Step 1: Compiling libhevtun ==="
  TMPDIR=$(mktemp -d)
  cleanup() { rm -rf "$TMPDIR"; }
  trap 'echo "Error in: $BASH_COMMAND"; cleanup; exit 1' ERR INT

  mkdir -p "$TMPDIR/jni"
  cp -r "$__dir/hev-socks5-tunnel" "$TMPDIR/jni/hev-socks5-tunnel"
  echo 'include $(call all-subdir-makefiles)' > "$TMPDIR/jni/Android.mk"

  "${NDK_HOME}/ndk-build.cmd" \
      NDK_PROJECT_PATH="$TMPDIR" \
      APP_BUILD_SCRIPT="$TMPDIR/jni/Android.mk" \
      "APP_ABI=armeabi-v7a arm64-v8a x86 x86_64" \
      APP_PLATFORM=android-24 \
      NDK_LIBS_OUT="$TMPDIR/libs" \
      NDK_OUT="$TMPDIR/obj" \
      "APP_CFLAGS=-O3 -DPKGNAME=com/v2ray/ang/service" \
      "APP_LDFLAGS=-Wl,--build-id=none -Wl,--hash-style=gnu"

  mkdir -p "$__dir/libs"
  cp -r "$TMPDIR/libs/"* "$__dir/libs/"
  cleanup
  trap - ERR INT
  echo "libhevtun compiled OK"
else
  echo "=== Step 1: Skipping libhevtun (--skip-hevtun) ==="
fi

# ── Step 2: Copy hevtun libs into app ────────────────────────────────────────
echo "=== Step 2: Copying hevtun libs to app ==="
mkdir -p "$__dir/V2rayNG/app/libs"
cp -r "$__dir/libs/"* "$__dir/V2rayNG/app/libs/"

# ── Step 3: Build libv2ray.aar ────────────────────────────────────────────────
if [[ "$SKIP_LIBV2RAY" == "false" ]]; then
  echo "=== Step 3: Building libv2ray.aar (gomobile) ==="

  command -v gomobile >/dev/null 2>&1 || {
    echo "gomobile not found, installing..."
    go install golang.org/x/mobile/cmd/gomobile@latest
  }
  command -v jq >/dev/null 2>&1 || {
    echo "jq not found, downloading..."
    curl -sL -o "$GOBIN/jq.exe" \
      "https://github.com/jqlang/jq/releases/latest/download/jq-windows-amd64.exe"
  }

  pushd "$__dir/AndroidLibXrayLite" > /dev/null
  mkdir -p assets data
  bash gen_assets.sh download
  cp data/*.dat assets/
  go mod tidy
  gomobile init
  gomobile bind -androidapi 24 -trimpath -ldflags='-s -w -buildid=' ./
  cp libv2ray.aar "$__dir/V2rayNG/app/libs/libv2ray.aar"
  popd > /dev/null
  echo "libv2ray.aar built and copied OK"
else
  echo "=== Step 3: Skipping libv2ray.aar (--skip-libv2ray) ==="
fi

# ── Step 4: Patch build.gradle.kts with ndkVersion ───────────────────────────
echo "=== Step 4: Patching build.gradle.kts ==="
GRADLE_KTS="$__dir/V2rayNG/app/build.gradle.kts"
if grep -q "ndkVersion" "$GRADLE_KTS"; then
  echo "ndkVersion already set"
else
  sed -i '10a\    ndkVersion = "'"${NDK_VERSION}"'"' "$GRADLE_KTS"
  echo "ndkVersion inserted"
fi

# ── Step 5: Write local.properties ───────────────────────────────────────────
echo "=== Step 5: Writing local.properties ==="
ANDROID_SDK_PROP=$(cygpath -w "$ANDROID_SDK" | sed 's/\\/\\\\/g; s/:/\\:/g')
echo "sdk.dir=${ANDROID_SDK_PROP}" > "$__dir/V2rayNG/local.properties"

# ── Step 6: Build APK ─────────────────────────────────────────────────────────
echo "=== Step 6: Building APK ==="
cd "$__dir/V2rayNG"
chmod 755 gradlew
./gradlew licenseFdroidReleaseReport
./gradlew assembleRelease

echo ""
echo "=== BUILD COMPLETE ==="
find "$__dir/V2rayNG/app/build/outputs/apk" -name "*.apk" 2>/dev/null \
  | sort | while read apk; do echo "  $apk"; done
