import QtQuick

QtObject {
  property string path: ""
  property string content: ""
  property bool printErrors: true
  property bool watchChanges: false
  signal loaded()
  signal loadFailed(var error)
  signal fileChanged()
  function text() { return content }
  function reload() { loaded() }
}
