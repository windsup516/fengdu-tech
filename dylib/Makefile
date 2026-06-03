# DFOverlay.dylib — Injected into Delta Force game process
# Renders Metal+ImGui overlay directly in game's address space
# Built by Theos toolchain as a subproject

ARCHS = arm64
TARGET = iphone:16.5
DEBUG = 0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = DFOverlay
DFOverlay_FILES = \
	DFCheatMain.mm \
	../include/imgui/imgui.cpp \
	../include/imgui/imgui_draw.cpp \
	../include/imgui/imgui_tables.cpp \
	../include/imgui/imgui_widgets.cpp \
	../include/imgui/backends/imgui_impl_metal.mm
DFOverlay_CFLAGS = -fobjc-arc -std=c++17 -stdlib=libc++ \
	-I../include -I../include/imgui -I../include/imgui/backends -I. -I../src \
	-Wno-error=unused-const-variable -Wno-error=unused-variable -Wno-error=unused-function \
	-Wno-error=nullability-completeness -Wno-error=incompatible-pointer-types
DFOverlay_CCFLAGS = -std=c++17 -stdlib=libc++ \
	-I../include -I../include/imgui -I../include/imgui/backends -I. -I../src
DFOverlay_LDFLAGS = -dynamiclib -install_name @executable_path/Frameworks/DFOverlay.dylib \
	-Wl,-undefined,dynamic_lookup \
	-lz -lobjc -framework UIKit -framework Metal \
	-framework MetalKit -framework CoreGraphics \
	-framework Foundation -framework CoreText \
	-framework IOSurface -framework QuartzCore

include $(THEOS_MAKE_PATH)/library.mk
