.PHONY: validate test manifest lint release-check

OMARCHY_SHELL_DIR ?= /usr/share/omarchy/shell

validate: test manifest lint

test:
	python3 -m py_compile bin/omawhatsapp
	OMAW_SCRIPT="$(CURDIR)/bin/omawhatsapp" python3 -B -m unittest discover -s tests -v
	jq empty manifest.json plugins/omawhatsapp/manifest.json

manifest:
	omarchy plugin validate .

lint:
	qmllint -I "$(OMARCHY_SHELL_DIR)" plugins/omawhatsapp/MediaViewerLogic.js plugins/omawhatsapp/DropdownModel.js plugins/omawhatsapp/SettingsPolicy.js plugins/omawhatsapp/AccountModel.js plugins/omawhatsapp/KeyboardNavigation.qml plugins/omawhatsapp/App.qml plugins/omawhatsapp/Service.qml plugins/omawhatsapp/MessageBubble.qml plugins/omawhatsapp/MediaBubble.qml plugins/omawhatsapp/MediaViewer.qml plugins/omawhatsapp/MediaViewerModel.qml plugins/omawhatsapp/BarWidget.qml plugins/omawhatsapp/Dropdown.qml

release-check:
	./scripts/test
