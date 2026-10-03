import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "MediaBrowser"
  width: 400
  height: 600
  visible: true
  when: windowShown

  Component { id: browserComponent; Oma.MediaBrowser { width: 380; height: 600 } }
  Component { id: spyComponent; SignalSpy {} }

  function test_links_are_listed_one_row_per_link() {
    var browser = createTemporaryObject(browserComponent, testCase, { kind: "links", items: [
      { id: "l1", text: "see https://example.test/a and www.example.test/b", timestamp: 1787540100, sender: "Sam" },
      { id: "l2", text: "no link here", timestamp: 1787540000 }] })
    compare(browser.linkRows.length, 2)
    compare(browser.linkRows[1].url, "https://www.example.test/b")
    verify(!findChild(browser, "mediaBrowserEmpty").visible)
  }

  function test_media_without_a_file_asks_for_a_download_and_with_one_opens_the_viewer() {
    var browser = createTemporaryObject(browserComponent, testCase, { kind: "media", items: [
      { id: "m1", media_type: "image", mime_type: "image/png", local_path: "" },
      { id: "m2", media_type: "image", mime_type: "image/png", local_path: "/nonexistent/a.png" }] })
    var download = createTemporaryObject(spyComponent, testCase, { target: browser, signalName: "downloadRequested" })
    var open = createTemporaryObject(spyComponent, testCase, { target: browser, signalName: "openMediaRequested" })
    browser.openMedia(browser.items[0])
    compare(download.count, 1)
    browser.openMedia(browser.items[1])
    compare(open.count, 1)
    compare(open.signalArguments[0][1].length, 1, "the viewer gets only the media that is on this computer")
  }

  function test_tabs_and_the_empty_state() {
    var browser = createTemporaryObject(browserComponent, testCase, { kind: "docs", items: [] })
    verify(findChild(browser, "mediaBrowserEmpty").visible)
    var tabs = createTemporaryObject(spyComponent, testCase, { target: browser, signalName: "kindRequested" })
    var media = findChild(browser, "mediaBrowserTab-media")
    tryVerify(function() { return media.width > 0 })
    mouseClick(media, media.width / 2, media.height / 2)
    compare(tabs.signalArguments[0][0], "media")
  }
}
