import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma
import "../plugins/omawhatsapp/TimeFormat.js" as TimeFormat
import "../plugins/omawhatsapp/LinkModel.js" as LinkModel

TestCase {
  id: testCase
  name: "TimelineMarkers"
  width: 900
  height: 420
  visible: true
  when: windowShown

  Component { id: appComponent; Oma.App { width: 900; height: 420; demoMode: true } }
  Component { id: dropdownComponent; Oma.Dropdown { demoMode: true } }
  Component {
    id: bubbleComponent
    Oma.MessageBubble {
      width: 600
      message: ({ id: "m", text: "see https://example.org/page, and www.omarchy.org.",
        sender: "Demo", timestamp: 1787540100, from_me: false, media_type: "", reactions: [] })
      foreground: "#eeeeee"; background: "#111111"; accent: "#66ccaa"
      dim: "#999999"; dimmer: "#777777"; fontFamily: "monospace"
    }
  }

  function test_day_labels() {
    var now = new Date(2026, 8, 24, 15, 0, 0)
    var at = function(y, m, d, h) { return new Date(y, m, d, h, 0, 0).getTime() / 1000 }
    compare(TimeFormat.dayLabel(at(2026, 8, 24, 9), now), "Today")
    compare(TimeFormat.dayLabel(at(2026, 8, 23, 23), now), "Yesterday")
    compare(TimeFormat.dayLabel(at(2026, 8, 21, 12), now), "Monday")
    compare(TimeFormat.dayLabel(at(2026, 7, 2, 12), now), "2 Aug")
    compare(TimeFormat.dayLabel(at(2025, 11, 31, 12), now), "31 Dec 2025")
  }

  function test_a_day_starts_at_its_oldest_message() {
    var day1 = new Date(2026, 8, 23, 10).getTime() / 1000
    var day2 = new Date(2026, 8, 24, 10).getTime() / 1000
    var newestFirst = [{ timestamp: day2 + 60 }, { timestamp: day2 }, { timestamp: day1 + 30 }, { timestamp: day1 }]
    compare([0, 1, 2, 3].map(function(i) { return TimeFormat.startsDay(newestFirst, i) }),
      [false, true, false, true])
  }

  function test_links_are_extracted_safely() {
    var links = LinkModel.extract("see https://example.org/page, and www.omarchy.org. ftp://x", 3)
    compare(links.map(function(link) { return link.url }),
      ["https://example.org/page", "https://www.omarchy.org"])
    compare(LinkModel.extract("no links here").length, 0)
  }

  function test_bubble_shows_link_chips_and_offers_copy_link() {
    var bubble = createTemporaryObject(bubbleComponent, testCase)
    compare(bubble.links.length, 2)
    verify(findChild(bubble, "messageLinks").visible)
    verify(bubble.menuActions.some(function(item) { return item.action === "copy-link" }))
    verify(bubble.fullTimestampText.length > bubble.timestampText.length,
      "the timestamp tooltip carries the full date")
  }

  function test_opening_an_unread_chat_marks_where_unread_starts() {
    var app = createTemporaryObject(appComponent, testCase)
    app.opened = true
    app.selectChat(app.demoChats[1])
    compare(app.demoChats[1].unread, 3)
    // The demo timeline has one received message, newest, above four of
    // yours: the divider goes above that one, never above your own.
    compare(app.unreadDividerIndex, 0)
    verify(app.visibleMessages[0].from_me !== true)
    app.selectChat(app.demoChats[0])
    compare(app.unreadDividerIndex, -1, "a read chat has no divider")
  }

  function test_replies_sent_after_opening_stay_below_the_unread_divider() {
    // The owner's report: after replying in a chat opened with one unread
    // message, the divider moved onto the reply ("1 unread message" above a
    // message they sent).
    var app = createTemporaryObject(appComponent, testCase)
    app.opened = true
    app.selectChat(app.demoChats[1])
    var anchor = app.visibleMessages[app.unreadDividerIndex]
    verify(anchor.from_me !== true, "the divider sits above a received message")
    var composer = findChild(app, "composerInput")
    composer.text = "first reply"
    app.sendDraft()
    composer.text = "second reply"
    app.sendDraft()
    compare(app.visibleMessages[0].text, "second reply")
    compare(app.visibleMessages[app.unreadDividerIndex].id, anchor.id,
      "the divider stays above the same received message")
    verify(app.unreadDividerIndex >= 2, "both replies are below it")
  }

  // Enough older demo messages that the timeline always scrolls, whatever
  // fonts the machine has (CI has none, which shrinks the text).
  function longTimeline(app) {
    var oldest = app.demoItems[app.demoItems.length - 1]
    var extra = []
    for (var i = 0; i < 8; i++)
      extra.push({ id: "extra-" + i, text: "Older synthetic message " + i, sender: "Sam Rivera",
        sender_jid: "sam@s.whatsapp.net", timestamp: Number(oldest.timestamp) - (i + 1) * 3600,
        from_me: i % 2 === 0, done: false, media_type: "", mime_type: "", local_path: "", tags: [] })
    app.demoItems = app.demoItems.concat(extra)
  }

  function test_jump_to_latest_appears_when_reading_above() {
    var app = createTemporaryObject(appComponent, testCase)
    app.opened = true
    var list = findChild(app, "messageList")
    var jump = findChild(app, "jumpToLatest")
    verify(list !== null && jump !== null)
    longTimeline(app)
    tryVerify(function() { return list.count > 5 })
    app.scrollToNewest()
    tryVerify(function() { return !jump.visible }, 2000, "at the newest message there is nothing to jump to")
    verify(list.contentHeight > list.height + 60, "the demo timeline must scroll here")
    // Straight to the top of the content: positionViewAtEnd settles later on
    // slower machines (CI), where lazily created delegates move the end.
    tryVerify(function() {
      list.contentY = list.originY
      return jump.visible
    }, 3000, "reading older messages offers the way back")
    var backing = findChild(app, "jumpToLatestBacking")
    verify(backing.visible && backing.color.a === 1, "the text never shows through the button")
    jump.clicked()
    tryVerify(function() { return !jump.visible }, 2000, "the button lands on the newest message, not beside it")
  }

  function test_the_conversation_has_a_scroll_bar_and_page_keys() {
    var app = createTemporaryObject(appComponent, testCase)
    app.opened = true
    // Grouped runs made the demo timeline short enough to fit; paging needs more.
    longTimeline(app)
    var list = findChild(app, "messageList")
    tryVerify(function() { return list.count > 0 })
    verify(findChild(app, "messageScrollBar") !== null, "a draggable scroll bar, not only the wheel")
    list.positionViewAtBeginning()
    wait(50)
    var newest = list.contentY
    verify(app.pageConversation(Qt.Key_PageUp))
    verify(list.contentY < newest, "Page Up moves toward older messages")
    verify(app.pageConversation(Qt.Key_End))
    tryVerify(function() { return !findChild(app, "jumpToLatest").visible }, 2000,
      "End goes back to the newest message")
    verify(app.pageConversation(Qt.Key_Home))
    verify(!app.pageConversation(Qt.Key_A))
  }

  function test_the_day_floats_at_the_top_while_scrolling_and_then_fades() {
    var app = createTemporaryObject(appComponent, testCase)
    app.opened = true
    var list = findChild(app, "messageList")
    tryVerify(function() { return list.count > 0 })
    longTimeline(app)
    tryVerify(function() { return list.count > 5 })
    var pill = findChild(app, "floatingDay")
    verify(pill !== null)
    tryVerify(function() {
      list.contentY = list.originY
      return findChild(app, "jumpToLatest").parent.awayFromLatest
    }, 3000)
    app.showFloatingDay()
    verify(app.floatingDayLabel !== "", "the topmost message's day")
    tryVerify(function() { return pill.shown })
    tryVerify(function() { return !pill.shown }, 3000, "it fades on its own after scrolling stops")
    app.scrollToNewest()
    tryVerify(function() { return !findChild(app, "jumpToLatest").visible }, 2000)
    app.showFloatingDay()
    verify(!pill.shown, "at the newest message the day header below is enough")
  }

  function test_dropdown_marks_unread_and_days_too() {
    var dropdown = createTemporaryObject(dropdownComponent, testCase)
    var unread = dropdown.demoChats.filter(function(chat) { return Number(chat.unread || 0) > 1 })[0]
    dropdown.openConversation(unread)
    verify(dropdown.unreadDividerIndex >= 0)
    var anchor = dropdown.sourceMessages[dropdown.unreadDividerIndex]
    verify(anchor.from_me !== true, "the divider sits above a received message")
    var incomingAfter = dropdown.sourceMessages.slice(0, dropdown.unreadDividerIndex + 1)
      .filter(function(item) { return item.from_me !== true })
    compare(incomingAfter.length, Math.min(unread.unread, dropdown.sourceMessages.filter(
      function(item) { return item.from_me !== true }).length), "N received messages from the divider down")
    verify(findChild(dropdown, "jumpToLatest") !== null)
    verify(findChild(dropdown, "dayHeader") !== null)
  }
}
