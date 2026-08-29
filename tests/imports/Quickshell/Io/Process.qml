import QtQuick

QtObject {
  property var command: []
  property bool running: false
  property bool stdinEnabled: false
  property var stdout: null
  property var stderr: null

  signal started()
  signal exited(int exitCode)

  function write(value) {}
}
