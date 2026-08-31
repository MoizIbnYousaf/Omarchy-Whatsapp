import QtQuick
import QtTest
import "../plugins/omawhatsapp/ComposerModel.js" as ComposerModel

TestCase {
  name: "ComposerModel"

  function test_demo_reply_preserves_visible_quote_context() {
    var message = ComposerModel.demoMessage("release-safe demo", true, {
      id: "quoted-1", sender: "Synthetic sender",
      text: "Synthetic quoted text", media_type: "image"
    }, 123000)
    compare(message.id, "demo-123000")
    compare(message.text, "release-safe demo")
    compare(message.timestamp, 123)
    compare(message.from_me, true)
    compare(message.media_type, "document")
    compare(message.quoted_id, "quoted-1")
    compare(message.quoted_sender, "Synthetic sender")
    compare(message.quoted_text, "Synthetic quoted text")
    compare(message.quoted_media_type, "image")
  }

  function test_only_the_initiating_surface_owns_a_write_result() {
    verify(ComposerModel.ownsOperation("app", "app"))
    verify(ComposerModel.ownsOperation("dropdown", "dropdown"))
    verify(!ComposerModel.ownsOperation("dropdown", "app"))
    verify(!ComposerModel.ownsOperation("app", "dropdown"))
    verify(!ComposerModel.ownsOperation("service", "app"))
  }

  function test_partial_send_removes_only_confirmed_successes() {
    compare(ComposerModel.remainingAttachments(
      ["/tmp/external.pdf", "file:///run/user/1000/paste.png", "/tmp/new.txt"],
      { sent_paths: ["/tmp/external.pdf", "file:///run/user/1000/paste.png"] }
    ), ["/tmp/new.txt"])
  }

  function test_plain_failure_preserves_the_draft() {
    compare(ComposerModel.remainingAttachments(["/tmp/a", "/tmp/b"], {}),
            ["/tmp/a", "/tmp/b"])
  }

  function test_partial_paths_match_file_urls_canonically() {
    compare(ComposerModel.remainingAttachments(
      ["file:///tmp/Synthetic%20video.mp4", "file:///tmp/keep.pdf"],
      { sent_paths: ["/tmp/Synthetic video.mp4"] }
    ), ["file:///tmp/keep.pdf"])
  }

  function test_edit_is_consumed_at_start_and_success_never_overwrites_new_text() {
    var submitted = {
      text: "edited message", edit: { id: "m1" },
      draftBeforeEdit: "new message draft",
      draftMentionsBeforeEdit: [{ jid: "sam@s.whatsapp.net", name: "Sam" }]
    }
    var started = ComposerModel.startedState(
      submitted, "edit", { id: "m1", text: "edited message" })
    compare(started.text, "new message draft")
    compare(started.edit, null)
    compare(started.mentions[0].jid, "sam@s.whatsapp.net")

    started.text = "typed while editing"
    var completed = ComposerModel.completedState(
      started, "edit", { id: "m1", text: "edited message" })
    compare(completed.text, "typed while editing")
    compare(completed.edit, null)
  }

  function test_send_success_does_not_erase_same_text_typed_after_start() {
    var submitted = {
      text: "same words", mentions: [{ jid: "sam@s.whatsapp.net" }],
      reply: { id: "reply-1" }
    }
    var started = ComposerModel.startedState(
      submitted, "send", { text: "same words", reply_id: "reply-1" })
    compare(started.text, "")
    compare(started.mentions, [])
    compare(started.reply, null)
    started.text = "same words"

    var completed = ComposerModel.completedState(
      started, "send", { text: "same words", reply_id: "reply-1" })
    compare(completed.text, "same words")
  }

  function test_file_success_only_reconciles_confirmed_attachments() {
    var started = ComposerModel.startedState({
      text: "old caption", attachments: ["/tmp/a", "/tmp/new"]
    }, "files", { caption: "old caption", paths: ["/tmp/a"] })
    compare(started.text, "")
    started.text = "new draft"
    var completed = ComposerModel.completedState(
      started, "files", { caption: "old caption", paths: ["/tmp/a"] })
    compare(completed.text, "new draft")
    compare(completed.attachments, ["/tmp/new"])
  }

  function test_failure_restores_only_untouched_consumed_fields() {
    var submitted = {
      text: "send me", mentions: [{ jid: "sam@s.whatsapp.net" }],
      reply: { id: "reply-1" }
    }
    var started = ComposerModel.startedState(
      submitted, "send", { text: "send me", reply_id: "reply-1" })
    var restored = ComposerModel.failedState(
      started, "send", { text: "send me", reply_id: "reply-1" }, submitted, {})
    compare(restored.text, "send me")
    compare(restored.mentions.length, 1)
    compare(restored.reply.id, "reply-1")

    started.text = "fresh words"
    started.mentions = []
    started.reply = { id: "reply-2" }
    var preserved = ComposerModel.failedState(
      started, "send", { text: "send me", reply_id: "reply-1" }, submitted, {})
    compare(preserved.text, "fresh words")
    compare(preserved.reply.id, "reply-2")
  }

  function test_failed_edit_reopens_only_when_post_start_draft_is_untouched() {
    var submitted = {
      text: "edited message", edit: { id: "m1" },
      draftBeforeEdit: "original draft",
      draftMentionsBeforeEdit: [{ jid: "sam@s.whatsapp.net" }]
    }
    var request = { id: "m1", text: "edited message" }
    var started = ComposerModel.startedState(submitted, "edit", request)
    var restored = ComposerModel.failedState(
      started, "edit", request, submitted, {})
    compare(restored.text, "edited message")
    compare(restored.edit.id, "m1")
    compare(restored.draftBeforeEdit, "original draft")

    started.text = "fresh in-flight draft"
    var preserved = ComposerModel.failedState(
      started, "edit", request, submitted, {})
    compare(preserved.text, "fresh in-flight draft")
    compare(preserved.edit, null)
  }

  function test_partial_failure_keeps_only_unsent_files_and_restores_caption() {
    var submitted = {
      text: "caption", attachments: ["/tmp/a", "/tmp/b"]
    }
    var request = { caption: "caption", paths: ["/tmp/a", "/tmp/b"] }
    var started = ComposerModel.startedState(submitted, "files", request)
    var restored = ComposerModel.failedState(started, "files", request,
      submitted, { sent_paths: ["/tmp/a"] })
    compare(restored.text, "caption")
    compare(restored.attachments, ["/tmp/b"])
  }

  function test_dropdown_close_reopen_reconciles_the_exact_text_write() {
    var work = { account: "work", jid: "shared@example", key: "ignored" }
    var home = { account: "home", jid: "shared@example" }
    var submitted = { text: "synthetic draft", reply: { id: "reply-1" } }
    var intent = ComposerModel.writeIntent(work, "send", {
      text: "synthetic draft", reply_id: "reply-1", mentions: []
    }, submitted)

    verify(ComposerModel.validWriteIntent(intent))
    verify(ComposerModel.writeIntentMatches(intent, work))
    verify(ComposerModel.writeIntentMatches(intent, work, "send"))
    verify(!ComposerModel.writeIntentMatches(intent, work, "files"))
    verify(!ComposerModel.writeIntentMatches(intent, home))
    compare(intent.chatRef.key, "work\nshared@example")

    // Closing and reopening a surface does not mutate this pending state.
    var whileClosed = ComposerModel.startedIntentState(intent)
    compare(whileClosed.text, "")
    compare(whileClosed.reply, null)
    var failedAfterReopen = ComposerModel.failedIntentState(
      whileClosed, intent, {})
    compare(failedAfterReopen.text, "synthetic draft")
    compare(failedAfterReopen.reply.id, "reply-1")

    var completedAfterReopen = ComposerModel.completedIntentState(
      ComposerModel.startedIntentState(intent), intent)
    compare(completedAfterReopen.text, "")
    compare(completedAfterReopen.reply, null)
  }

  function test_dropdown_close_reopen_reconciles_partial_file_failure() {
    var intent = ComposerModel.writeIntent({
      account: "work", jid: "chat@example"
    }, "files", {
      paths: ["file:///tmp/one.pdf", "file:///tmp/two.pdf"],
      caption: "synthetic caption", reply_id: ""
    }, {
      text: "synthetic caption",
      attachments: ["file:///tmp/one.pdf", "file:///tmp/two.pdf"]
    })
    var closed = ComposerModel.startedIntentState(intent)
    var failed = ComposerModel.failedIntentState(closed, intent, {
      sent_paths: ["/tmp/one.pdf"]
    })
    compare(failed.text, "synthetic caption")
    compare(failed.attachments, ["file:///tmp/two.pdf"])

    var completed = ComposerModel.completedIntentState(closed, intent)
    compare(completed.text, "")
    compare(completed.attachments, [])
  }

  function test_file_picker_merge_is_pure_and_bounded() {
    var current = {
      text: "draft", attachments: ["file:///tmp/existing.pdf"]
    }
    var result = ComposerModel.pickedState(current, [
      "file:///tmp/new.pdf", "file:///tmp/overflow.pdf"
    ], "document", 2)
    compare(current.attachments, ["file:///tmp/existing.pdf"])
    compare(result.state.attachments, [
      "file:///tmp/existing.pdf", "file:///tmp/new.pdf"
    ])
    compare(result.rejected, ["file:///tmp/overflow.pdf"])
    verify(result.overflow)
  }
}
