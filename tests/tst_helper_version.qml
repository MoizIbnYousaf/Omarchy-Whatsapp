import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// omarchy plugin update replaces the files, but the shell keeps the QML it
// loaded: the helper and the app disagree until the shell restarts, and the
// app says so instead of showing a raw error.
TestCase {
  id: testCase
  name: "HelperVersion"

  Component { id: serviceComponent; Oma.Service { manifest: ({ id: "io.github.moizibnyousaf.omawhatsapp", version: "0.15.0" }) } }

  function status(service, payload, stderrText) {
    var process = findChild(service, "statusProcess")
    process.stdout.text = payload === null ? "" : JSON.stringify(payload)
    process.stderr.text = stderrText || ""
    process.running = false
    process.exited(payload === null ? 2 : 0)
  }
  function ok(version) {
    var payload = { ok: true, installed: true, authenticated: true, database_ready: true,
      sync_active: true, any_authenticated: true, account: "", accounts: [] }
    if (version !== undefined) payload.helper_version = version
    return payload
  }

  function test_a_matching_helper_says_nothing() {
    var service = createTemporaryObject(serviceComponent, testCase)
    status(service, ok("0.15.0"))
    verify(!service.helperOutdated)
    verify(service.barTooltip.indexOf("restart the shell") < 0)
  }

  function test_without_a_manifest_nothing_is_compared() {
    var service = createTemporaryObject(serviceComponent, testCase, { manifest: null })
    status(service, ok())
    verify(!service.helperOutdated)
  }

  function test_a_different_helper_asks_to_restart_the_shell() {
    var service = createTemporaryObject(serviceComponent, testCase)
    status(service, ok())
    verify(service.helperOutdated, "a helper without a version predates this app")
    verify(service.helperOutdatedText.indexOf("Restart the Omarchy shell") >= 0)
    verify(service.barTooltip.indexOf("restart the shell") >= 0)
    status(service, ok("0.14.0"))
    verify(service.helperOutdated)
    verify(service.helperOutdatedText.indexOf("0.14.0") >= 0)
  }

  function test_a_refused_command_reads_as_an_old_helper() {
    var service = createTemporaryObject(serviceComponent, testCase)
    status(service, null, "omawhatsapp: error: argument command: invalid choice: 'unlink-account'")
    verify(service.helperOutdated)
    compare(service.errorText, service.helperOutdatedText, "no raw argparse error on screen")
  }
}
