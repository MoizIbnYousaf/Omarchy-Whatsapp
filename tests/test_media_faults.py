"""Inject broken worker responses into a disposable module, never the live app."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

class MediaFaults(unittest.TestCase):
    def test_parent_survives_untrusted_responses_timeouts_and_budget_pressure(self):
        imports=Path(subprocess.check_output([str(ROOT/'scripts/build-inputs')],text=True).strip())
        with tempfile.TemporaryDirectory() as directory:
            temp=Path(directory)
            module=temp/'OmaWhatsApp/Inputs';module.mkdir(parents=True)
            for name in ('libomainputs.so','qmldir'):
                shutil.copyfile(imports/'OmaWhatsApp/Inputs'/name,module/name)
            worker=module/'omawa-media-worker'
            worker.write_text('''#!/usr/bin/python3
import json,os,sys,time
request=json.load(sys.stdin);name=request['path']
if 'hang' in name: time.sleep(60)
if 'crash' in name: sys.exit(1)
if 'overflow' in name:
 while True: os.write(1,b'x'*65536)
w=2049 if 'malformed' in name else 1024 if 'large' in name else 1
header={'w':w,'h':w,'sw':w,'sh':w,'count':1,'index':0,'delay':100}
sys.stdout.buffer.write(json.dumps(header).encode()+b'\\n'+b'\\0'*(w*w*4))
''');worker.chmod(0o755)
            qml=temp/'tst_faults.qml'
            qml.write_text('''import QtQuick
import QtTest
import OmaWhatsApp.Inputs as Native
TestCase {
 id: root; name: "WorkerFaults"; when: windowShown; visible:true;width:100;height:100
 Component { id: image; Native.AnimatedImage {width:50;height:50} }
 function test_bad_response_data(){return [{tag:"overflow"},{tag:"crash"},{tag:"malformed"},{tag:"hang"}]}
 function test_bad_response(data){
   var a=createTemporaryObject(image,root,{source:"file:///synthetic/"+data.tag})
   tryCompare(a,"status",Image.Error,10000)
   a.source="file:///synthetic/valid";tryCompare(a,"status",Image.Ready)
 }
 function test_cancel_running_request(){
   var a=createTemporaryObject(image,root,{source:"file:///synthetic/hang"})
   wait(100);a.source="file:///synthetic/valid";tryCompare(a,"status",Image.Ready,2000)
 }
 function test_queue_deadline(){
   var all=[]
   for(var i=0;i<6;i++)all.push(createTemporaryObject(image,root,{source:"file:///synthetic/hang"+i}))
   tryVerify(function(){return all.every(function(a){return a.status===Image.Error})},16000)
 }
 function test_aggregate_retained_budget(){
   var all=[]
   for(var i=0;i<12;i++)all.push(createTemporaryObject(image,root,{source:"file:///synthetic/large"+i}))
   tryVerify(function(){return all.every(function(a){return a.status===Image.Ready||a.status===Image.Error})},10000)
   var ready=all.filter(function(a){return a.status===Image.Ready}).length
   verify(ready>0 && ready<=8)
 }
}
''')
            env=os.environ.copy();env.update(QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QML_IMPORT_PATH=str(temp),WAYLAND_DISPLAY='/nonexistent/omaw-test')
            result=subprocess.run(['/usr/lib/qt6/bin/qmltestrunner','-input',str(qml),'-o','-,txt'],env=env,text=True,capture_output=True,timeout=60)
            self.assertEqual(result.returncode,0,result.stdout+'\n'+result.stderr)
