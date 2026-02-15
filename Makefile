PROJECT := JustPlayNative.xcodeproj
SCHEME := JustPlayNative
DESTINATION := platform=macOS,arch=arm64
APP_NAME := JustPlay.app

.PHONY: bootstrap generate setup build run help

bootstrap:
	carthage bootstrap --use-xcframeworks --platform macOS

generate:
	xcodegen generate --use-cache

setup: bootstrap generate

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' build

run:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath ./.derivedData build && open "./.derivedData/Build/Products/Debug/$(APP_NAME)"

help:
	@printf "Available targets:\n"
	@printf "  make bootstrap  # Fetch VLCKit via Carthage\n"
	@printf "  make generate   # Generate Xcode project from project.yml\n"
	@printf "  make setup      # bootstrap + generate\n"
	@printf "  make build      # Build app for macOS arm64\n"
	@printf "  make run        # Build and open app\n"
