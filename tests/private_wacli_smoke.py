#!/usr/bin/python3
"""Actual dependency process boundary; no account, store or network is opened."""
import fcntl
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
binary=Path(sys.argv[1]).resolve()
secret="SYNTHETIC private Grüße 世界\nsecond line"
cap=json.loads(subprocess.check_output([str(binary),"--private-args-version"],text=True))
assert cap=={"protocol":1,"max_bytes":65536,"build":"omawhatsapp.3"}
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
def delegated(reply,timeout):
 """One send through a synthetic sync delegate: a held store lock and socket."""
 with tempfile.TemporaryDirectory() as tmp:
  store=Path(tmp)/"store";store.mkdir(mode=0o700)
  with open(store/"LOCK","w") as lock,socket.socket(socket.AF_UNIX) as server:
   fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
   server.bind(str(store/".send.sock"));server.listen(1);server.settimeout(5)
   def serve():
    conn,_=server.accept()
    with conn:
     conn.makefile("rb").readline()
     if reply is None:time.sleep(2)
     else:conn.sendall(json.dumps(reply).encode()+b"\n")
   thread=threading.Thread(target=serve,daemon=True);thread.start()
   args=["--store",str(store),"--timeout",timeout,"--json","send","text","--to","123@s.whatsapp.net","--message",secret]
   result=subprocess.run([str(binary),"--private-args-stdin"],input=json.dumps(args).encode(),capture_output=True,timeout=10)
   thread.join(5)
  output=result.stdout+result.stderr
  assert result.returncode!=0 and secret.encode() not in output and str(store).encode() not in output
  return json.loads(result.stderr)["error"]
refused={"ok":False,"error":"request timed out in the send queue before dispatch; it was not sent"}
dispatched={"ok":False,"error":"delegated text failed after dispatch and may still have gone through; check before retrying: context deadline exceeded"}
assert delegated(refused,"5s")=="Private WhatsApp command was not sent."
assert delegated(dispatched,"5s")=="Private WhatsApp command outcome is unknown."
assert delegated(None,"300ms")=="Private WhatsApp command outcome is unknown."
assert delegated({"ok":False,"error":secret},"5s")=="Private WhatsApp command failed."
print("Private dependency protocol, build label, procfs, readonly dispatch, malformed input, deadline and delegated outcomes passed.")
