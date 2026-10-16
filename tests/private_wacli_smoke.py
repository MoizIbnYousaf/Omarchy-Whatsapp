#!/usr/bin/python3
"""Actual dependency process boundary; no account, store or network is opened."""
import json
from pathlib import Path
import subprocess
import sys
import time
binary=Path(sys.argv[1]).resolve()
secret="SYNTHETIC private Grüße 世界\nsecond line"
cap=json.loads(subprocess.check_output([str(binary),"--private-args-version"],text=True))
assert cap=={"protocol":1,"max_bytes":65536}
child=subprocess.Popen([str(binary),"--private-args-stdin"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
# Child waits for EOF before dispatch, giving a deterministic inspection point.
try:
 cmdline=Path(f"/proc/{child.pid}/cmdline").read_bytes()
 environ=Path(f"/proc/{child.pid}/environ").read_bytes()
 assert secret.encode() not in cmdline and secret.encode() not in environ
 payload=json.dumps(["--read-only","--json","send","text","--to","123@s.whatsapp.net","--message",secret]).encode()
 stdout,stderr=child.communicate(payload,timeout=5)
 assert child.returncode!=0
 assert secret.encode() not in stdout+stderr
finally:
 if child.poll() is None:child.kill();child.wait()
for payload in [b"[",b"[]",b" "+b"x"*65536,b'["--private-args-stdin"]']:
 result=subprocess.run([str(binary),"--private-args-stdin"],input=payload,capture_output=True,timeout=5)
 assert result.returncode!=0
child=subprocess.Popen([str(binary),"--private-args-stdin"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
started=time.monotonic()
try:
 child.wait(timeout=5)
 assert child.returncode!=0 and time.monotonic()-started<4.5
finally:
 if child.poll() is None:child.kill();child.wait()
 child.stdin.close();child.stdout.close();child.stderr.close()
print("Private dependency protocol, procfs, readonly dispatch, malformed input and deadline passed.")
