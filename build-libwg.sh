#! /usr/bin/env bash

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$ROOT/Sources/WireGuardKitGo"

cd "$SRC_ROOT"

BUILD_ROOT="$ROOT/build/libwg-go"
LIPO_ARTIFACT_IOS="$BUILD_ROOT/lipo/iphoneos/libwg-go.a"
LIPO_ARTIFACT_IPHONESIM="$BUILD_ROOT/lipo/iphonesimulator/libwg-go.a"
LIPO_ARTIFACT_MACOS="$BUILD_ROOT/lipo/macosx/libwg-go.a"
XCFRAMEWORK_PATH="$ROOT/Frameworks/wg-go.xcframework"

rm -rf "$XCFRAMEWORK_PATH"
rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"
mkdir -p $(dirname "$LIPO_ARTIFACT_IOS")
mkdir -p $(dirname "$LIPO_ARTIFACT_IPHONESIM")
mkdir -p $(dirname "$LIPO_ARTIFACT_MACOS")

# Create a patched goroot using patches needed for iOS
GOROOT="$BUILD_ROOT/goroot/" # Not exported yet, still need the original GOROOT to copy
mkdir -p "$GOROOT"
rsync --exclude="pkg/obj/go-build" -a "$(go env GOROOT)/" "$GOROOT/"
export GOROOT
cat goruntime-*.diff | patch -p1 -fN -r- -d "$GOROOT"

BUILD_CFLAGS="-fembed-bitcode -Wno-unused-command-line-argument"

IOS_LIBS=()
IPHONESIM_LIBS=()
MACOS_LIBS=()

# Build the library for each target
function build_arch() {
    local ARCH="$1"
    local SDKNAME="$2"
    local GOTAG=""
    local GOOS=""
    local GOARCH=""
    if [[ "$SDKNAME" == "iphoneos" || "$SDKNAME" == "iphonesimulator" ]];  then
        local GOTAG="ios"
        local GOOS="ios"
    elif [[ "$SDKNAME" == "macosx" ]]; then
        local GOTAG="darwin"
        local GOOS="darwin"
    fi
    if [[ "$ARCH" == "x86_64" ]]; then
        local GOARCH="amd64"
    elif [[ "$ARCH" == "arm64" ]]; then
        local GOARCH="arm64"
    fi
    
    # Find the SDK path
    local SDKPATH
    SDKPATH="$(xcrun --sdk "$SDKNAME" --show-sdk-path)"
    local PLATFORM_CFLAGS=""
    if [[ "$SDKNAME" == "iphoneos" ]]; then
        PLATFORM_CFLAGS="-miphoneos-version-min=15.0"
    elif [[ "$SDKNAME" == "iphonesimulator" ]]; then
        PLATFORM_CFLAGS="-miphonesimulator-version-min=15.0"
    elif [[ "$SDKNAME" == "macosx" ]]; then
        PLATFORM_CFLAGS="-mmacosx-version-min=12.0"
    fi
    local FULL_CFLAGS="$BUILD_CFLAGS -isysroot $SDKPATH -arch $ARCH $PLATFORM_CFLAGS"
    local LIBPATH="$BUILD_ROOT/$SDKNAME/libwg-go-$ARCH.a"

    CGO_ENABLED=1 CGO_CFLAGS="$FULL_CFLAGS" CGO_LDFLAGS="$FULL_CFLAGS" GOOS="$GOOS" GOARCH="$GOARCH" \
        go build -tags $GOTAG -ldflags=-w -trimpath -v -o "$LIBPATH" -buildmode c-archive
    # rm -f "$BUILD_ROOT/libwg-go-$ARCH.h"
    if [[ "$SDKNAME" == "iphoneos" ]]; then
        IOS_LIBS+=($LIBPATH)
    elif [[ "$SDKNAME" == "iphonesimulator" ]]; then
        IPHONESIM_LIBS+=($LIBPATH)
    elif [[ "$SDKNAME" == "macosx" ]]; then
        MACOS_LIBS+=($LIBPATH)
    fi
}

build_arch arm64 iphonesimulator
build_arch x86_64 iphonesimulator
build_arch arm64 iphoneos
build_arch arm64 macosx
build_arch x86_64 macosx

LIPO="${LIPO:-lipo}"
"$LIPO" -create -output "$LIPO_ARTIFACT_IOS" "${IOS_LIBS[@]}"
"$LIPO" -create -output "$LIPO_ARTIFACT_IPHONESIM" "${IPHONESIM_LIBS[@]}"
"$LIPO" -create -output "$LIPO_ARTIFACT_MACOS" "${MACOS_LIBS[@]}"

xcodebuild -create-xcframework \
    -library "$LIPO_ARTIFACT_IOS" -headers "$BUILD_ROOT/iphoneos/libwg-go-arm64.h" \
    -library "$LIPO_ARTIFACT_IPHONESIM" -headers "$BUILD_ROOT/iphonesimulator/libwg-go-arm64.h" \
    -library "$LIPO_ARTIFACT_MACOS" -headers "$BUILD_ROOT/macosx/libwg-go-arm64.h" \
    -output "$XCFRAMEWORK_PATH"
