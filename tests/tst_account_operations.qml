import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "AccountOperations"

  Component {
    id: operationsComponent
    Oma.AccountOperations {
      helper: "/synthetic/omawhatsapp"
      accounts: []
    }
  }

  function test_terminal_options_are_single_arguments_and_target_the_helper() {
    var operations = createTemporaryObject(operationsComponent, testCase)
    verify(operations !== null)
    compare(operations.linkCommand("work"), [
      "/usr/bin/xdg-terminal-exec", "--title=OmaWhatsApp · Link work",
      "--hold", "--", "/synthetic/omawhatsapp", "link-account", "work",
      "--authorize", "interactive"
    ])
  }

  function test_authenticated_discovery_wins_over_a_late_terminal_exit() {
    var operations = createTemporaryObject(operationsComponent, testCase)
    operations.linkPhase = "running"
    operations.linkTarget = "work"
    operations.accounts = [{ account: "work", authenticated: true,
                              database_ready: true }]
    operations.reconcileLink()
    compare(operations.statusMessage, "work linked")
    verify(operations.linkBusy)
    operations.recordLinkExit(1)
    compare(operations.statusMessage, "work linked")
    verify(!operations.linkBusy)
  }

  function test_link_commit_does_not_wait_for_database_and_holds_process_slot() {
    var operations = createTemporaryObject(operationsComponent, testCase)
    operations.linkPhase = "running"
    operations.linkTarget = "work"
    operations.accounts = [{ account: "work", authenticated: true,
                              database_ready: false }]
    operations.reconcileLink()
    compare(operations.statusMessage, "work linked")
    verify(operations.linkBusy)
    verify(!operations.linkAccount("another"))
    operations.recordLinkExit(0)
    verify(!operations.linkBusy)
  }

  function test_exited_link_waits_for_canonical_probe_without_a_timer_race() {
    var operations = createTemporaryObject(operationsComponent, testCase)
    operations.linkPhase = "running"
    operations.linkTarget = "work"
    operations.linkPolls = 140
    verify(operations.recordLinkExit(1))
    verify(operations.linkBusy)
    verify(operations.statusMessage.indexOf("Checking whether work") === 0)
    for (var index = 0; index < 10; index++) operations.handleLinkPoll()
    verify(operations.linkBusy)
    operations.accounts = [{ account: "work", authenticated: true,
                              database_ready: false }]
    operations.reconcileLink()
    compare(operations.statusMessage, "work linked")
    verify(!operations.linkBusy)
  }

  function test_post_exit_session_probe_is_the_failure_boundary() {
    var operations = createTemporaryObject(operationsComponent, testCase)
    operations.linkPhase = "probing"
    operations.linkTarget = "work"
    operations.handleLinkProbeExit(1)
    compare(operations.statusMessage,
      "Linking was not finished; use the same name to resume")
    verify(!operations.linkBusy)
  }

  function test_timeout_never_reuses_a_held_terminal_process() {
    var operations = createTemporaryObject(operationsComponent, testCase)
    operations.linkPhase = "running"
    operations.linkTarget = "work"
    operations.linkPolls = 149
    operations.handleLinkPoll()
    verify(operations.linkBusy)
    verify(operations.busy)
    compare(operations.linkTarget, "work")
    compare(operations.statusMessage, "Linking is still open in the terminal")
    verify(!operations.linkAccount("another"))
  }

  function test_avatar_outcomes_report_partial_and_total_failure() {
    var operations = createTemporaryObject(operationsComponent, testCase)
    operations.avatarBusy = true
    operations.finishAvatarRefresh(0, JSON.stringify({
      ok: true, checked: 3, refreshed: 1, failed: 2, cached: 1
    }), "")
    compare(operations.statusMessage,
      "1 refreshed; 2 chat photos could not be refreshed")
    verify(!operations.avatarBusy)

    operations.avatarBusy = true
    operations.finishAvatarRefresh(0, JSON.stringify({
      ok: true, checked: 3, refreshed: 0, failed: 3, cached: 0
    }), "")
    compare(operations.statusMessage, "Chat photos could not be refreshed")
    verify(!operations.avatarBusy)
  }
}
