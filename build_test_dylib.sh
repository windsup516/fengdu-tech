#!/bin/bash
# Build minimal test dylib to verify Mach VM injection mechanism
# Usage: ./build_test_dylib.sh
# Output: Frameworks/DFTest.dylib

CLANG=$(which clang 2>/dev/null || echo "")
if [ -z "$CLANG" ]; then
    echo "FATAL: clang not found"
    exit 1
fi

SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")
if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
    for try_sdk in \
        "$THEOS/sdks/iPhoneOS16.5.sdk" \
        "$THEOS/sdks/iPhoneOS16.0.sdk" \
        "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"; do
        if [ -d "$try_sdk" ]; then SDK="$try_sdk"; break; fi
    done
fi

if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
    echo "FATAL: No iOS SDK found"
    exit 1
fi

echo "Building DFTest.dylib with SDK: $SDK"

mkdir -p Frameworks

$CLANG -arch arm64 -isysroot "$SDK" -miphoneos-version-min=13.0 \
    -fobjc-arc -std=c++17 -stdlib=libc++ \
    -Idylib -Isrc -Iinclude \
    -dynamiclib \
    -install_name @executable_path/Frameworks/DFTest.dylib \
    -Wl,-undefined,dynamic_lookup \
    -o Frameworks/DFTest.dylib \
    dylib/DFTest.mm \
    -framework UIKit -framework Foundation -lobjc

if [ $? -eq 0 ] && [ -f Frameworks/DFTest.dylib ]; then
    echo "DFTest.dylib built OK: $(wc -c < Frameworks/DFTest.dylib) bytes"
    # Strip code signature if any
    codesign --remove-signature Frameworks/DFTest.dylib 2>/dev/null || true
    echo "Ready for injection testing"
else
    echo "BUILD FAILED"
    exit 1
fi
