import QtQml
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "MediaViewer"

  Component {
    id: viewerComponent
    Oma.MediaViewerModel {}
  }

  Component {
    id: mediaBubbleComponent
    Oma.MediaBubble {
      width: 400
      message: ({
        id: "album-first",
        media_type: "album",
        mime_type: "image/svg+xml",
        local_path: "__demo__",
        album_count: 2,
        album_items: [
          { id: "album-first", media_type: "image", mime_type: "image/svg+xml",
            local_path: "__demo__", album_index: 0 },
          { id: "album-second", media_type: "image", mime_type: "image/svg+xml",
            local_path: "__demo_photo__", album_index: 1 }
        ]
      })
      foreground: "#eeeeee"
      background: "#111111"
      accent: "#66ccaa"
      dim: "#aaaaaa"
      dimmer: "#777777"
      fontFamily: "monospace"
    }
  }

  function media(id) {
    return {
      id: id,
      sender: "Demo",
      timestamp: 1,
      text: "Synthetic image",
      media_type: "image",
      mime_type: "image/svg+xml",
      local_path: "__demo__"
    }
  }

  function test_open_navigation_zoom_and_close() {
    var viewer = createTemporaryObject(viewerComponent, testCase)
    verify(viewer !== null)
    viewer.items = [media("one"), media("two"), media("three")]
    viewer.openAt(1)
    compare(viewer.opened, true)
    compare(viewer.currentIndex, 1)
    compare(viewer.currentItem.id, "two")

    viewer.navigate(1)
    compare(viewer.currentItem.id, "three")
    viewer.navigate(1)
    compare(viewer.currentItem.id, "one")
    viewer.navigate(-1)
    compare(viewer.currentItem.id, "three")

    viewer.setZoom(10)
    compare(viewer.zoom, 4)
    viewer.setZoom(0.1)
    compare(viewer.zoom, 0.5)
    viewer.closeViewer()
    compare(viewer.opened, false)
    compare(viewer.currentIndex, -1)
    compare(viewer.zoom, 1)
  }

  function test_open_is_bounded() {
    var viewer = createTemporaryObject(viewerComponent, testCase)
    verify(viewer !== null)
    viewer.items = [media("one"), media("two")]
    viewer.openAt(99)
    compare(viewer.currentIndex, 1)
    viewer.openAt(-10)
    compare(viewer.currentIndex, 0)
  }

  function test_album_accepts_qt_variant_lists_offscreen() {
    var bubble = createTemporaryObject(mediaBubbleComponent, testCase)
    verify(bubble !== null)
    tryCompare(bubble, "album", true)
    compare(bubble.albumItems.length, 2)
    verify(bubble.implicitHeight > 0)
    compare(String(bubble.localUrlFor(bubble.albumItems[1])).indexOf("demo-photo.svg") >= 0,
            true)
  }
}
