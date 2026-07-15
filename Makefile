APP = Vigil
DIST = dist/$(APP).app

.PHONY: build bundle install run clean

build:
	swift build -c release

bundle: build
	rm -rf $(DIST)
	mkdir -p $(DIST)/Contents/MacOS $(DIST)/Contents/Resources
	cp .build/release/$(APP) $(DIST)/Contents/MacOS/
	cp Resources/Info.plist $(DIST)/Contents/
	if [ -f Resources/$(APP).icns ]; then cp Resources/$(APP).icns $(DIST)/Contents/Resources/; fi
	codesign --force --sign - $(DIST)

install: bundle
	rm -rf /Applications/$(APP).app
	cp -R $(DIST) /Applications/

run: bundle
	open $(DIST)

clean:
	rm -rf .build dist
