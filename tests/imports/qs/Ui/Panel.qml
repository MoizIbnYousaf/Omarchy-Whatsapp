import QtQuick

Item {
  property QtObject bar: null
  property string moduleName: ""
  property bool manageIpc: true
  property bool opened: false

  function open() { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }
}
