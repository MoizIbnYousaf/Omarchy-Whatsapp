import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma
import "../plugins/omawhatsapp/TimeFormat.js" as TimeFormat

TestCase {
  id: testCase
  name: "TimeFormat"

  Component { id: appComponent; Oma.App { demoMode: true; opened: true } }
  Component { id: dropdownComponent; Oma.Dropdown { demoMode: true } }
  Component {
    id: bubbleComponent
    Oma.MessageBubble {
      width: 420
      foreground: "#eeeeee"
      background: "#111111"
      accent: "#66ccaa"
      dim: "#999999"
      dimmer: "#777777"
      fontFamily: "monospace"
      message: ({ text: "Synthetic timestamp", timestamp: 1, media_type: "", from_me: true })
    }
  }
  Component {
    id: viewerComponent
    Oma.MediaViewer {
      width: 800
      height: 600
      foreground: "#eeeeee"
      background: "#111111"
      accent: "#66ccaa"
      dim: "#999999"
      fontFamily: "monospace"
    }
  }

  function test_system_uses_the_locale_and_explicit_choices_override_it_data() {
    return [{ tag: "US", locale: "en_US" }, { tag: "UK", locale: "en_GB" },
      { tag: "Germany", locale: "de_DE" }]
  }
  function test_system_uses_the_locale_and_explicit_choices_override_it(data) {
    var localePattern = Qt.locale(data.locale).timeFormat(Locale.ShortFormat)
    compare(TimeFormat.clockPattern("auto", localePattern), localePattern)
    compare(TimeFormat.clockPattern("12h", localePattern), "h:mm AP")
    compare(TimeFormat.clockPattern("24h", localePattern), "HH:mm")
    compare(TimeFormat.clockPattern("invalid", localePattern), localePattern)
  }

  function test_midnight_noon_and_afternoon_change_in_messages_and_media_data() {
    return [{ tag: "midnight", hour: 0, clock24: "00:05" },
      { tag: "noon", hour: 12, clock24: "12:05" },
      { tag: "afternoon", hour: 13, clock24: "13:05" }]
  }
  function test_midnight_noon_and_afternoon_change_in_messages_and_media(data) {
    var date = new Date(2026, 0, 15, data.hour, 5, 0)
    var message = { text: "Synthetic timestamp", timestamp: date.getTime() / 1000,
      media_type: "", from_me: true }
    var bubble = createTemporaryObject(bubbleComponent, testCase, { message: message })
    var viewer = createTemporaryObject(viewerComponent, testCase,
      { items: [message], currentIndex: 0 })
    verify(bubble !== null && viewer !== null)
    bubble.timeFormat = "24h"
    viewer.timeFormat = "24h"
    compare(bubble.timestampText, data.clock24)
    verify(viewer.timestampText.endsWith(" · " + data.clock24))
    var clock12 = Qt.formatTime(date, "h:mm AP")
    bubble.timeFormat = "12h"
    viewer.timeFormat = "12h"
    compare(bubble.timestampText, clock12)
    verify(viewer.timestampText.endsWith(" · " + clock12))
    bubble.timeFormat = "auto"
    compare(bubble.timestampText,
      Qt.formatTime(date, Qt.locale().timeFormat(Locale.ShortFormat)))
  }

  function test_app_and_dropdown_previews_and_bubbles_share_the_preference() {
    var app = createTemporaryObject(appComponent, testCase)
    var dropdown = createTemporaryObject(dropdownComponent, testCase)
    verify(app !== null && dropdown !== null)
    dropdown.openConversation(dropdown.demoChats[0])
    var today = new Date()
    var date = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 13, 5, 0)
    var seconds = date.getTime() / 1000
    app.demoTimeFormat = "24h"
    dropdown.demoTimeFormat = "24h"
    verify(app.formatTime(seconds).endsWith(" 13:05"))
    compare(dropdown.timeLabel(seconds), "13:05")
    wait(0)
    var appBubble = findChild(app, "messageBubbleSurface")
    var dropdownBubble = findChild(dropdown, "messageBubbleSurface")
    verify(appBubble !== null && dropdownBubble !== null)
    compare(appBubble.parent.timeFormat, "24h")
    compare(dropdownBubble.parent.timeFormat, "24h")
    var viewer = findChild(app, "mediaViewer")
    verify(viewer !== null)
    compare(viewer.timeFormat, "24h")
    app.demoTimeFormat = "12h"
    dropdown.demoTimeFormat = "12h"
    var clock12 = Qt.formatTime(date, "h:mm AP")
    verify(app.formatTime(seconds).endsWith(" " + clock12))
    compare(dropdown.timeLabel(seconds), clock12)
    compare(appBubble.parent.timeFormat, "12h")
    compare(dropdownBubble.parent.timeFormat, "12h")
    compare(viewer.timeFormat, "12h")

    var yesterday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1, 13, 5, 0)
    compare(dropdown.timeLabel(yesterday.getTime() / 1000), "Yesterday")
    compare(dropdown.timeLabel(0), "")
  }

  function test_the_list_stamp_shortens_with_age() {
    var now = new Date(2026, 8, 25, 15, 0, 0)
    var at = function(year, month, day, hour, minute) {
      return new Date(year, month, day, hour, minute, 0).getTime() / 1000
    }
    compare(TimeFormat.listStamp(at(2026, 8, 25, 9, 21), now, "HH:mm", "dd/MM/yyyy"), "09:21")
    compare(TimeFormat.listStamp(at(2026, 8, 24, 22, 0), now, "HH:mm", "dd/MM/yyyy"), "Yesterday")
    // 23 September 2026 is a Wednesday.
    compare(TimeFormat.listStamp(at(2026, 8, 23, 8, 0), now, "HH:mm", "dd/MM/yyyy"), "Wed")
    compare(TimeFormat.listStamp(at(2026, 8, 12, 8, 0), now, "HH:mm", "dd/MM/yyyy"), "12/09")
    compare(TimeFormat.listStamp(at(2026, 8, 12, 8, 0), now, "HH:mm", "M/d/yy"), "09/12")
    compare(TimeFormat.listStamp(at(2025, 11, 30, 8, 0), now, "HH:mm", "dd/MM/yyyy"), "30/12/25")
    compare(TimeFormat.listStamp(0, now, "HH:mm", "dd/MM/yyyy"), "")
  }
}
