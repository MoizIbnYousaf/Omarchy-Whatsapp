"""The private wacli builder applies its patches the same way in every locale.

Everything is synthetic except `git apply`: a copy of the builder runs against
generated patches and a stand-in source checkout, Go toolchain and compiler.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
BUILDER = REPOSITORY / "scripts/build-private-wacli"
REAL_GIT = shutil.which("git")
# Message settings under which git may answer in another language.
LOCALES = (
    {"LANG": "de_DE.UTF-8"},
    {"LANG": "pt_BR.UTF-8"},
    {"LANG": "en_US.UTF-8", "LANGUAGE": "de"},
    {"LANG": "en_US.UTF-8", "LANGUAGE": "pt_BR"},
)


def builder_constants() -> dict:
    """Read the builder's pinned commit, label and patch list without running it."""
    text = BUILDER.read_text()
    constants: dict = {}
    exec(text[text.index("BASE = "):text.index("parser=")], constants)
    return constants


def neutral_environment() -> dict:
    return {
        key: value for key, value in os.environ.items()
        if not key.startswith(("LC_", "LANG", "GIT_"))
    }


def translated_environment(root: Path) -> dict | None:
    """Return a locale in which git's own messages are translated here, if any."""
    probe = root / "probe"
    probe.mkdir()
    for locale in LOCALES:
        (probe / "f.txt").write_text("a\n")
        result = subprocess.run(
            [REAL_GIT, "apply", "--verbose", "-"],
            input=b"--- a/f.txt\n+++ b/f.txt\n@@ -1 +1 @@\n-a\n+b\n",
            cwd=probe, capture_output=True, timeout=30,
            env=dict(neutral_environment(), GIT_CEILING_DIRECTORIES=str(root), **locale),
        )
        if result.returncode == 0 and b"Applied patch" not in result.stdout + result.stderr:
            return dict(neutral_environment(), **locale)
    return None


def write_executable(path: Path, text: str) -> None:
    path.write_text(text)
    path.chmod(0o755)


class PrivateBuildTests(unittest.TestCase):
    def setUp(self) -> None:
        if REAL_GIT is None:
            self.skipTest("git is not installed")
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.environment = translated_environment(self.root)
        if self.environment is None:
            self.skipTest("git prints no translated messages on this system")
        self.constants = builder_constants()
        self.checkout = self.root / "checkout"
        self.source = self.root / "source"
        (self.checkout / "scripts").mkdir(parents=True)
        (self.checkout / "dependencies").mkdir()
        shutil.copy2(BUILDER, self.checkout / "scripts/build-private-wacli")
        # Two files exist upstream so that patches modify as well as add.
        self.files = {"cmd/wacli/send_ipc.go": ["package main"], "internal/wa/contacts.go": ["package wa"]}
        for path, lines in self.files.items():
            (self.source / path).parent.mkdir(parents=True, exist_ok=True)
            (self.source / path).write_text("".join(line + "\n" for line in lines))
        for _, name, _, sentinels in self.constants["PATCHES"]:
            (self.checkout / "dependencies" / name).write_text(self.synthetic_patch(name, sentinels))
        self.install_stand_ins()
        # Build inside an enclosing repository, where an unguarded git apply
        # skips every path.
        self.temp_parent = self.root / "enclosing"
        subprocess.run([REAL_GIT, "init", "-q", str(self.temp_parent)], check=True,
                       env=dict(neutral_environment(), GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1"))
        self.environment.update(
            PATH=f"{self.root / 'bin'}{os.pathsep}{self.environment.get('PATH', os.defpath)}",
            TMPDIR=str(self.temp_parent),
        )
        self.output = self.root / "out/wacli"
        self.provenance = self.root / "build-evidence.json"

    def synthetic_patch(self, name: str, sentinels) -> str:
        """Add each sentinel as a line of its file, the way the real patch would."""
        text = f"Synthetic {name}: git apply ignores this header.\n\n"
        changes: dict[str, list[str]] = {}
        for path, sentinel in sentinels:
            changes.setdefault(path, []).append(f"// {sentinel}")
        for path, added in changes.items():
            before = self.files.get(path)
            text += f"diff --git a/{path} b/{path}\n"
            if before is None:
                text += f"new file mode 100644\n--- /dev/null\n+++ b/{path}\n@@ -0,0 +1,{len(added)} @@\n"
            else:
                text += f"--- a/{path}\n+++ b/{path}\n@@ -1,{len(before)} +1,{len(before) + len(added)} @@\n"
                text += "".join(f" {line}\n" for line in before)
            text += "".join(f"+{line}\n" for line in added)
            self.files[path] = (before or []) + added
        return text

    def install_stand_ins(self) -> None:
        """git answers for the pinned commit but applies for real; go and cc never compile."""
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        capability = json.dumps({"protocol": 1, "max_bytes": 65536, "build": self.constants["EXTENSION"]})
        binary = f"#!/bin/sh\necho '{capability}'\n"
        write_executable(bin_dir / "git", f"""#!{sys.executable}
import os, sys, tarfile
from pathlib import Path
source, base, real = {str(self.source)!r}, {self.constants["BASE"]!r}, {REAL_GIT!r}
args = sys.argv[1:]
if args == ["-C", source, "rev-parse", "HEAD"]:
    print(base)
elif args == ["-C", source, "archive", base]:
    with tarfile.open(fileobj=sys.stdout.buffer, mode="w|") as tar:
        for path in sorted(Path(source).rglob("*")):
            tar.add(path, arcname=path.relative_to(source).as_posix(), recursive=False)
else:
    os.execv(real, [real, *args])
""")
        write_executable(bin_dir / "go", f"""#!{sys.executable}
import sys
from pathlib import Path
args = sys.argv[1:]
if args == ["version"]:
    print("go version synthetic")
elif args[:1] == ["build"]:
    output = Path(args[args.index("-o") + 1])
    output.write_text({binary!r})
    output.chmod(0o755)
else:
    sys.exit("unexpected go " + " ".join(args))
""")
        write_executable(bin_dir / "cc", "#!/bin/sh\necho 'cc (synthetic) 1'\n")

    def build(self) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, "-B", str(self.checkout / "scripts/build-private-wacli"), str(self.source),
             str(self.output), "--provenance", str(self.provenance)],
            env=self.environment, capture_output=True, text=True, timeout=120,
        )

    def test_translated_git_messages_still_build_every_patch(self) -> None:
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        evidence = json.loads(self.provenance.read_text())
        for key, name, _, _ in self.constants["PATCHES"]:
            data = (self.checkout / "dependencies" / name).read_bytes()
            self.assertEqual(evidence[key], hashlib.sha256(data).hexdigest(), name)
        self.assertEqual(evidence["extension"], self.constants["EXTENSION"])
        self.assertEqual(evidence["binary_sha256"], hashlib.sha256(self.output.read_bytes()).hexdigest())

    def test_a_patch_that_does_not_apply_is_reported_legibly(self) -> None:
        name = self.constants["PATCHES"][-1][1]
        patch = self.checkout / "dependencies" / name
        patch.write_text(patch.read_text().replace(" package main\n", " package synthetic\n"))
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"{name} did not apply completely", result.stderr)
        self.assertIn("patch does not apply", result.stderr)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
