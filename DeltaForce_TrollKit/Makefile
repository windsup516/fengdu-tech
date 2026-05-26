# DeltaForce TrollKit v2.1 — Kernel-Level iOS Cheat Framework
# Build: make package
# Output: Star.tipa (TrollStore 安装包)

ARCHS = arm64
TARGET = iphone:14.0
DEBUG = 0
FINAL_PACKAGE = 1

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Star
Star_FILES = \
	src/main.m \
	src/XPFKernelInterface.c \
	src/CryptoUtils.m \
	src/LoginViewController.m \
	src/AppViewController.m \
	src/HUDController.m \
	src/HUDRootViewController.m \
	src/TouchMainWindow.m \
	src/TouchViewController.m \
	src/HIDEventManager.m \
	src/GameHooks.mm \
	src/ESPOverlay.mm \
	src/MetalRenderer.mm \
	src/ImGuiAdapter.mm \
	src/WeaponConfig.m \
	src/DeviceInfo.m

Star_CFLAGS = -fobjc-arc -Iinclude -I$(THEOS)/include
Star_LDFLAGS = -lz -lobjc -framework UIKit -framework Metal \
	-framework MetalKit -framework CoreGraphics \
	-framework Foundation -framework CoreText \
	-framework IOSurface -framework IOKit

Star_CODESIGN_FLAGS = -Ssign.plist

include $(THEOS_MAKE_PATH)/application.mk

# 打包 .tipa
after-package::
	@echo "==> 打包 .tipa for TrollStore..."
	@mkdir -p $(THEOS_STAGING_DIR)/Payload/Star.app
	@cp -r $(THEOS_STAGING_DIR)/Applications/Star.app/* $(THEOS_STAGING_DIR)/Payload/Star.app/
	@cp Info.plist $(THEOS_STAGING_DIR)/Payload/Star.app/
	@cd $(THEOS_STAGING_DIR) && rm -f Star.tipa && zip -r Star.tipa Payload/
	@mkdir -p $(THEOS_OBJ_DIR)
	@cp $(THEOS_STAGING_DIR)/Star.tipa $(THEOS_OBJ_DIR)/Star.tipa 2>/dev/null || true
	@echo "==> 完成: $(THEOS_OBJ_DIR)/Star.tipa"
