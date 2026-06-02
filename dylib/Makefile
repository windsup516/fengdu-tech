# DFOverlay.dylib — Injected into Delta Force game process
# Renders Metal+ImGui overlay directly in game's address space
# No SBS needed: game is always foreground, render context never dies

ARCHS = arm64
TARGET = iphone:13.0
DEBUG = 0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = DFOverlay
DFOverlay_FILES = \
	DFOverlayController.mm \
	../src/MetalRenderer.mm \
	../src/ImGuiAdapter.mm \
	../include/imgui/imgui.cpp \
	../include/imgui/imgui_draw.cpp \
	../include/imgui/imgui_tables.cpp \
	../include/imgui/imgui_widgets.cpp \
	../include/imgui/backends/imgui_impl_metal.mm
DFOverlay_CFLAGS = -fobjc-arc -I../include -I../include/imgui -I../include/imgui/backends \
	-Wno-error=unused-const-variable -Wno-error=unused-variable -Wno-error=unused-function \
	-Wno-error=nullability-completeness -Wno-error=incompatible-pointer-types
DFOverlay_OBJCCFLAGS = -fobjc-arc -std=c++17 -stdlib=libc++ -I../include -I../include/imgui -I../include/imgui/backends \
	-Wno-error=unused-const-variable -Wno-error=unused-variable -Wno-error=unused-function \
	-Wno-error=nullability-completeness
DFOverlay_CCFLAGS = -std=c++17 -stdlib=libc++ -I../include -I../include/imgui -I../include/imgui/backends
DFOverlay_LDFLAGS = -lz -lobjc -framework UIKit -framework Metal \
	-framework MetalKit -framework CoreGraphics \
	-framework Foundation -framework CoreText \
	-framework IOSurface -framework QuartzCore

include $(THEOS_MAKE_PATH)/library.mk
