# DeltaForce TrollKit - Kernel-Level iOS Cheat Framework
# Build: make package
# Deploy: scp to TrollStore or sideload

ARCHS = arm64 arm64e
TARGET = iphone:15.0:13.0
DEBUG = 0
FINAL_PACKAGE = 1

include $(THEOS)/makefiles/common.mk

TOOL_NAME = Star
Star_FILES = src/main.m src/LoginViewController.m src/AppViewController.m \
             src/HUDController.m src/HUDRootViewController.m \
             src/TouchMainWindow.m src/TouchViewController.m \
             src/NetworkManager.m src/CryptoUtils.m \
             src/WeaponConfig.m src/AuthService.m \
             src/GameHooks.mm src/ESPOverlay.mm \
             src/MetalRenderer.mm src/ImGuiAdapter.mm \
             src/HIDEventManager.m src/SBSHelper.m \
             src/DeviceInfo.m src/StatusCard.m

Star_CFLAGS = -fobjc-arc -Iinclude -I$(THEOS)/include
Star_LDFLAGS = -lz -lobjc -framework UIKit -framework Metal \
               -framework MetalKit -framework CoreGraphics \
               -framework Foundation -framework CoreText \
               -framework IOSurface -framework IOKit

Star_CODESIGN_FLAGS = -Ssign.plist
Star_INSTALL_PATH = /Applications/Star.app

include $(THEOS_MAKE_PATH)/tool.mk

SUBPROJECTS += xpf_framework
SUBPROJECTS += libjailbreak

include $(THEOS_MAKE_PATH)/aggregate.mk

# XPF Kernel Exploit Framework
xpf_framework_OBJ_FILES = $(wildcard xpf/*.o)

# Packaging for TrollStore
after-package::
	@echo "Packing .tipa for TrollStore..."
	@mkdir -p $(THEOS_STAGING_DIR)/Payload/Star.app
	@cp -r $(THEOS_STAGING_DIR)/Applications/Star.app/* $(THEOS_STAGING_DIR)/Payload/Star.app/
	@cd $(THEOS_STAGING_DIR) && zip -r Star.tipa Payload/
	@echo "Done: Star.tipa"
