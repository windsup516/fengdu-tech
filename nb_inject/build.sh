#!/bin/bash
# NB Cheat dylib — standalone build script (no Theos required)
# Requires: Xcode + Command Line Tools
set -e

CLANG=$(xcrun --sdk iphoneos --find clang 2>/dev/null || echo "")
if [ -z "$CLANG" ]; then
    echo "FATAL: clang not found. Install Xcode Command Line Tools."
    exit 1
fi

SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
    echo "FATAL: iPhoneOS SDK not found"
    exit 1
fi

echo "==> SDK: $SDK"
echo "==> Clang: $CLANG"

# === Config ===
INSTALL_NAME="@rpath/TGPA.framework/TGPA"
OUTPUT="NBWrapper.dylib"
IMGUI_DIR="../include/imgui"

# === Source files ===
SOURCES="NBMain.mm\
 NBLoginManager.m\
 $IMGUI_DIR/imgui.cpp\
 $IMGUI_DIR/imgui_draw.cpp\
 $IMGUI_DIR/imgui_tables.cpp\
 $IMGUI_DIR/imgui_widgets.cpp\
 $IMGUI_DIR/backends/imgui_impl_metal.mm"

# === Compile flags ===
FLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=13.0\
 -fobjc-arc -std=c++17 -stdlib=libc++\
 -I../include -I$IMGUI_DIR -I$IMGUI_DIR/backends -Iinclude\
 -dynamiclib -install_name $INSTALL_NAME\
 -Wl,-undefined,dynamic_lookup\
 -current_version 1.0.0 -compatibility_version 1.0.0\
 -lz -lobjc\
 -framework UIKit -framework Metal -framework MetalKit\
 -framework CoreGraphics -framework Foundation -framework CoreText\
 -framework IOSurface -framework QuartzCore\
 -Wno-error=unused-const-variable -Wno-error=unused-variable\
 -Wno-error=unused-function -Wno-error=nullability-completeness\
 -Wno-error=incompatible-pointer-types -Wno-error=format-security"

echo "==> Compiling $OUTPUT..."
$CLANG $FLAGS -o "$OUTPUT" $SOURCES 2>&1

if [ -f "$OUTPUT" ]; then
    echo ""
    echo "============================================"
    echo "  BUILD SUCCESS"
    echo "  $(ls -lh $OUTPUT | awk '{print $5}') — $(wc -c < $OUTPUT) bytes"
    echo "  Install name: $INSTALL_NAME"
    echo "============================================"
    echo ""
    echo ">>> PLACEMENT INSTRUCTIONS <<<"
    echo ""
    echo "This dylib is designed to REPLACE a framework that the game loads"
    echo "automatically at launch. The most common target is TGPA.framework."
    echo ""
    echo "Method A — IPA Repack (TrollStore, recommended):"
    echo "  1. Decrypt DeltaForce.ipa (use bfdecrypt or similar)"
    echo "  2. Unzip the IPA"
    echo "  3. Find Frameworks/TGPA.framework/TGPA inside Payload/"
    echo "  4. Replace that binary with NBWrapper.dylib (keep the NAME 'TGPA')"
    echo "  5. Re-sign: ldid -Ssign.plist Payload/*.app/"
    echo "  6. Re-zip + rename to .ipa"
    echo "  7. Install via TrollStore"
    echo ""
    echo "Method B — File Replacement (Jailbreak only):"
    echo "  1. Find installed game path via Filza"
    echo "  2. Navigate to .../DeltaForce.app/Frameworks/"
    echo "  3. Replace TGPA.framework/TGPA with NBWrapper.dylib"
    echo "  4. Respring / re-launch game"
    echo ""
    echo "If the game loads a DIFFERENT framework, edit INSTALL_NAME"
    echo "in this script to match, and rename NBWrapper.dylib accordingly."
    echo ""
    echo "After injection:"
    echo "  - Game launches → Card Key login window appears"
    echo "  - Enter any 16 characters and press Enter"
    echo "  - Cheat overlay activates"
    echo "  - Log: /tmp/nb_cheat.log (in game's sandbox)"
    echo "============================================"
else
    echo "FATAL: Build failed — $OUTPUT not created"
    ls -la ./
    exit 1
fi
