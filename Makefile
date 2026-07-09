APP := dist/Screenshot Editor.app

.PHONY: app run run-fg release test clean icons

# Regenerate the app identity (Resources/AppIcon.icns + Resources/MenuBarIcon.pdf).
# The generated assets are checked in, so this only needs re-running when the design changes.
icons:
	swift scripts/make-icons.swift

app:
	scripts/bundle.sh debug

release:
	scripts/bundle.sh release

run: app
	open "$(APP)"

# Foreground run: logs stream to the terminal; Ctrl-C to quit.
run-fg: app
	"$(APP)/Contents/MacOS/ScreenshotEditor"

# Command Line Tools ship Testing.framework outside the default search paths.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := -Xswiftc -F$(CLT_DEV)/Frameworks \
	-Xlinker -F$(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib

test:
	swift test $(TEST_FLAGS)

clean:
	rm -rf .build dist
