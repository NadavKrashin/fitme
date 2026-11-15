# Every command CI runs is a target here, so "green locally" means "green in CI".
# Run `make help` for the list.

SHELL := /bin/bash
# macOS ships GNU Make 3.81, which ignores .SHELLFLAGS, so piped recipes set pipefail themselves.
PIPEFAIL := set -o pipefail;

PROJECT    := FitMe.xcodeproj
SCHEME     := FitMe
DERIVED    := DerivedData
# Newest available iPhone simulator; override with `make test SIMULATOR="iPhone 17 Pro"`.
SIMULATOR  ?= $(shell xcrun simctl list devices available | grep -oE 'iPhone [0-9]+( Pro)?( Max)?' | sort -V | tail -1)
DESTINATION = platform=iOS Simulator,name=$(SIMULATOR)
XCODEBUILD := xcodebuild -project $(PROJECT) -derivedDataPath $(DERIVED)

.PHONY: help bootstrap project open format lint test test-engine test-app test-proxy verify-release screenshots icons release clean

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

bootstrap: ## Install tools from the Brewfile and generate the Xcode project
	brew bundle --file=Brewfile
	$(MAKE) project

project: ## Generate FitMe.xcodeproj from project.yml
	xcodegen generate --quiet

open: project ## Generate and open the project in Xcode
	open $(PROJECT)

format: ## Format all Swift code in place
	swiftformat .

lint: ## Check formatting and lint (what CI runs)
	swiftformat --lint .
	swiftlint lint --strict --quiet

test: test-engine test-proxy test-app ## Run all tests

test-engine: ## FitEngine package tests (fast, no simulator)
	cd Packages/FitEngine && swift test

test-proxy: ## Claude proxy (server/claude-proxy): typecheck and tests, no Cloudflare account needed
	cd server/claude-proxy && npm ci --no-audit --no-fund && npm run typecheck && npm test

test-app: project ## App tests on the iOS Simulator
	$(PIPEFAIL) $(XCODEBUILD) -scheme $(SCHEME) -destination '$(DESTINATION)' test | xcbeautify

verify-release: project ## Build Release and fail if any demo data made it into the app
	$(PIPEFAIL) $(XCODEBUILD) -scheme $(SCHEME) -configuration Release -destination 'generic/platform=iOS Simulator' \
		build CODE_SIGNING_ALLOWED=NO | xcbeautify
	scripts/verify-release.sh "$(DERIVED)/Build/Products/Release-iphonesimulator/FitMe.app"

SCREENSHOT_SIMULATOR ?= iPhone 18 Pro Max
SCREENSHOT_DIR := $(CURDIR)/docs/store/screenshots

screenshots: project ## App Store screenshots (6.9-inch iPhone) into docs/store/screenshots
	mkdir -p "$(SCREENSHOT_DIR)"
	xcrun simctl boot "$(SCREENSHOT_SIMULATOR)" 2>/dev/null || true
	xcrun simctl status_bar "$(SCREENSHOT_SIMULATOR)" override --time 9:41 --batteryState charged \
		--batteryLevel 100 --wifiBars 3 --cellularBars 4
	$(PIPEFAIL) TEST_RUNNER_SCREENSHOT_DIR="$(SCREENSHOT_DIR)" $(XCODEBUILD) -scheme FitMeScreenshots \
		-destination 'platform=iOS Simulator,name=$(SCREENSHOT_SIMULATOR)' test | xcbeautify

icons: ## Re-render app icons
	swift scripts/make-app-icons.swift

release: ## Ship to production: make release VERSION=1.2.0
	scripts/release.sh "$(VERSION)"

clean: ## Remove build output and the generated project
	rm -rf $(DERIVED) $(PROJECT) Packages/FitEngine/.build
