PROJECT := JustPlayNative.xcodeproj
SCHEME := JustPlayNative
DESTINATION := platform=macOS,arch=arm64
APP_NAME := JustPlay.app
DERIVED_DATA := ./.derivedData
APP_BUNDLE := $(DERIVED_DATA)/Build/Products/Debug/$(APP_NAME)
APPLICATIONS_DIR ?= /Applications

.PHONY: bootstrap generate setup build run install help

bootstrap:
	carthage bootstrap --use-xcframeworks --platform macOS

generate:
	xcodegen generate --use-cache

setup: bootstrap generate

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' build

run:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) build && open "$(APP_BUNDLE)"

install:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) build && rm -rf "$(APPLICATIONS_DIR)/$(APP_NAME)" && ditto "$(APP_BUNDLE)" "$(APPLICATIONS_DIR)/$(APP_NAME)" && open "$(APPLICATIONS_DIR)/$(APP_NAME)"

help:
	@printf "Available targets:\n"
	@printf "  make bootstrap  # Fetch VLCKit via Carthage\n"
	@printf "  make generate   # Generate Xcode project from project.yml\n"
	@printf "  make setup      # bootstrap + generate\n"
	@printf "  make build      # Build app for macOS arm64\n"
	@printf "  make run        # Build and open app\n"
	@printf "  make install    # Build, copy app to /Applications, and open\n"
	@printf "  make install APPLICATIONS_DIR=~/Applications\n"
