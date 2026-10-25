.PHONY: validate test manifest lint release-check dev demo

OMARCHY_SHELL_DIR ?= /usr/share/omarchy/shell
# Arch installs the Qt tools outside PATH.
export PATH := $(PATH):/usr/lib/qt6/bin
# Nothing in the checkout may gain a .pyc while these checks run: the shell
# watches this folder and hot-reloads on any write, which can crash it
# (Omarchy #11929 / #12859). The checks below import the helper in child
# processes, so the environment, not just -B, has to carry this.
export PYTHONDONTWRITEBYTECODE := 1
# py_compile's own check, compile() exactly as its loader calls it, without
# the .pyc that py_compile writes even with the variable above set. It runs
# from the environment because make gives each line of a recipe its own shell.
define python_syntax_check
import sys
for path in sys.argv[1:]:
    with open(path, "rb") as source:
        compile(source.read(), path, "exec", dont_inherit=True)
endef
export python_syntax_check

validate: test manifest lint

test:
	# Compile-check without writing .pyc beside the sources. The shell watches
	# this folder and hot-reloads on any write, which can crash it (Omarchy
	# #11929 / #12859); the launcher's bytecode belongs in the user cache.
	python3 -c "$$python_syntax_check" bin/omawhatsapp bin/omawhatsapp_core.py bin/omawhatsapp_assets.py bin/omawhatsapp-mcp
	OMAW_SCRIPT="$(CURDIR)/bin/omawhatsapp_core.py" python3 -B -m unittest discover -s tests -v
	jq empty manifest.json

manifest:
	omarchy plugin validate .

# Validate every shipped component, including future additions.
lint:
	qmllint -I "$$(./scripts/build-inputs)" -I "$(OMARCHY_SHELL_DIR)" $(wildcard plugins/omawhatsapp/*.qml plugins/omawhatsapp/*.js)

release-check:
	./scripts/test

# Copy the working tree over the plugin checkout that omarchy plugin add made.
dev:
	./scripts/dev-sync

# Open the full app with repository-owned demo data (safe for screenshots).
demo:
	omarchy-shell io.github.moizibnyousaf.omawhatsapp openApp '{"demo":true}'
