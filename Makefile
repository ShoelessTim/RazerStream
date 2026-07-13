SWIFT = swiftc
SDK   = $(shell xcrun --sdk macosx --show-sdk-path)

BUILD  = .build/manual
KITOBJ = $(BUILD)/RazerStreamKit

KIT_SOURCES = \
	Sources/RazerStreamKit/Constants.swift \
	Sources/RazerStreamKit/DeviceEvent.swift \
	Sources/RazerStreamKit/DeviceCommand.swift \
	Sources/RazerStreamKit/WSFrameCodec.swift \
	Sources/RazerStreamKit/SerialTransport.swift \
	Sources/RazerStreamKit/RazerStreamDevice.swift

CLI_SOURCES = Sources/RazerStreamCLI/main.swift

KIT_FLAGS = \
	-sdk $(SDK) \
	-module-name RazerStreamKit \
	-emit-module -emit-module-path $(KITOBJ)/RazerStreamKit.swiftmodule \
	-emit-library -o $(KITOBJ)/libRazerStreamKit.dylib \
	-framework IOKit \
	-framework CoreFoundation \
	-Xlinker -install_name -Xlinker @rpath/libRazerStreamKit.dylib

CLI_FLAGS = \
	-sdk $(SDK) \
	-module-name RazerStreamCLI \
	-I $(KITOBJ) \
	-L $(KITOBJ) \
	-lRazerStreamKit \
	-framework IOKit \
	-framework CoreFoundation \
	-Xlinker -rpath -Xlinker @executable_path \
	-o $(BUILD)/rstream

TEST_SOURCES = \
	Tests/RazerStreamKitTests/WSFrameCodecTests.swift \
	Tests/RazerStreamKitTests/DeviceCommandTests.swift

TEST_FLAGS = \
	-sdk $(SDK) \
	-parse-as-library \
	-module-name RazerStreamKitTests \
	-I $(KITOBJ) \
	-L $(KITOBJ) \
	-lRazerStreamKit \
	-framework XCTest \
	-framework IOKit \
	-framework CoreFoundation \
	-Xlinker -rpath -Xlinker $(KITOBJ) \
	-o $(BUILD)/RazerStreamKitTests

APP_SOURCES = \
	Sources/RazerStreamApp/Profile.swift \
	Sources/RazerStreamApp/ActionEngine.swift \
	Sources/RazerStreamApp/TileRenderer.swift \
	Sources/RazerStreamApp/DeviceManager.swift \
	Sources/RazerStreamApp/ContentView.swift \
	Sources/RazerStreamApp/RazerStreamApp.swift

APP_FLAGS = \
	-sdk $(SDK) \
	-parse-as-library \
	-module-name RazerStreamApp \
	-I $(KITOBJ) \
	-L $(KITOBJ) \
	-lRazerStreamKit \
	-framework IOKit \
	-framework CoreFoundation \
	-framework AppKit \
	-framework SwiftUI \
	-Xlinker -rpath -Xlinker @executable_path \
	-o $(BUILD)/RazerStreamApp

.PHONY: all kit cli app test clean run

all: cli

$(KITOBJ):
	mkdir -p $(KITOBJ)

kit: $(KITOBJ)
	$(SWIFT) $(KIT_SOURCES) $(KIT_FLAGS)

cli: kit
	$(SWIFT) $(CLI_SOURCES) $(CLI_FLAGS)

app: kit
	$(SWIFT) $(APP_SOURCES) $(APP_FLAGS)
	cp $(KITOBJ)/libRazerStreamKit.dylib $(BUILD)/

test: kit
	$(SWIFT) $(TEST_SOURCES) $(TEST_FLAGS)
	$(BUILD)/RazerStreamKitTests

run: cli
	$(BUILD)/rstream monitor

clean:
	rm -rf $(BUILD)

# Copy the dylib next to the binary so @rpath resolves
install: cli
	cp $(KITOBJ)/libRazerStreamKit.dylib $(BUILD)/
	@echo "Binary: $(BUILD)/rstream"
	@echo "Run: $(BUILD)/rstream monitor"
