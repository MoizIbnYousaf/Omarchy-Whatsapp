import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "ChatAvatar"

  Component {
    id: avatarComponent
    Oma.ChatAvatar {
      width: 38
      height: 38
      chat: ({ name: "Synthetic Person", kind: "dm", avatar_path: "" })
      foreground: "#eeeeee"
      background: "#111111"
      accent: "#66ccaa"
      fontFamily: "monospace"
    }
  }

  Component { id: appComponent; Oma.App { demoMode: true; opened: true } }

  function test_conversation_header_follows_the_selected_chat_photo() {
    var app = createTemporaryObject(appComponent, testCase)
    verify(app !== null)
    var photo = { jid: "synthetic-photo", name: "Synthetic Person", kind: "dm",
      account: "personal", account_label: "personal", avatar_path: "__demo_avatar__",
      preview: "", timestamp: 2, unread: 0, pinned: false }
    var initials = { jid: "synthetic-initials", name: "Synthetic Friend", kind: "dm",
      account: "personal", account_label: "personal", avatar_path: "",
      preview: "", timestamp: 1, unread: 0, pinned: false }
    var group = { jid: "synthetic-group", name: "Synthetic Group", kind: "group",
      account: "work", account_label: "work", avatar_path: "",
      preview: "", timestamp: 0, unread: 0, pinned: false }
    app.demoChats = [photo, initials, group]
    var header = findChild(app, "conversationAvatar")
    verify(header !== null)

    app.selectChat(photo)
    tryVerify(function() { return header.avatarReady }, 5000)
    compare(findChild(header, "chatAvatarFallback").visible, false)

    app.selectChat(initials)
    compare(header.avatarReady, false)
    compare(findChild(header, "chatAvatarFallback").text, "SF")

    app.selectChat(group)
    compare(findChild(header, "chatAvatarFallback").text, "SG")

    app.demoChats = []
    compare(app.selectedChat, null)
    compare(findChild(header, "chatAvatarFallback").text, "󰠮")
  }

  function test_private_local_avatar_replaces_the_fallback() {
    var avatar = createTemporaryObject(avatarComponent, testCase, {
      chat: { name: "Synthetic Person", kind: "dm",
        avatar_path: "__demo_avatar__" }
    })
    verify(avatar !== null)
    tryVerify(function() { return avatar.avatarReady }, 5000)
    compare(findChild(avatar, "chatAvatarFallback").visible, false)
    compare(findChild(avatar, "chatAvatarImage").source,
      Qt.resolvedUrl("../plugins/omawhatsapp/assets/demo-photo.png"))
  }

  function test_remote_urls_never_cross_the_qml_boundary() {
    var avatar = createTemporaryObject(avatarComponent, testCase, {
      chat: { name: "Synthetic Person", kind: "dm",
        avatar_path: "https://example.invalid/private-token" }
    })
    verify(avatar !== null)
    compare(avatar.localAvatar, false)
    compare(String(findChild(avatar, "chatAvatarImage").source), "")
    compare(findChild(avatar, "chatAvatarFallback").text, "SP")
  }

  function test_groups_keep_a_clear_fallback_when_no_photo_exists() {
    var avatar = createTemporaryObject(avatarComponent, testCase, {
      width: 38, height: 38,
      chat: { jid: "synthetic-group", name: "Synthetic Group", kind: "group", avatar_path: "" }
    })
    verify(avatar !== null)
    compare(avatar.avatarReady, false)
    // Initials on a rounded square: the shape says group, the letters which.
    compare(findChild(avatar, "chatAvatarFallback").text, "SG")
    verify(avatar.shapeRadius < avatar.width / 2)
    var unnamed = createTemporaryObject(avatarComponent, testCase, {
      chat: { name: "", kind: "group", avatar_path: "" }
    })
    compare(findChild(unnamed, "chatAvatarFallback").text, "󰠮")
  }

  function test_people_are_round_and_each_chat_keeps_its_own_color() {
    var first = createTemporaryObject(avatarComponent, testCase, {
      width: 38, height: 38,
      chat: { jid: "synthetic-a", name: "Synthetic A", kind: "dm", avatar_path: "" }
    })
    var again = createTemporaryObject(avatarComponent, testCase, {
      width: 38, height: 38,
      chat: { jid: "synthetic-a", name: "Synthetic A", kind: "dm", avatar_path: "" }
    })
    var other = createTemporaryObject(avatarComponent, testCase, {
      width: 38, height: 38,
      chat: { jid: "synthetic-b", name: "Synthetic B", kind: "dm", avatar_path: "" }
    })
    compare(first.shapeRadius, 19)
    compare(String(first.tint), String(again.tint))
    verify(String(first.tint) !== String(other.tint))
    compare(String(findChild(first, "chatAvatarBackdrop").color), String(first.tint))
  }
}
