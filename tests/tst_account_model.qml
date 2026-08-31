import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma
import "../plugins/omawhatsapp/AccountModel.js" as AccountModel

TestCase {
  id: testCase
  name: "AccountModel"

  readonly property var workChat: { return { jid: "shared@s.whatsapp.net", account: "work", account_label: "work" } }
  readonly property var homeChat: { return { jid: "shared@s.whatsapp.net", account: "home", account_label: "home" } }

  Component {
    id: readinessComponent
    Oma.AccountReadiness {
      accounts: []
      foreground: "#eeeeee"
      accent: "#66ccaa"
      fontFamily: "monospace"
    }
  }

  function test_the_same_jid_in_two_accounts_is_two_chats() {
    verify(AccountModel.sameChat(workChat, "work", "shared@s.whatsapp.net"))
    verify(!AccountModel.sameChat(workChat, "home", "shared@s.whatsapp.net"))
    verify(!AccountModel.sameChat(null, "work", "shared@s.whatsapp.net"))
    compare(AccountModel.chatKey("work", "shared@s.whatsapp.net"),
            "work\nshared@s.whatsapp.net")
    verify(AccountModel.chatKey("work", "shared@s.whatsapp.net")
           !== AccountModel.chatKey("home", "shared@s.whatsapp.net"))
    compare(AccountModel.chatKey("work", ""), "")
    compare(AccountModel.refOf(workChat), {
      account: "work", jid: "shared@s.whatsapp.net",
      key: "work\nshared@s.whatsapp.net"
    })
    verify(AccountModel.sameRef(AccountModel.refOf(workChat),
                                AccountModel.chatRef("work", "shared@s.whatsapp.net")))
    verify(!AccountModel.sameRef(AccountModel.refOf(workChat),
                                 AccountModel.refOf(homeChat)))
    compare(AccountModel.findChat([homeChat, workChat], AccountModel.refOf(workChat)),
            workChat)
  }

  function test_stale_responses_never_cross_account_boundaries() {
    var work = AccountModel.refOf(workChat)
    var home = AccountModel.refOf(homeChat)
    verify(AccountModel.responseMatches({ jid: "shared@s.whatsapp.net" }, work, work))
    verify(!AccountModel.responseMatches({ jid: "shared@s.whatsapp.net" }, work, home))
    verify(!AccountModel.responseMatches({ jid: "another@s.whatsapp.net" }, work, work))
  }

  function test_the_account_is_named_only_when_there_is_more_than_one() {
    compare(AccountModel.previewPrefix(workChat, true), "work · ")
    compare(AccountModel.previewPrefix(workChat, false), "")
    compare(AccountModel.previewPrefix({ jid: "a" }, true), "")
    verify(AccountModel.isMultiAccount([{}, {}]))
    verify(!AccountModel.isMultiAccount([{}]))
    verify(!AccountModel.isMultiAccount(null))
  }

  function test_rail_readiness_never_authorizes_an_unready_selected_account() {
    var readiness = AccountModel.statusReadiness({
      authenticated: false,
      database_ready: false,
      any_authenticated: true,
      any_database_ready: true,
      rail_ready: true
    })
    compare(readiness.railReady, true)
    compare(readiness.authenticated, false)
    compare(readiness.accountReady, false)
  }

  function test_unready_summary_exposes_labels_only_and_keeps_ready_accounts() {
    var accounts = [
      { account: "work", label: "Work", authenticated: true,
        database_ready: true, store: "/private/work" },
      { account: "home", label: "Home", authenticated: false,
        database_ready: false, store: "/private/home",
        error: "private diagnostic" }
    ]
    compare(AccountModel.unreadyAccountLabels(accounts), ["Home"])
    compare(AccountModel.unreadyAccountSummary(accounts), "Home unavailable")
    verify(AccountModel.unreadyAccountSummary(accounts).indexOf("private") < 0)
    compare(AccountModel.unreadyAccountSummary([accounts[0]]), "")

    var row = createTemporaryObject(readinessComponent, testCase)
    verify(row !== null)
    row.accounts = accounts
    wait(0)
    compare(row.summary, "Home unavailable")
    compare(row.hasUnavailableAccounts, true)
    verify(row.height > 0)
  }

  function test_every_account_store_is_watched_once() {
    compare(AccountModel.storeDirectories([
      { store: "/state/wacli/accounts/work" },
      { store: "/state/wacli/accounts/home" },
      { store: "/state/wacli/accounts/work" }
    ], "/fallback"), ["/state/wacli/accounts/work", "/state/wacli/accounts/home"])
    compare(AccountModel.storeDirectories([], "/fallback"), ["/fallback"])
    compare(AccountModel.storeDirectories(null, ""), [])
    compare(AccountModel.storeDirectories([
      { store: "relative-private-store" }, { store: "/safe/store" }
    ], "relative-fallback"), ["/safe/store"])
    compare(AccountModel.storeDirectories([], "relative-fallback"), [])
    compare(AccountModel.defaultStoreDirectory(
      "relative-store", "relative-state", "/home/synthetic"),
      "/home/synthetic/.local/state/wacli")
    compare(AccountModel.defaultStoreDirectory(
      "/explicit/store", "/state", "/home/synthetic"), "/explicit/store")
  }

  function test_forwarding_never_leaves_the_account() {
    var targets = AccountModel.forwardTargets(
      [workChat, homeChat, { jid: "team@g.us", account: "work" }], workChat)
    compare(targets.length, 1)
    compare(targets[0].jid, "team@g.us")
  }

  function test_forward_picker_remains_bound_to_its_origin_ref() {
    var chats = [
      workChat,
      homeChat,
      { jid: "work-target@g.us", account: "work" },
      { jid: "home-target@g.us", account: "home" }
    ]
    var origin = AccountModel.refOf(workChat)
    var targets = AccountModel.forwardTargetsForRef(chats, origin)
    compare(targets.length, 1)
    compare(targets[0].account, "work")
    compare(targets[0].jid, "work-target@g.us")

    // A later selection of the same JID in another account cannot retarget
    // the already-open picker because its immutable origin is still `work`.
    verify(!AccountModel.sameRef(origin, AccountModel.refOf(homeChat)))
    compare(AccountModel.forwardTargetsForRef(chats, origin), targets)
    compare(AccountModel.forwardTargetsForRef(chats, {
      account: "missing", jid: "shared@s.whatsapp.net"
    }), [])
  }
}
