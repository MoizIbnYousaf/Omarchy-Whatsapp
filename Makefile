.PHONY: validate test manifest lint release-check dev demo

OMARCHY_SHELL_DIR ?= /usr/share/omarchy/shell
# Arch installs the Qt tools outside PATH.
export PATH := $(PATH):/usr/lib/qt6/bin

validate: test manifest lint

test:
	python3 -m py_compile bin/omawhatsapp bin/omawhatsapp_core.py bin/omawhatsapp_assets.py bin/omawhatsapp-mcp
	OMAW_SCRIPT="$(CURDIR)/bin/omawhatsapp_core.py" python3 -B -m unittest discover -s tests -v
	jq empty manifest.json

manifest:
	omarchy plugin validate .

# Validate every shipped component, including future additions.
lint:
	qmllint -I "$(OMARCHY_SHELL_DIR)" $(wildcard plugins/omawhatsapp/*.qml plugins/omawhatsapp/*.js)

release-check:
	./scripts/test

# Copy the working tree over the plugin checkout that omarchy plugin add made.
dev:
	./scripts/dev-sync

# Open the full app with repository-owned demo data (safe for screenshots).
demo:
	omarchy-shell io.github.moizibnyousaf.omawhatsapp openApp '{"demo":true}'
