APP = Vigil
DIST = dist/$(APP).app

# Overridden by the release workflow: universal build + Developer ID signing
BUILD_FLAGS ?=
RELEASE_DIR ?= .build/release
SIGN_IDENTITY ?= -
SIGN_FLAGS ?=

.PHONY: build bundle install run clean

build:
	swift build -c release $(BUILD_FLAGS)

bundle: build
	rm -rf $(DIST)
	mkdir -p $(DIST)/Contents/MacOS $(DIST)/Contents/Resources
	cp $(RELEASE_DIR)/$(APP) $(DIST)/Contents/MacOS/
	cp -R $(RELEASE_DIR)/$(APP)_$(APP).bundle $(DIST)/Contents/Resources/
	cp Resources/Info.plist $(DIST)/Contents/
	xcrun actool Resources/$(APP).icon --compile $(DIST)/Contents/Resources \
		--platform macosx --minimum-deployment-target 14.0 \
		--app-icon $(APP) --include-all-app-icons \
		--output-partial-info-plist /dev/null > /dev/null
	codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_FLAGS) $(DIST)

install: bundle
	rm -rf /Applications/$(APP).app
	cp -R $(DIST) /Applications/

run: bundle
	open $(DIST)

clean:
	rm -rf .build dist
