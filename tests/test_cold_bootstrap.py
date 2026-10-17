"""The resident service must parse before the native media/input module exists."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
class ColdBootstrap(unittest.TestCase):
    def test_service_loads_without_pre_registered_native_imports(self):
        with tempfile.TemporaryDirectory() as directory:
            test=Path(directory)/'tst_cold.qml'
            test.write_text('''import QtQuick
import QtTest
import "'''+(ROOT/'plugins/omawhatsapp').as_uri()+'''" as Oma
TestCase {
 name: "ColdBootstrap"
 Component {id: service; Oma.Service {}}
 function test_bootstrap(){
   var item=createTemporaryObject(service,this)
   verify(item!==null)
   compare(item.inputsReady,false)
 }
}
''')
            env=os.environ.copy()
            env.update(QT_QPA_PLATFORM='offscreen',WAYLAND_DISPLAY='/nonexistent/omaw-test',QML_IMPORT_PATH=directory,QML2_IMPORT_PATH=directory)
            result=subprocess.run(['/usr/lib/qt6/bin/qmltestrunner','-input',str(test),'-import',str(ROOT/'tests/imports'),'-o','-,txt'],env=env,capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stdout+'\n'+result.stderr)
