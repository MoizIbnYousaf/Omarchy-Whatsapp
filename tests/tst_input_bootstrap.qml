import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma
TestCase {
  id: suite
  name: "InputBootstrap"
  Component { id: component; Oma.Service {} }
  function test_failed_build_keeps_all_editors_unloaded() {
    var service=createTemporaryObject(component,suite)
    verify(service!==null)
    compare(service.inputsReady,false)
    var process=findChild(service,"inputBuildProcess")
    verify(process!==null)
    process.stdout.text=JSON.stringify({ok:false,error:"Compiler is unavailable"})
    process.running=false
    process.exited(1)
    compare(service.inputsReady,false)
    compare(service.inputError,"Compiler is unavailable")
    compare(service.openApp('{"demo":true}'),false)
  }
}
