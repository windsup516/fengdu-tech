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

# after-package: make package 完成后自动打包 .tipa
# 把 .tipa 放到和 .deb 同一目录, 方便 CI artifact 收集
# 同时删除 .deb 避免混淆
after-package::
	@echo "==> 打包 Stocks.tipa for TrollStore..."
	@echo "==> 1. 检查 staging 目录"
	@ls -la $(THEOS_STAGING_DIR)/Applications/Stocks.app/ 2>/dev/null || echo "(staging 空)"
	@echo "==> 2. 检查 Frameworks 目录"
	@ls -la Frameworks/ 2>/dev/null || echo "(无 Frameworks)"
	@rm -rf /tmp/Stocks.tipa.work
	@mkdir -p /tmp/Stocks.tipa.work/Payload/Stocks.app
	@cp -rL $(THEOS_STAGING_DIR)/Applications/Stocks.app/* /tmp/Stocks.tipa.work/Payload/Stocks.app/
	@cp Info.plist /tmp/Stocks.tipa.work/Payload/Stocks.app/
	@if [ -d Frameworks ]; then \
		echo "==> 复制 Frameworks..."; \
		cp -r Frameworks /tmp/Stocks.tipa.work/Payload/Stocks.app/; \
	fi
	@echo "==> 3. 打包前文件列表:"
	@find /tmp/Stocks.tipa.work/Payload -type f -exec ls -lh {} \; 2>/dev/null | head -20
	@cd /tmp/Stocks.tipa.work && rm -f Stocks.tipa && zip -r Stocks.tipa Payload/
	@ls -lh /tmp/Stocks.tipa.work/Stocks.tipa
	@mkdir -p $(THEOS_PACKAGE_DIR)
	@cp /tmp/Stocks.tipa.work/Stocks.tipa $(THEOS_PACKAGE_DIR)/Stocks.tipa
	@rm -rf /tmp/Stocks.tipa.work
	@echo "==> 完成: $(THEOS_PACKAGE_DIR)/Stocks.tipa"
