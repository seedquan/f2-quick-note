override APP_NAME := F2QuickNote
override APP_BUNDLE := $(CURDIR)/dist/F2QuickNote.app
override BINARY := $(CURDIR)/.build/release/F2QuickNote
override INSTALL_DIR := /Applications
override INSTALLED_APP := /Applications/F2QuickNote.app
CODE_SIGN_CERTIFICATE ?= Apple Development: Xiaolin Quan (548KLZK9CA)
CODE_SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -F '"$(CODE_SIGN_CERTIFICATE)"' | grep -v 'CSSMERR_' | awk 'NR == 1 { print $$2 }')

.PHONY: all privacy test build app install run clean guard-paths guard-signing-identity

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

guard-signing-identity:
	@test -n "$(CODE_SIGN_IDENTITY)" || (echo "No usable $(CODE_SIGN_CERTIFICATE) code-signing identity found. Install that certificate or pass CODE_SIGN_IDENTITY." >&2; exit 1)
	@test "$(CODE_SIGN_IDENTITY)" != "-" || (echo "Ad-hoc signing cannot preserve Accessibility permission across builds." >&2; exit 1)

app: build guard-paths guard-signing-identity
	rm -rf -- "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp Resources/F2QuickNote.icns "$(APP_BUNDLE)/Contents/Resources/F2QuickNote.icns"
	cp "$(BINARY)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@codesign --force --options runtime --sign "$(CODE_SIGN_IDENTITY)" --entitlements Resources/F2QuickNote.entitlements "$(APP_BUNDLE)"
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
