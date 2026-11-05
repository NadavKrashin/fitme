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

.PHONY: help bootstrap project open format lint test test-engine test-app verify-release icons release clean

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

test: test-engine test-app ## Run all tests

test-engine: ## FitEngine package tests (fast, no simulator)
	cd Packages/FitEngine && swift test

test-app: project ## App tests on the iOS Simulator
	$(PIPEFAIL) $(XCODEBUILD) -scheme $(SCHEME) -destination '$(DESTINATION)' test CODE_SIGNING_ALLOWED=NO | xcbeautify

verify-release: project ## Build Release and fail if any demo data made it into the app
	$(PIPEFAIL) $(XCODEBUILD) -scheme $(SCHEME) -configuration Release -destination 'generic/platform=iOS Simulator' \
		build CODE_SIGNING_ALLOWED=NO | xcbeautify
	scripts/verify-release.sh "$(DERIVED)/Build/Products/Release-iphonesimulator/FitMe.app"

icons: ## Re-render app icons
	swift scripts/make-app-icons.swift

release: ## Ship to production: make release VERSION=1.2.0
	scripts/release.sh "$(VERSION)"

clean: ## Remove build output and the generated project
	rm -rf $(DERIVED) $(PROJECT) Packages/FitEngine/.build
