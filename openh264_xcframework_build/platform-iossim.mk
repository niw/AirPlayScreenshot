include $(SRC_PATH)build/arch.mk
SHAREDLIB_DIR = $(PREFIX)/lib
SHAREDLIBSUFFIX = dylib
SHAREDLIBSUFFIXFULLVER=$(FULL_VERSION).$(SHAREDLIBSUFFIX)
SHAREDLIBSUFFIXMAJORVER=$(SHAREDLIB_MAJORVERSION).$(SHAREDLIBSUFFIX)
CURRENT_VERSION := 2.4.1
COMPATIBILITY_VERSION := 2.4.1
SHLDFLAGS = -dynamiclib -twolevel_namespace -undefined dynamic_lookup \
	-fno-common -headerpad_max_install_names -install_name \
	$(SHAREDLIB_DIR)/$(LIBPREFIX)$(PROJECT_NAME).$(SHAREDLIBSUFFIXMAJORVER)
SHARED = -dynamiclib
SHARED += -current_version $(CURRENT_VERSION) -compatibility_version $(COMPATIBILITY_VERSION)
CXX = clang++
CC = clang
SDK_MIN = 16.0
SDKROOT := $(shell xcrun --sdk iphonesimulator --show-sdk-path)
TARGET_TRIPLE = arm64-apple-ios$(SDK_MIN)-simulator
CFLAGS += -target $(TARGET_TRIPLE) -isysroot $(SDKROOT) -DAPPLE_IOS -Wall -fPIC -MMD -MP
CXXFLAGS += -stdlib=libc++ -std=c++17
LDFLAGS += -target $(TARGET_TRIPLE) -isysroot $(SDKROOT) -stdlib=libc++
ASMFLAGS += -target $(TARGET_TRIPLE) -isysroot $(SDKROOT)
ifeq ($(USE_STACK_PROTECTOR), Yes)
CFLAGS += -fstack-protector-all
endif
