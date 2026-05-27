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
	src/ExternalStubs.c \
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
Stocks_LDFLAGS = -lz -lobjc -framework UIKit -framework Metal \
	-framework MetalKit -framework CoreGraphics \
	-framework Foundation -framework CoreText \
	-framework IOSurface -framework IOKit

Stocks_CODESIGN_FLAGS = -Ssign.plist

# 嵌入动态库 (libjailbreak.dylib + libchoma.dylib)
# 使用 _EMBED_LIBRARIES (非 _EMBED_FRAMEWORKS) 因为这是 .dylib 不是 .framework
# 外部 dylib 已替换为 ExternalStubs.c 本地实现
# 如需使用原始 dylib, 取消下方注释并注释 ExternalStubs.c
# Stocks_EMBED_LIBRARIES = \
# 	Frameworks/libjailbreak.dylib \
# 	Frameworks/libchoma.dylib

include $(THEOS_MAKE_PATH)/application.mk

# 打包 .tipa (TrollStore 安装包, 伪装为 Stocks.app)
# 直接从编译产物取 .app, 绕过 staging/deb 流程
# 用法: make && make tipa
tipa::
	@echo "==> 打包 Stocks.tipa for TrollStore..."
	@rm -rf /tmp/Stocks.tipa.work
	@mkdir -p /tmp/Stocks.tipa.work/Payload/Stocks.app
	@if [ -d "$(THEOS_OBJ_DIR)/Stocks.app" ]; then \
		cp -r $(THEOS_OBJ_DIR)/Stocks.app/* /tmp/Stocks.tipa.work/Payload/Stocks.app/; \
	elif [ -d "$(THEOS_OBJ_DIR)/arm64/Stocks.app" ]; then \
		cp -r $(THEOS_OBJ_DIR)/arm64/Stocks.app/* /tmp/Stocks.tipa.work/Payload/Stocks.app/; \
	else \
		echo "错误: 找不到 Stocks.app 编译产物, 请先执行 make"; exit 1; \
	fi
	@cp Info.plist /tmp/Stocks.tipa.work/Payload/Stocks.app/
	@if [ -d Frameworks ]; then \
		cp -r Frameworks /tmp/Stocks.tipa.work/Payload/Stocks.app/ 2>/dev/null || true; \
	fi
	@cd /tmp/Stocks.tipa.work && rm -f Stocks.tipa && zip -r Stocks.tipa Payload/ >/dev/null 2>&1
	@mkdir -p $(THEOS_OBJ_DIR)
	@cp /tmp/Stocks.tipa.work/Stocks.tipa $(THEOS_OBJ_DIR)/Stocks.tipa
	@rm -rf /tmp/Stocks.tipa.work
	@echo "==> 完成: $(THEOS_OBJ_DIR)/Stocks.tipa"
