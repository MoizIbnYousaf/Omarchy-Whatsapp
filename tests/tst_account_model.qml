import QtQuick
import QtTest
import "../plugins/omawhatsapp/AccountModel.js" as AccountModel

TestCase {
  name: "AccountModel"

  readonly property var workChat: { return { jid: "shared@s.whatsapp.net", account: "work", account_label: "work" } }
  readonly property var homeChat: { return { jid: "shared@s.whatsapp.net", account: "home", account_label: "home" } }

  function test_the_same_jid_in_two_accounts_is_two_chats() {
    verify(AccountModel.sameChat(workChat, "work", "shared@s.whatsapp.net"))
    verify(!AccountModel.sameChat(workChat, "home", "shared@s.whatsapp.net"))
    verify(!AccountModel.sameChat(null, "work", "shared@s.whatsapp.net"))
    compare(AccountModel.chatKey("work", "shared@s.whatsapp.net"),
            "work\nshared@s.whatsapp.net")
    verify(AccountModel.chatKey("work", "shared@s.whatsapp.net")
           !== AccountModel.chatKey("home", "shared@s.whatsapp.net"))
    compare(AccountModel.chatKey("work", ""), "")
  }

  function test_the_account_is_named_only_when_there_is_more_than_one() {
    compare(AccountModel.previewPrefix(workChat, true), "work · ")
    compare(AccountModel.previewPrefix(workChat, false), "")
    compare(AccountModel.previewPrefix({ jid: "a" }, true), "")
    verify(AccountModel.isMultiAccount([{}, {}]))
    verify(!AccountModel.isMultiAccount([{}]))
    verify(!AccountModel.isMultiAccount(null))
  }

  function test_every_account_store_is_watched_once() {
    compare(AccountModel.storeDirectories([
      { store: "/state/wacli/accounts/work" },
      { store: "/state/wacli/accounts/home" },
      { store: "/state/wacli/accounts/work" }
    ], "/fallback"), ["/state/wacli/accounts/work", "/state/wacli/accounts/home"])
    compare(AccountModel.storeDirectories([], "/fallback"), ["/fallback"])
    compare(AccountModel.storeDirectories(null, ""), [])
  }

  function test_forwarding_never_leaves_the_account() {
    var targets = AccountModel.forwardTargets(
      [workChat, homeChat, { jid: "team@g.us", account: "work" }], workChat)
    compare(targets.length, 1)
    compare(targets[0].jid, "team@g.us")
  }
}
