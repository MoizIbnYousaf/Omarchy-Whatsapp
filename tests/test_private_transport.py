"""Private stdin transport uses only synthetic processes and data."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock
spec=importlib.util.spec_from_file_location("private_core",Path(__file__).resolve().parents[1]/"bin/omawhatsapp_core.py")
core=importlib.util.module_from_spec(spec);spec.loader.exec_module(core)

class PrivateTransportTests(unittest.TestCase):
 def test_duplex_input_does_not_deadlock_on_full_output_pipe(self):
  payload=b"x"*60000
  code="import sys;sys.stdout.buffer.write(b'y'*60000);sys.stdout.flush();data=sys.stdin.buffer.read();sys.stdout.buffer.write(data)"
  result=core.run_bounded([sys.executable,"-c",code],input_bytes=payload,timeout=4,stdout_limit=130000,text=False)
  self.assertEqual(result.stdout,b"y"*60000+payload)
 def test_stalled_reader_deadline(self):
  start=time.monotonic()
  with self.assertRaises(subprocess.TimeoutExpired):
   core.run_bounded([sys.executable,"-c","import time;time.sleep(10)"],input_bytes=b"x"*60000,timeout=.15,stdout_limit=1024)
  self.assertLess(time.monotonic()-start,2)
 def test_early_exit_and_output_limit(self):
  result=core.run_bounded([sys.executable,"-c","pass"],input_bytes=b"x"*60000,timeout=2,stdout_limit=1024)
  self.assertEqual(result.returncode,0)
  with self.assertRaises(core.ProcessOutputLimitExceeded):
   core.run_bounded([sys.executable,"-c","print('x'*10000)"],input_bytes=b"x",timeout=2,stdout_limit=100)
 def test_private_content_never_enters_argv_or_environment(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);binary=root/"fake-wacli"
   binary.write_text("#!"+sys.executable+"\nimport json,os,sys\nif sys.argv[1:]==['--private-args-version']: print(json.dumps({'protocol':1,'max_bytes':65536}))\nelse:\n data=json.load(sys.stdin)\n print(json.dumps({'argv':sys.argv[1:],'cmdline':open('/proc/self/cmdline','rb').read().decode().split(chr(0)),'input':data,'env':list(os.environ.values())}))\n")
   binary.chmod(0o700)
   backend=core.Backend(store_dir=root/"store",state_dir=root/"state",wacli=binary,account_config=root/"none")
   secret="Synthetic Grüße 世界\nsecond line"
   args=['--json','send','text','--message',secret]
   result=backend._run(args,account=None,private_args=True)
   value=json.loads(result.stdout)
   self.assertEqual(value['argv'],['--private-args-stdin'])
   self.assertEqual(value['input'],['--timeout','30s',*args])
   self.assertNotIn(secret,str(value['cmdline']))
   self.assertNotIn(secret,str(value['env']))
 def test_old_binary_is_refused_before_content_dispatch(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);binary=root/'wacli';binary.write_text('#!/bin/sh\nexit 1\n');binary.chmod(0o700)
   backend=core.Backend(store_dir=root/'store',state_dir=root/'state',wacli=binary)
   with self.assertRaisesRegex(core.OmaWhatsAppError,'privacy-enabled'):
    backend._run(['send','text','--message','synthetic'],account=None,private_args=True)
 def test_mutation_and_lock_retries_keep_private_transport(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);backend=core.Backend(store_dir=root/'store',state_dir=root/'state')
   account=core.Account('default',root/'store',True,selector='store')
   locked=subprocess.CompletedProcess([],1,'','store is locked')
   done=subprocess.CompletedProcess([],0,'{}','')
   with mock.patch.object(backend,'online',return_value=True),mock.patch.object(backend,'_run',side_effect=[locked,locked,done]) as run,mock.patch.object(backend,'_yield_active_sync',return_value=False):
    backend._mutate(['send','text','--message','synthetic'],timeout=3,require_online=True,account=account)
   self.assertEqual(run.call_count,3)
   self.assertTrue(all(call.kwargs.get('private_args') for call in run.call_args_list))
 def test_capability_probe_reports_without_raising(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);binary=root/'wacli';binary.write_text('#!/bin/sh\nexit 1\n');binary.chmod(0o700)
   backend=core.Backend(store_dir=root/'store',state_dir=root/'state',wacli=binary)
   self.assertFalse(backend._private_transport_supported())
   binary.write_text('#!/bin/sh\necho \'{"protocol":1,"max_bytes":65536}\'\n');os.utime(binary,ns=(1,10**18))
   self.assertTrue(backend._private_transport_supported(),'a replaced binary is probed again')
if __name__=='__main__':unittest.main()
