import QtQuick

Item {
  id: root
  property QtObject bar: null
  property string moduleName: ""
  property bool manageIpc: true
  property bool opened: false

  property QtObject controller: QtObject {
    function show() { root.opened = true }
    function hide() { root.opened = false }
  }

  function open() { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }
}
