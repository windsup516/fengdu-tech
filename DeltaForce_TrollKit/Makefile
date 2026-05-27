# DeltaForce TrollKit v2.1 — Kernel-Level iOS Cheat Framework
# Build: make package
# Output: Star.tipa (TrollStore 安装包)

ARCHS = arm64
TARGET = iphone:16.5
DEBUG = 0
FINAL_PACKAGE = 1

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Stocks
Stocks_FILES = \
	src/main.m \
	src/XPFKernelInterface.c \
	src/CryptoUtils.m \
	src/LoginViewController.m \
	src/AppViewController.m \
	src/HUDController.m \
	src/HUDRootViewController.mm \
	src/TouchMainWindow.m \
	src/TouchViewController.m \
	src/HIDEventManager.m \
	src/GameHooks.mm \
	src/ESPOverlay.mm \
	src/MetalRenderer.mm \
	src/ImGuiAdapter.mm \
	src/WeaponConfig.m \
	src/DeviceInfo.m \
	include/imgui/imgui.cpp \
	include/imgui/imgui_draw.cpp \
	include/imgui/imgui_tables.cpp \
	include/imgui/imgui_widgets.cpp \
	include/imgui/backends/imgui_impl_metal.mm

Stocks_CFLAGS = -fobjc-arc -Iinclude -Iinclude/imgui -Iinclude/imgui/backends -I$(THEOS)/include \
	-Wno-error=unused-const-variable -Wno-error=unused-variable -Wno-error=nullability-completeness -Wno-error=incompatible-pointer-types
Stocks_OBJCCFLAGS = -fobjc-arc -std=c++17 -stdlib=libc++ -Iinclude -Iinclude/imgui -Iinclude/imgui/backends -I$(THEOS)/include \
	-Wno-error=unused-const-variable -Wno-error=unused-variable -Wno-error=nullability-completeness
Stocks_CCFLAGS = -std=c++17 -stdlib=libc++ -Iinclude -Iinclude/imgui -Iinclude/imgui/backends -I$(THEOS)/include
Stocks_LDFLAGS = -lz -lobjc -L Frameworks -ljailbreak -lchoma -framework UIKit -framework Metal \
	-framework MetalKit -framework CoreGraphics \
	-framework Foundation -framework CoreText \
	-framework IOSurface -framework IOKit

Stocks_CODESIGN_FLAGS = -Ssign.plist

# 嵌入动态库 (libjailbreak.dylib + libchoma.dylib)
# 使用 _EMBED_LIBRARIES (非 _EMBED_FRAMEWORKS) 因为这是 .dylib 不是 .framework
Stocks_EMBED_LIBRARIES = \
	Frameworks/libjailbreak.dylib \
	Frameworks/libchoma.dylib

include $(THEOS_MAKE_PATH)/application.mk

# 打包 .tipa (伪装为 Stocks.app)
after-package::
	@echo "==> 打包 .tipa for TrollStore..."
	@mkdir -p $(THEOS_STAGING_DIR)/Payload/Stocks.app
	@cp -r $(THEOS_STAGING_DIR)/Applications/Stocks.app/* $(THEOS_STAGING_DIR)/Payload/Stocks.app/
	@cp Info.plist $(THEOS_STAGING_DIR)/Payload/Stocks.app/
	@cp -r Frameworks $(THEOS_STAGING_DIR)/Payload/Stocks.app/ 2>/dev/null || true
	@cd $(THEOS_STAGING_DIR) && rm -f Stocks.tipa && zip -r Stocks.tipa Payload/
	@mkdir -p $(THEOS_OBJ_DIR)
	@cp $(THEOS_STAGING_DIR)/Stocks.tipa $(THEOS_OBJ_DIR)/Stocks.tipa 2>/dev/null || true
	@echo "==> 完成: $(THEOS_OBJ_DIR)/Stocks.tipa"
