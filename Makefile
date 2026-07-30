override APP_NAME := F2QuickNote
override APP_BUNDLE := $(CURDIR)/dist/F2QuickNote.app
override BINARY := $(CURDIR)/.build/release/F2QuickNote
override INSTALL_DIR := /Applications
override INSTALLED_APP := /Applications/F2QuickNote.app

.PHONY: all privacy test build app install run clean guard-paths

all: app

privacy:
	node scripts/privacy-check.mjs

test: privacy
	swift test

build: privacy
	swift build -c release
	node scripts/release-privacy-check.mjs "$(BINARY)"

guard-paths:
	@test "$(APP_BUNDLE)" = "$(CURDIR)/dist/F2QuickNote.app"
	@test "$(BINARY)" = "$(CURDIR)/.build/release/F2QuickNote"
	@test "$(INSTALLED_APP)" = "/Applications/F2QuickNote.app"
	@test ! -L "$(CURDIR)/dist"
	@test ! -L "$(APP_BUNDLE)"
	@test ! -L "$(INSTALLED_APP)"

app: build guard-paths
	rm -rf -- "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp "$(BINARY)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	codesign --force --options runtime --sign - --entitlements Resources/F2QuickNote.entitlements "$(APP_BUNDLE)"
	@codesign -d --entitlements - "$(APP_BUNDLE)" 2>&1 | grep -q 'com.apple.security.automation.apple-events'
	node scripts/release-privacy-check.mjs "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

install: app
	rm -rf -- "$(INSTALLED_APP)"
	cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/"
	node scripts/release-privacy-check.mjs "$(INSTALLED_APP)"
	@echo "Installed to $(INSTALLED_APP)"

run: app
	open "$(APP_BUNDLE)"

clean: guard-paths
	swift package clean
	rm -rf -- "$(CURDIR)/dist"
