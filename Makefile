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
	src/HUDMainWindow.m \
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
	src/SceneDelegate.m \
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

# 强制使用 ldid 签名 (不用 codesign，因为 codesign 会拒绝自定义 entitlement)
# sign.plist 包含 task_for_pid-allow 等 TrollStore 专用权限
_THEOS_TARGET_CODESIGNING_TOOL = ldid
Stocks_CODESIGN_FLAGS = -Ssign.plist

# 嵌入动态库 — TrollStore + 越狱双模式
# libjailbreak.dylib: 内核 r/w 原语 (越狱下由 jb_init 激活, TrollStore 自动降级)
# libchoma.dylib: 代码生成 + Mach-O 解析
Stocks_EMBED_LIBRARIES = \
	Frameworks/libjailbreak.dylib \
	Frameworks/libchoma.dylib

include $(THEOS_MAKE_PATH)/application.mk

# after-package: make package 完成后自动打包 .tipa
after-package::
	@echo "==> 打包 Stocks.tipa for TrollStore..."
	@rm -rf /tmp/Stocks.tipa.work
	@mkdir -p /tmp/Stocks.tipa.work/Payload/Stocks.app
	@cp -rL $(THEOS_STAGING_DIR)/Applications/Stocks.app/* /tmp/Stocks.tipa.work/Payload/Stocks.app/
	@cp Info.plist /tmp/Stocks.tipa.work/Payload/Stocks.app/
	@for f in AppIcon60x60@2x.png AppIcon76x76@2x~ipad.png Assets.car PkgInfo; do \
		if [ -f "$$f" ]; then cp "$$f" /tmp/Stocks.tipa.work/Payload/Stocks.app/; fi; \
	done
	@if [ -d Base.lproj ]; then cp -r Base.lproj /tmp/Stocks.tipa.work/Payload/Stocks.app/; fi
	@if [ -d Frameworks ]; then cp -r Frameworks /tmp/Stocks.tipa.work/Payload/Stocks.app/; fi
	@if [ -d Resources ]; then cp -r Resources/* /tmp/Stocks.tipa.work/Payload/Stocks.app/; fi
	@# === 显式重签：不依赖 Theos 内部签名，全部在这里完成 ===
	@echo "==> Re-signing with entitlements (ldid2)..."; \
	LDID=$$(ls $(THEOS)/bin/ldid* 2>/dev/null | head -1); \
	if [ -z "$$LDID" ] || [ ! -x "$$LDID" ]; then \
		LDID=$$(which ldid 2>/dev/null); \
	fi; \
	if [ -z "$$LDID" ] || [ ! -x "$$LDID" ]; then \
		echo "FATAL: ldid not found!"; exit 1; \
	fi; \
	echo "Using ldid: $$LDID"; \
	APP_DIR=/tmp/Stocks.tipa.work/Payload/Stocks.app; \
	APP_BIN=$$APP_DIR/Stocks; \
	echo "=== Step 1: ad-hoc codesign to create _CodeSignature/CodeResources ==="; \
	codesign --force --sign - --timestamp=none "$$APP_DIR" 2>&1 || echo "ad-hoc codesign failed (non-fatal)"; \
	if [ -d "$$APP_DIR/_CodeSignature" ]; then \
		echo "_CodeSignature created OK"; \
		ls -la "$$APP_DIR/_CodeSignature/"; \
	else \
		echo "WARNING: no _CodeSignature directory"; \
	fi; \
	echo "=== Step 2: strip code signature from binary ==="; \
	codesign --remove-signature "$$APP_BIN" 2>/dev/null || true; \
	echo "=== Step 3: ldid sign with entitlements ==="; \
	$$LDID -S$(CURDIR)/sign.plist "$$APP_BIN" 2>&1 || { echo "FATAL: ldid signing failed!"; exit 1; }; \
	echo "=== Step 4: ldid sign embedded dylibs ==="; \
	for dylib in $$APP_DIR/Frameworks/*.dylib; do \
		if [ -f "$$dylib" ]; then \
			echo "  Signing: $$dylib"; \
			codesign --remove-signature "$$dylib" 2>/dev/null || true; \
			$$LDID -S$(CURDIR)/sign.plist "$$dylib" 2>&1 || true; \
		fi; \
	done; \
	echo "=== Step 5: verify entitlements ==="; \
	ENTS=$$($$LDID -e "$$APP_BIN" 2>&1); \
	echo "$$ENTS"; \
	if ! echo "$$ENTS" | grep -q "task_for_pid-allow"; then \
		echo "FATAL: task_for_pid-allow NOT embedded in final binary!"; exit 1; \
	fi; \
	echo "=== Entitlements OK, _CodeSignature present: $$([ -d $$APP_DIR/_CodeSignature ] && echo YES || echo NO) ==="
	@cd /tmp/Stocks.tipa.work && rm -f Stocks.tipa && zip -r Stocks.tipa Payload/ >/dev/null 2>&1
	@mkdir -p $(THEOS_PACKAGE_DIR)
	@cp /tmp/Stocks.tipa.work/Stocks.tipa $(THEOS_PACKAGE_DIR)/Stocks.tipa
	@rm -rf /tmp/Stocks.tipa.work
	@echo "==> 完成: $(THEOS_PACKAGE_DIR)/Stocks.tipa"
