import QtQml
import "MediaViewerLogic.js" as Logic

// Pure state model kept separate from rendering so navigation and bounds can
// be verified by Qt's offscreen test runner without loading a shell process.
QtObject {
  id: root

  property var items: []
  property int currentIndex: -1
  property real zoom: 1
  property bool opened: false
  readonly property var currentItem: currentIndex >= 0 && currentIndex < items.length
    ? items[currentIndex] : null

  function openAt(index) {
    if (!Array.isArray(items) || items.length === 0) return false
    currentIndex = Logic.boundedIndex(items, index)
    zoom = 1
    opened = true
    return true
  }

  function closeViewer() {
    opened = false
    currentIndex = -1
    zoom = 1
  }

  function navigate(delta) {
    if (!items || items.length < 2) return
    currentIndex = Logic.nextIndex(items, currentIndex, delta)
    zoom = 1
  }

  function setZoom(value) {
    zoom = Logic.boundedZoom(value)
  }
}
