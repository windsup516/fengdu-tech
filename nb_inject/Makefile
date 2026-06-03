# NB Cheat — 进程内 dylib (Framework 替换方案)
# 替换目标: 游戏加载的 TGPA.framework/TGPA 或类似 dylib
# 安装方式: 重打包 IPA，替换目标 framework，TrollStore 签名安装
#
# 构建: make
# 输出: NBWrapper.dylib

ARCHS = arm64
TARGET = iphone:13.0
DEBUG = 0

# === 目标 dylib 安装名 (根据游戏实际加载的 framework 修改) ===
# nb原版使用 @rpath/IMgui.dylib 作为安装名
# 如果游戏加载的是 TGPA.framework/TGPA，改为:
#   INSTALL_NAME = @rpath/TGPA.framework/TGPA
INSTALL_NAME = @rpath/IMgui.dylib

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = NBWrapper
NBWrapper_FILES = \
	NBMain.mm \
	NBLoginManager.m \
	../include/imgui/imgui.cpp \
	../include/imgui/imgui_draw.cpp \
	../include/imgui/imgui_tables.cpp \
	../include/imgui/imgui_widgets.cpp \
	../include/imgui/backends/imgui_impl_metal.mm

NBWrapper_CFLAGS = -fobjc-arc -std=c++17 -stdlib=libc++ \
	-I../include -I../include/imgui -I../include/imgui/backends -Iinclude \
	-Wno-error=unused-const-variable -Wno-error=unused-variable \
	-Wno-error=unused-function -Wno-error=nullability-completeness \
	-Wno-error=incompatible-pointer-types -Wno-error=format-security

NBWrapper_CCFLAGS = -std=c++17 -stdlib=libc++ \
	-I../include -I../include/imgui -I../include/imgui/backends -Iinclude

NBWrapper_LDFLAGS = -dynamiclib \
	-install_name $(INSTALL_NAME) \
	-Wl,-undefined,dynamic_lookup \
	-current_version 1.0.0 -compatibility_version 1.0.0 \
	-lz -lobjc -framework UIKit -framework Metal \
	-framework MetalKit -framework CoreGraphics \
	-framework Foundation -framework CoreText \
	-framework IOSurface -framework QuartzCore

NBWrapper_INSTALL_PATH = /tmp

include $(THEOS_MAKE_PATH)/library.mk

# === 打包脚本 ===
after-install::
	@echo "============================================"
	@echo "  NBWrapper.dylib ready"
	@echo "  Install name: $(INSTALL_NAME)"
	@echo "  Placement:"
	@echo "    1. Decrypt DeltaForce IPA"
	@echo "    2. Replace TGPA.framework/TGPA with this dylib"
	@echo "    3. Re-sign with TrollStore"
	@echo "    4. Install via TrollStore"
	@echo "============================================"
	@DYLIB=$$(find .theos -name NBWrapper.dylib -type f | head -1); \
	if [ -f "$$DYLIB" ]; then \
		cp "$$DYLIB" ./NBWrapper.dylib; \
		echo "Copied to: ./NBWrapper.dylib"; \
		otool -L ./NBWrapper.dylib 2>/dev/null || echo "(otool not available)"; \
	fi
