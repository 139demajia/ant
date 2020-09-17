BGFXROOT = $(ANT3RD)
BGFXSRC = $(BGFXROOT)/bgfx
BXSRC 	= $(BGFXROOT)/bx
BIMGSRC = $(BGFXROOT)/bimg

ifeq ("$(BGFXROOT)","")
$(error BGFXROOT NOT define)
endif

BXINC = -I$(BXSRC)/include/compat/$(PLAT) -I$(BXSRC)/include
BIMGINC = -I$(BIMGSRC)/include

BGFXINC = -I$(BGFXSRC)/include $(BXINC) -I$(BGFXSRC)/src -I$(BIMGSRC)/include
BGFX3RDINC = -I$(BGFXSRC)/3rdparty -I$(BGFXSRC)/examples/common


BXLIB = -lbx$(MODE)
BIMGLIB = -lbimg$(MODE)
BIMGDECODELIB=-lbimg_decode$(MODE)

ifeq "$(PLAT)" "mingw"
BXLIB += -lpsapi
BGFXLIBDIR = $(BGFXSRC)/.build/win64_mingw-gcc/bin
BGFXLIB = -lbgfx$(MODE) $(BIMGLIB) $(BXLIB) -lstdc++ -lgdi32 -luuid
else ifeq "$(PLAT)" "osx"
BGFXLIBDIR = $(BGFXSRC)/.build/osx64_clang/bin
BGFXLIB = -lbgfx$(MODE) $(BIMGLIB) $(BXLIB) -lstdc++
BGFXLIB += -framework Foundation -framework Metal -framework QuartzCore -framework Cocoa
else ifeq "$(PLAT)" "ios"
BGFXLIBDIR = $(BGFXSRC)/.build/ios-arm64/bin
BGFXLIB = -lbgfx$(MODE) $(BIMGLIB) $(BXLIB) -lstdc++
BGFXLIB += -framework CoreFoundation -framework Foundation -framework OpenGLES -framework UIKit -framework QuartzCore -weak_framework Metal
endif

BGFXUTILLIB = -lexample-common$(MODE)
