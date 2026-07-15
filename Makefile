APP_NAME := F2QuickNote
APP_BUNDLE := dist/$(APP_NAME).app
BINARY := .build/release/$(APP_NAME)
INSTALL_DIR := /Applications

.PHONY: all test build app install run clean

all: app

test:
	swift test

build:
	swift build -c release

app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp $(BINARY) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	codesign --force --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

install: app
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	cp -R $(APP_BUNDLE) $(INSTALL_DIR)/
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

run: app
	open $(APP_BUNDLE)

clean:
	rm -rf .build dist
