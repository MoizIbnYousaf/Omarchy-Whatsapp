"""Execute the shipped skill examples with synthetic values and a fake helper."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skills/omawhatsapp"


def blocks(path):
    return re.findall(r"```bash\n(.*?)```", path.read_text(), re.S)


class AgentRequests(unittest.TestCase):
    def test_previous_builder_exposes_synthetic_text_in_procfs(self):
        text = "SYNTHETIC-PRIVATE-previous-builder"
        with subprocess.Popen(["jq", "-c", "--arg", "text", text, "{text:$text}"],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE) as process:
            try:
                deadline = time.monotonic() + 2
                argv = b""
                while time.monotonic() < deadline and text.encode() not in argv:
                    argv = Path(f"/proc/{process.pid}/cmdline").read_bytes()
                    if text.encode() not in argv:
                        time.sleep(0.005)  # exec may briefly publish an empty cmdline
                self.assertIn(text.encode(), argv)
            finally:
                process.kill(); process.communicate()

    def test_no_documented_jq_argument_interpolation(self):
        for path in SKILL.rglob("*.md"):
            for block in blocks(path):
                self.assertNotRegex(block, r"--arg(?:json)?\b", str(path))

    def test_every_private_request_example_round_trips_without_argv_or_env(self):
        operation_blocks = blocks(SKILL / "references/operations.md")
        setup = operation_blocks[0]
        marker = "SYNTHETIC-PRIVATE-"
        text = marker + 'Unicode ☃ "quotes" \\ slash\n$(touch should-not-exist) `literal`\n'
        values = {
            "resolved_jid": marker + "chat", "row_account": marker + "account",
            "message": text, "requested_name": text, "requested_query": text,
            "reply_id": marker + "reply", "mention_jids_json": json.dumps([marker + "mention"]),
            "caption": text, "local_paths_json": json.dumps(["/tmp/" + text]),
            "action": "pin", "args_json": json.dumps(["messages", "search", text]),
            "resolved_group_jid": marker + "group", "poll_id": marker + "poll",
            "chosen_option": text,
        }
        examples = [b for b in operation_blocks[1:] if "oma_request " in b]
        examples += [b for b in blocks(SKILL / "references/wacli-parity.md") if "oma_request " in b]
        expected = [
            {"jid": values["resolved_jid"], "account": values["row_account"], "text": text},
            {"query": text}, {"jid": values["resolved_jid"], "query": text},
            {"jid": values["resolved_jid"]},
            {"jid": values["resolved_jid"], "text": text, "reply_id": values["reply_id"],
             "mentions": [marker + "mention"]},
            {"jid": values["resolved_jid"], "caption": text, "paths": ["/tmp/" + text]},
            {"jid": values["resolved_jid"], "action": "pin"},
            {"args": ["messages", "search", text]},
        ]
        # The final advanced block contains three examples, including a static local read.
        expected_advanced = [
            {"args": ["calls", "list", "--limit", "20"]},
            {"args": ["groups", "info", "--jid", marker + "group"], "authorization": "remote-read"},
            {"args": ["poll", "vote", "--to", marker + "chat", "--id", marker + "poll",
                      "--option", text], "authorization": "whatsapp-write"},
        ]
        self.assertEqual(len(examples), 9)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            observations = root / "observations.jsonl"
            # Hold each actual jq process at stdin and inspect its procfs argv/env
            # before feeding it data. This tests executable documentation, not a copy.
            jq = root / "jq"
            jq.write_text("#!/usr/bin/python3\n" + f'''
import json, os, pathlib, subprocess, sys
data = sys.stdin.buffer.read()
p = subprocess.Popen([{shutil.which('jq')!r}, *sys.argv[1:]], stdin=subprocess.PIPE)
try:
    argv = pathlib.Path(f"/proc/{{p.pid}}/cmdline").read_bytes()
    environ = pathlib.Path(f"/proc/{{p.pid}}/environ").read_bytes()
    assert b"SYNTHETIC-PRIVATE-" not in argv + environ
    with open({str(observations)!r}, "a") as log:
        log.write(json.dumps({{"argv": argv.decode(), "private_in_env": False}}) + "\\n")
    p.communicate(data, timeout=5)
finally:
    if p.poll() is None:
        p.kill(); p.wait()
sys.exit(p.returncode)
''')
            jq.chmod(0o700)
            helper = root / "fake-helper"
            helper.write_text("#!/usr/bin/python3\n" + '''
import json, os, pathlib, sys
assert b"SYNTHETIC-PRIVATE-" not in pathlib.Path(f"/proc/{os.getpid()}/cmdline").read_bytes()
assert b"SYNTHETIC-PRIVATE-" not in pathlib.Path(f"/proc/{os.getpid()}/environ").read_bytes()
print(json.dumps(json.load(sys.stdin), ensure_ascii=False))
''')
            helper.chmod(0o700)
            bindings = "names=(" + " ".join(values) + ")\ni=0\n"
            bindings += "while IFS= read -r -d '' value; do builtin printf -v \"${names[i]}\" '%s' \"$value\"; ((i+=1)); done\n"
            payload = b"".join(v.encode() + b"\0" for v in values.values())
            env = {**os.environ, "PATH": str(root) + ":" + os.environ["PATH"]}
            for index, example in enumerate(examples):
                with self.subTest(example=index):
                    script = setup + "\n" + bindings + f"oma={str(helper)!r}\n" + example
                    result = subprocess.run(["bash", "--noprofile", "--norc", "-c", script],
                                            input=payload, capture_output=True, env=env, timeout=15)
                    self.assertEqual(result.returncode, 0, result.stderr.decode())
                    actual = [json.loads(line) for line in result.stdout.splitlines()]
                    self.assertEqual(actual, [expected[index]] if index < 8 else expected_advanced)
            self.assertGreaterEqual(len(observations.read_text().splitlines()), 15)


if __name__ == "__main__":
    unittest.main()
