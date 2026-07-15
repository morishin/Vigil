APP = Vigil
DIST = dist/$(APP).app

.PHONY: build bundle install run clean

build:
	swift build -c release

bundle: build
	rm -rf $(DIST)
	mkdir -p $(DIST)/Contents/MacOS $(DIST)/Contents/Resources
	cp .build/release/$(APP) $(DIST)/Contents/MacOS/
	cp -R .build/release/$(APP)_$(APP).bundle $(DIST)/Contents/Resources/
	cp Resources/Info.plist $(DIST)/Contents/
	xcrun actool Resources/$(APP).icon --compile $(DIST)/Contents/Resources \
		--platform macosx --minimum-deployment-target 14.0 \
		--app-icon $(APP) --include-all-app-icons \
		--output-partial-info-plist /dev/null > /dev/null
	codesign --force --sign - $(DIST)

install: bundle
	rm -rf /Applications/$(APP).app
	cp -R $(DIST) /Applications/

run: bundle
	open $(DIST)

clean:
	rm -rf .build dist
