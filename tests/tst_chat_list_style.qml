import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma
import "../plugins/omawhatsapp/AccountModel.js" as AccountModel
import "../plugins/omawhatsapp/Tint.js" as Tint

// The chat list of the approved restyle: pinned and recent chats under their
// own labels, the time on every row, media named by kind, and a compact
// density that keeps each chat on one line.
TestCase {
  id: testCase
  name: "ChatListStyle"
  width: 1100
  height: 760
  visible: true
  when: windowShown

  Component { id: appComponent; Oma.App { demoMode: true; opened: true } }

  readonly property var chats: [
    { jid: "demo-pin", name: "Synthetic Pinned", kind: "dm", account: "work", account_label: "work",
      avatar_path: "", preview: "morning", timestamp: 1787539920, unread: 0, pinned: true },
    { jid: "demo-group", name: "Synthetic Team", kind: "group", account: "work", account_label: "work",
      avatar_path: "", preview: "[image]", last_media_type: "image", last_sender: "Sam Rivera",
      timestamp: 1787539000, unread: 3, notification_unread: 3, pinned: false },
    { jid: "demo-quiet", name: "Synthetic Quiet", kind: "dm", account: "work", account_label: "work",
      avatar_path: "", preview: "[audio]", last_media_type: "audio",
      timestamp: 1787538200, unread: 2, notification_unread: 0, muted: true, pinned: false }
  ]

  function openApp() {
    var app = createTemporaryObject(appComponent, testCase)
    app.demoChats = chats
    app.demoSelectedJid = "demo-pin"
    return app
  }

  function rows(app) {
    var found = []
    function walk(item) {
      if (item.objectName === "chatRow") found.push(item)
      for (var i = 0; i < item.children.length; i++) walk(item.children[i])
    }
    walk(app)
    tryVerify(function() { found = []; walk(app); return found.length === 3 }, 3000)
    found.sort(function(a, b) { return a.index - b.index })
    return found
  }

  function test_pinned_and_recent_chats_are_labelled() {
    var app = openApp()
    var list = rows(app)
    compare(findChild(list[0], "chatSection").text, "PINNED")
    compare(findChild(list[1], "chatSection").text, "RECENT")
    verify(!findChild(list[2], "chatSection").visible)
    app.chatView = "unread"
    tryVerify(function() { return app.railSectionLabel(0) === "" }, 1000, "views other than all have no labels")
    app.chatView = "all"
    verify(app.railSectionLabel(0) === "Pinned")
  }

  function test_every_row_shows_its_time_and_unread_rows_stand_out() {
    var app = openApp()
    var list = rows(app)
    for (var i = 0; i < list.length; i++) {
      var time = findChild(list[i], "chatTime")
      verify(time.visible && time.text !== "", "row " + i + " has a time")
    }
    compare(String(findChild(list[1], "chatTime").color), String(app.accent), "unread: accent time")
    verify(String(findChild(list[2], "chatTime").color) !== String(app.accent), "muted unread stays quiet")
    compare(findChild(list[1], "chatName").font.weight, Font.Bold)
    compare(findChild(list[0], "chatName").font.weight, Font.Medium)
    var loud = findChild(list[1], "chatUnreadBadge")
    var quiet = findChild(list[2], "chatUnreadBadge")
    compare(String(loud.color), String(app.accent))
    verify(String(quiet.color) !== String(app.accent), "a muted chat's count is grey")
  }

  function test_media_previews_name_their_kind_and_who_sent_them() {
    var app = openApp()
    var list = rows(app)
    compare(findChild(list[1], "chatPreview").text, "work · Sam: Photo", "account, then sender")
    compare(findChild(list[1], "chatPreviewKind").text, "󰄀")
    compare(findChild(list[2], "chatPreview").text, "work · Voice message")
    compare(findChild(list[2], "chatPreviewKind").text, "󰍬")
    verify(!findChild(list[0], "chatPreviewKind").visible, "plain text has no kind icon")
    compare(AccountModel.previewParts({ preview: "Orcamento.pdf", last_media_type: "document" }).text,
      "Orcamento.pdf", "a file name stays")
    compare(AccountModel.previewSender({ kind: "group", last_from_me: true, last_sender: "You" }), "")
  }

  function test_a_draft_reads_amber() {
    var app = openApp()
    app.composerStates = { "work\ndemo-group": { text: "see you", attachments: [] } }
    var list = rows(app)
    var preview = findChild(list[1], "chatPreview")
    tryCompare(preview, "text", "Draft: see you")
    compare(String(preview.color), String(Tint.draftColor(app.accent)))
    verify(!findChild(list[1], "chatPreviewKind").visible, "a draft hides the media icon")
  }

  function test_compact_rows_keep_one_line() {
    var app = openApp()
    var comfortable = findChild(rows(app)[1], "chatRowBody").height
    app.demoRailDensity = "compact"
    var list = rows(app)
    var body = findChild(list[0], "chatRowBody")
    verify(body.height < comfortable)
    var name = findChild(list[0], "chatName")
    var preview = findChild(list[0], "chatPreviewLine")
    compare(Math.round(name.y + name.height / 2), Math.round(preview.y + preview.height / 2),
      "name and preview share the line")
    verify(preview.x > name.x + name.width, "the preview follows the name")
    verify(findChild(list[0], "chatTime").visible, "no unread: the time sits at the end")
    verify(!findChild(list[1], "chatTime").visible, "unread: the badge takes its place")
    verify(findChild(list[1], "chatUnreadBadge").visible)
    verify(findChild(list[0], "chatAvatarBackdrop").width < 30, "a small avatar")
  }

  function test_view_filters_fill_the_rail_or_underline_in_compact() {
    var app = openApp()
    var views = findChild(app, "railViews")
    var all = findChild(app, "railView-all")
    var groups = findChild(app, "railView-groups")
    tryVerify(function() { return groups.x > all.x + all.width }, 2000, "the row has laid out")
    verify(!views.overflowing, "the four views fit a normal rail")
    var end = groups.mapToItem(views, groups.width, 0).x
    verify(Math.abs(views.width - end) <= 3 + views.inset, "the segments reach the rail's edge")
    verify(!findChild(all, "railViewUnderline").visible)
    app.demoRailDensity = "compact"
    tryVerify(function() { return findChild(all, "railViewUnderline").visible }, 1000,
      "compact: the current view is underlined")
    verify(!findChild(groups, "railViewUnderline").visible)
  }

  function test_the_search_field_shows_its_key() {
    var app = openApp()
    var hint = findChild(app, "chatSearchKeyHint")
    verify(hint !== null && hint.visible)
  }

  function test_an_unread_mention_shows_an_at_sign() {
    // L222: a chat whose unread messages @mention you says so beside its count.
    var app = openApp()
    var list = rows(app)
    verify(!findChild(list[1], "chatMentionBadge").visible, "no mention, no sign")
    var marked = chats.slice()
    marked[1] = Object.assign({}, marked[1], { mentioned: true })
    marked[0] = Object.assign({}, marked[0], { mentioned: true })
    app.demoChats = marked
    list = rows(app)
    verify(findChild(list[1], "chatMentionBadge").visible, "unread and mentioned")
    verify(!findChild(list[0], "chatMentionBadge").visible, "read chats show no sign")
  }

  // L236: with several accounts, each chat carries its account's color on the
  // row's edge (not on the photo, where a dot reads as "online").
  function test_each_account_marks_its_chats_with_its_color() {
    var app = openApp()
    app.demoChats = chats.concat([{ jid: "demo-home", name: "Synthetic Home", kind: "dm",
      account: "personal", account_label: "personal", avatar_path: "", preview: "hi",
      timestamp: 1787530000, unread: 0, pinned: false }])
    var found = []
    function walk(item) {
      if (item.objectName === "chatRow") found.push(item)
      for (var i = 0; i < item.children.length; i++) walk(item.children[i])
    }
    tryVerify(function() { found = []; walk(app); return found.length === 4 }, 3000)
    var byName = {}
    for (var i = 0; i < found.length; i++)
      byName[findChild(found[i], "chatName").text] = findChild(found[i], "chatAccountStripe")
    verify(byName["Synthetic Pinned"].visible)
    verify(byName["Synthetic Home"].visible)
    verify(Qt.colorEqual(byName["Synthetic Pinned"].color, Tint.accountColor(0, app.accent)))
    verify(Qt.colorEqual(byName["Synthetic Home"].color, Tint.accountColor(1, app.accent)))
    verify(!Qt.colorEqual(byName["Synthetic Pinned"].color, byName["Synthetic Home"].color))
    var dots = []
    function walkDots(item) {
      if (item.objectName === "accountChipDot" && item.visible) dots.push(item)
      for (var j = 0; j < item.children.length; j++) walkDots(item.children[j])
    }
    tryVerify(function() { dots = []; walkDots(app); return dots.length === 2 }, 2000,
      "the account chips are the legend; All has no color")
    var subtitle = findChild(app, "conversationSubtitle")
    compare(subtitle.text, "work", "the open chat names its account")
    verify(Qt.colorEqual(subtitle.color, Tint.accountColor(0, app.accent)), "in the account's color")
  }

  function test_account_order_sets_the_color() {
    compare(AccountModel.accountIndex([{ account: "work" }, { account: "home" }], "home"), 1)
    compare(AccountModel.accountIndex([{ account: "work" }], "home"), -1)
    var accent = Qt.hsla(0.4, 0.6, 0.6, 1)
    verify(Qt.colorEqual(Tint.accountColor(0, accent), accent), "the first account is the accent")
    verify(!Qt.colorEqual(Tint.accountColor(1, accent), Tint.accountColor(2, accent)))
  }
}
