"""The MCP server that lets an agent such as Claude Code use OmaWhatsApp.

Unit tests replace the helper with a recorder, so every tool's request is
checked without wacli. The end-to-end class runs the real server and the real
helper over a synthetic mirror and a fake wacli that records its arguments,
which proves each authorization token is exactly the one the helper demands.
"""

from __future__ import annotations

from contextlib import closing
import importlib.util
from importlib.machinery import SourceFileLoader
import io
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from test_backend import SCHEMA

SCRIPT = Path(os.environ["OMAW_SCRIPT"])
SERVER = SCRIPT.with_name("omawhatsapp-mcp")
SPEC = importlib.util.spec_from_loader(
    "omawhatsapp_mcp", SourceFileLoader("omawhatsapp_mcp", str(SERVER)))
assert SPEC and SPEC.loader
mcp = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mcp)

WRITE_TOOLS = {
    "send_message", "send_files", "start_chat", "react", "forward_message", "edit_message",
    "delete_message", "send_poll", "set_chat_state", "create_group", "manage_group",
    "remove_or_leave_group", "fetch_older_history", "tag_contacts", "set_contact_alias",
    "send_individually", "vote_poll", "send_location", "update_profile", "post_status",
    "join_channel", "leave_channel", "export_chat", "join_group", "delete_status",
}
DESTRUCTIVE_TOOLS = {"delete_message", "remove_or_leave_group", "leave_channel", "delete_status"}


def chat(jid: str, name: str, kind: str = "dm", **fields: object) -> dict[str, object]:
    row: dict[str, object] = {"jid": jid, "account": "", "name": name, "kind": kind,
                              "unread": 0, "timestamp": 1790000000, "last_from_me": False}
    row.update(fields)
    return row


def message(identifier: str, timestamp: int, from_me: bool = False, text: str = "",
            **fields: object) -> dict[str, object]:
    row: dict[str, object] = {"id": identifier, "timestamp": timestamp, "from_me": from_me,
                              "text": text, "sender": "" if from_me else "Sam",
                              "sender_jid": "" if from_me else "sam@s.whatsapp.net"}
    row.update(fields)
    return row


class Recorder:
    """Stands in for the helper: records requests and answers per command."""

    def __init__(self, **answers: object) -> None:
        self.calls: list[tuple[str, dict | None, tuple[str, ...]]] = []
        self.answers = answers

    def __call__(self, command: str, payload: dict | None = None, *args: str,
                 timeout: float = 60) -> dict:
        self.calls.append((command, payload, args))
        key = command
        if command == "wacli":
            words = [item for item in payload["args"] if not item.startswith("-")]
            key = "wacli " + " ".join(words[:2])
        answer = self.answers.get(key, self.answers.get(command, {}))
        if callable(answer):
            answer = answer(payload, args)
        if isinstance(answer, Exception):
            raise answer
        return dict(answer, ok=True)

    def of(self, command: str) -> list[dict]:
        return [payload for name, payload, _ in self.calls if name == command]

    def wacli(self) -> list[list[str]]:
        return [payload["args"] for name, payload, _ in self.calls if name == "wacli"]

    def token(self) -> str:
        return [payload for name, payload, _ in self.calls if name == "wacli"][-1]["authorization"]


class ToolCase(unittest.TestCase):
    def use(self, **answers: object) -> Recorder:
        recorder = Recorder(**answers)
        patcher = mock.patch.object(mcp, "helper", recorder)
        patcher.start()
        self.addCleanup(patcher.stop)
        sleeper = mock.patch.object(mcp.time, "sleep")
        sleeper.start()
        self.addCleanup(sleeper.stop)
        return recorder

    def run_tool(self, tool_name: str, /, **arguments: object) -> dict:
        result = mcp.call_tool(tool_name, arguments)
        self.assertFalse(result["isError"], result["content"][0]["text"])
        return json.loads(result["content"][0]["text"])

    def tool_error(self, tool_name: str, /, **arguments: object) -> str:
        result = mcp.call_tool(tool_name, arguments)
        self.assertTrue(result["isError"], result["content"][0]["text"])
        return result["content"][0]["text"]


class ProtocolTests(ToolCase):
    def test_initialize_negotiates_the_version_and_names_the_server(self) -> None:
        reply = mcp.respond({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                             "params": {"protocolVersion": "2025-03-26"}})
        self.assertEqual(reply["result"]["protocolVersion"], "2025-03-26")
        self.assertEqual(reply["result"]["serverInfo"]["name"], "omawhatsapp")
        self.assertIn("tools", reply["result"]["capabilities"])
        self.assertIn("Never guess", reply["result"]["instructions"])
        newer = mcp.respond({"jsonrpc": "2.0", "id": 2, "method": "initialize",
                             "params": {"protocolVersion": "2099-01-01"}})
        self.assertEqual(newer["result"]["protocolVersion"], mcp.PROTOCOL_VERSIONS[0])

    def test_notifications_get_no_reply_and_unknown_methods_an_error(self) -> None:
        self.assertIsNone(mcp.respond({"jsonrpc": "2.0", "method": "notifications/initialized"}))
        self.assertEqual(mcp.respond({"jsonrpc": "2.0", "id": 3, "method": "ping"})["result"], {})
        missing = mcp.respond({"jsonrpc": "2.0", "id": 4, "method": "resources/list"})
        self.assertEqual(missing["error"]["code"], -32601)

    def test_the_stdio_loop_answers_lines_batches_and_bad_json(self) -> None:
        requests = "\n".join([
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": "ping"}),
            "",
            "not json",
            json.dumps([{"jsonrpc": "2.0", "id": 2, "method": "ping"},
                        {"jsonrpc": "2.0", "method": "notifications/initialized"}]),
        ]) + "\n"
        output = io.StringIO()
        self.assertEqual(mcp.serve(io.StringIO(requests), output), 0)
        replies = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(replies[0]["id"], 1)
        self.assertEqual(replies[1]["error"]["code"], -32700)
        self.assertEqual(replies[2], [{"jsonrpc": "2.0", "id": 2, "result": {}}])

    def test_every_tool_declares_a_schema_and_honest_annotations(self) -> None:
        tools = {tool["name"]: tool for tool in mcp.listed_tools()}
        self.assertEqual(len(tools), 46)
        for name, tool in tools.items():
            self.assertRegex(name, r"^[a-z][a-z_]+$")
            self.assertTrue(tool["description"] and tool["title"], name)
            schema = tool["inputSchema"]
            self.assertEqual(schema["type"], "object")
            self.assertFalse(schema["additionalProperties"])
            self.assertLessEqual(set(schema["required"]), set(schema["properties"]), name)
            self.assertIn("account", schema["properties"])
            self.assertNotIn("handler", tool)
            hints = tool["annotations"]
            self.assertEqual(not hints["readOnlyHint"], name in WRITE_TOOLS,
                             f"{name}: a tool that changes WhatsApp must say so")
            self.assertEqual(hints["destructiveHint"], name in DESTRUCTIVE_TOOLS, name)
        json.dumps(mcp.listed_tools())

    def test_arguments_are_checked_before_anything_runs(self) -> None:
        recorder = self.use()
        self.assertIn("Unknown argument", self.tool_error("list_chats", colour="red"))
        self.assertIn("text is required", self.tool_error("send_message", jid="a@s.whatsapp.net"))
        self.assertIn("whole number", self.tool_error("list_chats", limit="10"))
        self.assertIn("one of", self.tool_error("list_chats", view="favourites"))
        self.assertIn("list of strings", self.tool_error("set_chat_state", jids=[1], action="pin"))
        self.assertIn("exact jid", self.tool_error("send_message", jid="Sam", text="hi"))
        self.assertIn("Unknown tool", self.tool_error("format_disk"))
        self.assertEqual(recorder.calls, [], "nothing reaches the helper")

    def test_a_tool_bug_is_an_error_result_not_a_crash(self) -> None:
        self.use(chats=lambda payload, args: {"chats": [{"broken": True}]})
        with mock.patch.dict(mcp.TOOLS["list_chats"], handler=lambda **_: {}["missing"]):
            self.assertIn("KeyError", self.tool_error("list_chats"))

    def test_a_helper_failure_reports_its_message_and_partial_work(self) -> None:
        self.use(send=mcp.ToolError("Offline mode is on.", {"committed": False}))
        text = self.tool_error("send_message", jid="a@s.whatsapp.net", text="hi")
        self.assertIn("Offline mode is on.", text)
        self.assertIn("committed", text)

    def test_times_are_local_and_dates_parse_in_local_time(self) -> None:
        self.assertEqual(mcp.local_time(0), "")
        self.assertEqual(mcp.local_time(1790000000), mcp.local_time(1790000000000))
        self.assertTrue(mcp.local_time("2026-09-23T18:37:41Z").startswith("2026-09-23"))
        self.assertEqual(mcp.epoch("2026-09-24", "after"),
                         int(mcp.datetime(2026, 9, 24).timestamp()))
        with self.assertRaises(mcp.ToolError):
            mcp.epoch("next tuesday", "after")


class ReadToolTests(ToolCase):
    CHATS = [
        chat("sam@s.whatsapp.net", "Sam Rivera", unread=2, timestamp=1790000300),
        chat("team@g.us", "Design team", "group", unread=5, muted=True, timestamp=1790000200),
        chat("old@s.whatsapp.net", "Old friend", archived=True, unread=1, timestamp=1790000100),
        chat("5516999990000@s.whatsapp.net", "Sam Rivera Work", last_from_me=True,
             timestamp=1790000050),
    ]

    def chats(self, **answers: object) -> Recorder:
        return self.use(chats={"chats": self.CHATS}, **answers)

    def test_list_chats_filters_views_names_and_numbers(self) -> None:
        self.chats()
        names = lambda **arguments: [row["name"] for row in self.run_tool(
            "list_chats", **arguments)["chats"]]
        self.assertEqual(names(), ["Sam Rivera", "Design team", "Sam Rivera Work"],
                         "archived chats stay out of the default view")
        self.assertEqual(names(view="unread"), ["Sam Rivera", "Design team"])
        self.assertEqual(names(view="groups"), ["Design team"])
        self.assertEqual(names(view="archived"), ["Old friend"])
        self.assertEqual(names(query="rivera"), ["Sam Rivera", "Sam Rivera Work"])
        self.assertEqual(names(query="+55 16 99999-0000"), ["Sam Rivera Work"])
        first = self.run_tool("list_chats", limit=1)
        self.assertEqual(first["more"], 2)
        self.assertNotIn("avatar_path", json.dumps(first))

    def test_a_name_matching_several_chats_asks_instead_of_guessing(self) -> None:
        recorder = self.chats()
        text = self.tool_error("read_chat", chat="Sam")
        self.assertIn("Several chats match", text)
        self.assertIn("sam@s.whatsapp.net", text)
        self.assertEqual(recorder.of("messages"), [])
        self.assertIn("No chat matches", self.tool_error("read_chat", chat="Nobody"))

    def test_an_exact_name_wins_over_partial_matches(self) -> None:
        recorder = self.chats(messages={"messages": [], "has_more": False})
        self.run_tool("read_chat", chat="sam rivera")
        self.assertEqual(recorder.of("messages")[0]["jid"], "sam@s.whatsapp.net")

    def test_unread_messages_flags_the_unread_ones_with_context(self) -> None:
        page = [message("m4", 40, text="are you there?"), message("m3", 30, text="hi"),
                message("m2", 20, from_me=True, text="bye"), message("m1", 10, text="earlier")]
        recorder = self.chats(messages={"messages": page, "has_more": True})
        answer = self.run_tool("unread_messages", context=2)
        self.assertEqual(len(answer["chats"]), 1, "the muted group and the archived chat wait")
        self.assertEqual(answer["left_out"], {"muted": 1, "archived": 1})
        messages = answer["chats"][0]["messages"]
        self.assertEqual([item["id"] for item in messages], ["m1", "m2", "m3", "m4"],
                         "oldest first")
        self.assertEqual([item["id"] for item in messages if item.get("unread")], ["m3", "m4"])
        self.assertEqual(recorder.calls[-1][2], ("--limit", "5"))
        everything = self.run_tool("unread_messages", include_muted=True, include_archived=True)
        self.assertEqual(len(everything["chats"]), 3)

    def test_awaiting_reply_lists_people_whose_message_is_the_last(self) -> None:
        now = 1790100000
        rows = [chat("a@s.whatsapp.net", "Waiting", timestamp=now - 7200),
                chat("b@s.whatsapp.net", "Just now", timestamp=now - 60),
                chat("c@s.whatsapp.net", "Answered", last_from_me=True, timestamp=now - 7200),
                chat("d@g.us", "Group", "group", timestamp=now - 7200),
                chat("e@s.whatsapp.net", "Ancient", timestamp=now - 40 * 86400),
                chat("f@s.whatsapp.net", "Archived", archived=True, timestamp=now - 7200)]
        self.use(chats={"chats": rows})
        with mock.patch.object(mcp.time, "time", return_value=now):
            names = [row["name"] for row in self.run_tool("awaiting_reply", min_hours=1)["chats"]]
            self.assertEqual(names, ["Waiting"])
            with_groups = self.run_tool("awaiting_reply", min_hours=1, include_groups=True)
        self.assertEqual([row["name"] for row in with_groups["chats"]], ["Waiting", "Group"])
        self.assertEqual(with_groups["chats"][0]["waiting_hours"], 2.0)

    def test_read_chat_pages_back_to_a_date_and_hands_a_cursor(self) -> None:
        pages = {
            None: [message("m9", 90), message("m8", 80), message("m7", 70)],
            "m7": [message("m6", 60), message("m5", 50), message("m4", 40)],
        }

        def answer(payload: dict, args: tuple) -> dict:
            before = payload.get("before")
            key = before["id"] if before else None
            return {"messages": pages.get(key, [message("m3", 30)]), "has_more": True}

        recorder = self.chats(messages=answer)
        result = self.run_tool("read_chat", chat="sam@s.whatsapp.net", limit=4)
        self.assertEqual([item["id"] for item in result["messages"]], ["m6", "m7", "m8", "m9"])
        self.assertEqual(result["next_before"], "cursor:60:m6")
        self.assertTrue(result["older_messages"])
        again = self.run_tool("read_chat", chat="sam@s.whatsapp.net", limit=2,
                              before=result["next_before"])
        self.assertIn({"ts": 60, "id": "m6"},
                      [payload.get("before") for payload in recorder.of("messages")])
        self.assertTrue(again["messages"])
        with mock.patch.object(mcp, "epoch", return_value=55):
            dated = self.run_tool("read_chat", chat="sam@s.whatsapp.net", limit=100,
                                  after="2026-01-01")
        self.assertEqual([item["id"] for item in dated["messages"]], ["m6", "m7", "m8", "m9"])
        self.assertFalse(dated["older_messages"])

    def test_read_chat_shows_polls_with_votes_and_deleted_messages(self) -> None:
        page = [message("p1", 30, from_me=True, poll={
                    "question": "Which day?", "selectable": 1, "voters": 2,
                    "options": [{"text": "Mon", "votes": 2, "voters": ["You", "Sam"], "mine": True},
                                {"text": "Tue", "votes": 0, "voters": [], "mine": False}]}),
                message("gone", 20, from_me=True, revoked=True)]
        self.chats(messages={"messages": page, "has_more": False})
        rows = {row["id"]: row for row in self.run_tool("read_chat", chat="sam@s.whatsapp.net")["messages"]}
        self.assertEqual(rows["p1"]["poll"]["options"][0],
                         {"text": "Mon", "votes": 2, "voters": ["You", "Sam"], "mine": True})
        self.assertEqual(rows["p1"]["poll"]["choices_allowed"], 1)
        self.assertTrue(rows["gone"]["deleted_for_everyone"])

    def test_read_chat_says_whether_a_sent_message_was_read(self) -> None:
        page = [message("r1", 30, from_me=True, status="read"),
                message("u1", 20, from_me=True),
                message("in", 10, status="read")]
        self.chats(messages={"messages": page, "has_more": False})
        rows = {row["id"]: row for row in self.run_tool("read_chat", chat="sam@s.whatsapp.net")["messages"]}
        self.assertEqual(rows["r1"]["delivery"], "read")
        self.assertNotIn("delivery", rows["u1"], "no record, nothing claimed")
        self.assertNotIn("delivery", rows["in"], "only sent messages have a delivery state")

    def test_read_chat_gives_shared_contacts_with_their_numbers(self) -> None:
        page = [message("c1", 30, text="Contact: Ana (+55 16 99999-0000)", contacts=[
            {"name": "Ana", "phone": "+55 16 99999-0000", "digits": "5516999990000",
             "jid": "5516999990000@s.whatsapp.net", "has_chat": True}])]
        self.chats(messages={"messages": page, "has_more": False})
        row = self.run_tool("read_chat", chat="sam@s.whatsapp.net")["messages"][0]
        self.assertEqual(row["shared_contacts"], [{"name": "Ana", "phone": "+55 16 99999-0000",
                                                   "jid": "5516999990000@s.whatsapp.net",
                                                   "has_chat": True}])

    def test_global_search_goes_to_wacli_with_every_filter(self) -> None:
        rows = [{"ChatJID": "sam@s.whatsapp.net", "ChatName": "Sam", "MsgID": "x1",
                 "Timestamp": "2026-09-20T12:00:00Z", "FromMe": False, "Text": "watch Dune",
                 "Snippet": "watch [Dune]"},
                {"ChatJID": "sam@s.whatsapp.net", "MsgID": "x2", "FromMe": True,
                 "Timestamp": "2026-09-20T12:01:00Z", "Text": "ok"}]
        recorder = self.use(**{"wacli messages search": {"data": {"fts": True, "messages": rows}}})
        answer = self.run_tool("search_messages", query="filme", sender="sam@s.whatsapp.net",
                               after="2026-09-01", type="text", forwarded=True, from_me=False)
        arguments = recorder.wacli()[0]
        self.assertEqual(arguments[:3], ["messages", "search", "filme"])
        for flag in ("--from", "--after", "--type", "--forwarded"):
            self.assertIn(flag, arguments)
        self.assertEqual(recorder.token(), "", "a search is a local read")
        self.assertEqual([item["id"] for item in answer["results"]], ["x1"])
        self.assertEqual(answer["results"][0]["match"], "watch [Dune]")

    def test_search_inside_a_chat_reads_through_the_helper(self) -> None:
        page = [message("m2", 20, text="that movie"), message("m1", 10, from_me=True,
                                                            text="which movie")]
        recorder = self.chats(messages={"messages": page, "has_more": False})
        answer = self.run_tool("search_messages", query="movie", chat="sam@s.whatsapp.net",
                               from_me=False)
        self.assertEqual(recorder.of("messages")[0]["query"], "movie")
        self.assertEqual([item["id"] for item in answer["results"]], ["m2"])
        self.assertEqual(answer["results"][0]["chat_jid"], "sam@s.whatsapp.net")
        self.assertEqual(recorder.wacli(), [], "the helper also reads the @lid rows")

    def test_message_context_marks_the_message_asked_for(self) -> None:
        rows = [{"MsgID": "a", "ChatJID": "c@g.us"}, {"MsgID": "b", "ChatJID": "c@g.us"}]
        recorder = self.use(**{"wacli messages context": {"data": {"messages": rows}}})
        answer = self.run_tool("message_context", chat_jid="c@g.us", id="b", before=1, after=0)
        self.assertEqual([item.get("match") for item in answer["messages"]], [None, True])
        self.assertEqual(recorder.wacli()[0],
                         ["messages", "context", "--chat", "c@g.us", "--id", "b",
                          "--before", "1", "--after", "0"])

    def test_attachments_pass_dates_as_epochs_and_chats_as_jids(self) -> None:
        recorder = self.chats(attachments={"attachments": [{
            "chat_jid": "sam@s.whatsapp.net", "id": "d1", "timestamp": 1790000000,
            "media_type": "document", "filename": "quote.pdf", "local_path": "",
            "available": False, "from_me": False, "sender": "Sam"}]})
        answer = self.run_tool("list_attachments", chat="Sam Rivera", kinds=["document"],
                               direction="received", after="2026-09-01", missing_only=True)
        payload = recorder.of("attachments")[0]
        self.assertEqual(payload["jid"], "sam@s.whatsapp.net")
        self.assertEqual(payload["after"], mcp.epoch("2026-09-01", "after"))
        self.assertEqual(payload["kinds"], ["document"])
        self.assertTrue(payload["missing_only"])
        self.assertTrue(answer["attachments"][0]["expired"])

    def test_open_attachment_returns_the_local_file(self) -> None:
        with tempfile.NamedTemporaryFile() as handle:
            handle.write(b"%PDF")
            handle.flush()
            recorder = self.use(media={"local_path": handle.name})
            answer = self.run_tool("open_attachment", chat_jid="sam@s.whatsapp.net", id="d1")
        self.assertEqual(answer, {"local_path": handle.name, "size_bytes": 4})
        self.assertEqual(recorder.of("media")[0]["id"], "d1")

    def test_contacts_and_tags_come_from_the_helper(self) -> None:
        recorder = self.use(**{"contacts-search": {"people": [
            {"jid": "sam@s.whatsapp.net", "name": "Sam", "tags": ["suppliers"], "alias": ""}]},
            "contact-tags": {"tags": [{"tag": "suppliers", "people": 1}]}})
        people = self.run_tool("find_contacts", tag="suppliers")["people"]
        self.assertEqual(people, [{"jid": "sam@s.whatsapp.net", "name": "Sam",
                                   "tags": ["suppliers"]}])
        self.assertEqual(recorder.of("contacts-search")[0]["tag"], "suppliers")
        self.assertEqual(self.run_tool("list_contact_tags")["tags"][0]["tag"], "suppliers")

    def test_chat_info_is_local_unless_live_settings_are_asked(self) -> None:
        # The helper's answer: its own kind, and the chat's kind under chat.
        details = {"kind": "chat-details", "chat": {"kind": "group", "name": "Design team"},
                   "since": 1790000000, "avatar_path": "/private/a.jpg",
                   "participants": [{"jid": "sam@s.whatsapp.net", "avatar_path": "/p.jpg"}]}
        recorder = self.chats(**{"chat-details": details,
                                 "group-info": {"announce": False, "locked": True}})
        local = self.run_tool("chat_info", chat="team@g.us")
        self.assertNotIn("avatar_path", json.dumps(local))
        self.assertNotIn("kind", local)
        self.assertEqual(local["chat"]["kind"], "group")
        self.assertEqual(recorder.of("group-info"), [])
        live = self.run_tool("chat_info", chat="team@g.us", live=True)
        self.assertEqual(recorder.of("group-info")[0]["authorization"], "remote-read")
        self.assertTrue(live["live_settings"]["locked"])

    def test_status_counts_unread_chats(self) -> None:
        self.use(status={"authenticated": True, "database_ready": True, "rail_ready": True,
                         "sync_active": True, "accounts": [{"name": "work"}]},
                 chats={"chats": self.CHATS})
        status = self.run_tool("whatsapp_status")
        self.assertEqual(status["unread_chats"], 3)
        self.assertTrue(status["syncing"])

    def test_missed_calls_keep_unanswered_incoming_ones(self) -> None:
        calls = [{"direction": "inbound", "outcome": "missed", "chat_name": "Sam",
                  "timestamp": "2026-09-23T18:37:41Z", "call_type": "regular"},
                 {"direction": "outbound", "outcome": "missed", "chat_name": "Ana"},
                 {"direction": "inbound", "outcome": "connected", "chat_name": "Bo"}]
        recorder = self.use(**{"wacli calls list": {"data": {"calls": calls}}})
        answer = self.run_tool("list_calls", missed_only=True)
        self.assertEqual([item["name"] for item in answer["calls"]], ["Sam"])
        self.assertEqual(answer["calls"][0]["direction"], "incoming")
        self.assertIn("200", recorder.wacli()[0], "a filtered request scans the whole window")


class WriteToolTests(ToolCase):
    def test_send_message_passes_the_reply_and_mentions(self) -> None:
        recorder = self.use(send={"message_id": "SENT"})
        answer = self.run_tool("send_message", jid="team@g.us", text=" hi ", reply_to="m1",
                               mentions=["sam@s.whatsapp.net"])
        self.assertEqual(answer, {"done": True, "message_id": "SENT"})
        self.assertEqual(recorder.of("send")[0], {"account": "", "jid": "team@g.us",
                                                  "text": "hi", "reply_id": "m1",
                                                  "mentions": ["sam@s.whatsapp.net"]})
        self.assertIn("too long", self.tool_error("send_message", jid="team@g.us",
                                                  text="x" * 5000))

    def test_send_files_refuses_missing_files(self) -> None:
        recorder = self.use(files={"count": 1})
        self.assertIn("do not exist", self.tool_error("send_files", jid="a@s.whatsapp.net",
                                                      paths=["/nonexistent/file.pdf"]))
        with tempfile.NamedTemporaryFile(suffix=".pdf") as handle:
            answer = self.run_tool("send_files", jid="a@s.whatsapp.net", paths=[handle.name],
                                   caption="quote")
        self.assertEqual(answer["sent"], 1)
        self.assertEqual(recorder.of("files")[0]["paths"], [handle.name])

    def test_start_chat_checks_the_number_before_sending(self) -> None:
        recorder = self.use(**{"check-number": {"registered": False}})
        self.assertIn("no WhatsApp account", self.tool_error(
            "start_chat", phone="+55 16 99999-0000", text="hello"))
        self.assertEqual(recorder.of("send-new"), [])
        self.assertEqual(recorder.of("check-number")[0], {
            "account": "", "phone": "5516999990000", "authorization": "remote-read"})
        recorder = self.use(**{"check-number": {"registered": True},
                               "send-new": {"chat_jid": "5516999990000@s.whatsapp.net"}})
        answer = self.run_tool("start_chat", phone="+55 16 99999-0000", text="hello")
        self.assertEqual(answer["chat_jid"], "5516999990000@s.whatsapp.net")
        self.assertEqual(recorder.of("send-new")[0]["target"], {"phone": "5516999990000"})

    def test_message_actions_map_to_the_helper(self) -> None:
        recorder = self.use(poll={"message_id": "P1"})
        self.run_tool("react", jid="a@s.whatsapp.net", id="m1", emoji="👍")
        self.run_tool("forward_message", jid="a@s.whatsapp.net", id="m1", to_jid="b@g.us")
        self.run_tool("edit_message", jid="a@s.whatsapp.net", id="m1", text="fixed")
        self.run_tool("delete_message", jid="a@s.whatsapp.net", id="m1", for_everyone=True)
        self.run_tool("send_poll", jid="b@g.us", question="Day?", options=["Mon", "Tue", " "],
                      multiple=True)
        self.assertEqual(recorder.of("react")[0]["emoji"], "👍")
        self.assertEqual(recorder.of("forward")[0]["to_jid"], "b@g.us")
        self.assertEqual(recorder.of("edit")[0]["text"], "fixed")
        self.assertFalse(recorder.of("delete")[0]["for_me"], "for everyone is not for me")
        self.assertEqual(recorder.of("poll")[0]["options"], ["Mon", "Tue"])
        self.assertEqual(recorder.of("poll")[0]["multi"], 2)
        self.assertIn("2 to 12", self.tool_error("send_poll", jid="b@g.us", question="Q",
                                                 options=["only"]))

    def test_chat_states_stop_at_the_first_failure(self) -> None:
        def answer(payload: dict, args: tuple) -> dict:
            if payload["jid"] == "b@g.us":
                return mcp.ToolError("That chat is not available.")
            return {}
        recorder = self.use(**{"chat-action": answer})
        text = self.tool_error("set_chat_state", jids=["a@g.us", "b@g.us", "c@g.us"],
                               action="archive")
        self.assertIn("Stopped at b@g.us", text)
        self.assertIn("Already changed: a@g.us", text)
        self.assertEqual([payload["jid"] for payload in recorder.of("chat-action")],
                         ["a@g.us", "b@g.us"])

    def test_create_group_uses_the_write_token_and_sets_the_description(self) -> None:
        recorder = self.use(**{"wacli groups create": {"data": {"JID": "new@g.us"}},
                               "chats": {"chats": [chat("new@g.us", "Obra", "group")]}})
        answer = self.run_tool("create_group", name="  Obra  Sorriso ",
                               participants=["sam@s.whatsapp.net", "+55 (16) 99999-0000"],
                               description="Schedule", locked=True)
        arguments = recorder.wacli()[0]
        self.assertEqual(arguments[:4], ["groups", "create", "--name", "Obra Sorriso"])
        self.assertEqual([arguments[i + 1] for i, item in enumerate(arguments) if item == "--user"],
                         ["sam@s.whatsapp.net", "+5516999990000"])
        self.assertIn("--locked", arguments)
        self.assertNotIn("--announce-only", arguments)
        self.assertEqual(recorder.token(), "whatsapp-write")
        self.assertEqual(recorder.of("group-action")[0]["value"], "Schedule")
        self.assertEqual(answer["jid"], "new@g.us")
        self.assertTrue(answer["description_set"])
        self.assertIn("not a jid", self.tool_error("create_group", name="X",
                                                   participants=["Sam"]))

    def test_a_group_not_indexed_yet_leaves_the_description_for_later(self) -> None:
        recorder = self.use(**{"wacli groups create": {"data": {"JID": "new@g.us"}},
                               "chats": {"chats": []}})
        with mock.patch.object(mcp.time, "monotonic", side_effect=[0, 0, 100]):
            answer = self.run_tool("create_group", name="Obra", participants=["a@s.whatsapp.net"],
                                   description="Later")
        self.assertFalse(answer["description_set"])
        self.assertIn("manage_group", answer["note"])
        self.assertEqual(recorder.of("group-action"), [])

    def test_group_management_names_and_tokens(self) -> None:
        recorder = self.use(**{"group-action": {"link": "https://chat.whatsapp.com/X"}})
        self.run_tool("manage_group", jid="g@g.us", action="announce_only", value=True)
        self.run_tool("manage_group", jid="g@g.us", action="add",
                      value=["a@s.whatsapp.net", "+1 555 000 1111"])
        link = self.run_tool("manage_group", jid="g@g.us", action="invite_link")
        self.run_tool("remove_or_leave_group", jid="g@g.us", action="remove",
                      user="a@s.whatsapp.net")
        self.run_tool("remove_or_leave_group", jid="g@g.us", action="reset_invite_link")
        actions = recorder.of("group-action")
        self.assertEqual([payload["action"] for payload in actions],
                         ["announce", "add", "invite-get", "remove", "invite-revoke"])
        self.assertEqual(actions[1]["value"], ["a@s.whatsapp.net", "+15550001111"])
        self.assertEqual(actions[2]["authorization"], "remote-read")
        self.assertEqual(link["link"], "https://chat.whatsapp.com/X")
        self.assertIn("true or false", self.tool_error("manage_group", jid="g@g.us",
                                                       action="locked", value="yes"))
        self.assertIn("exact jid", self.tool_error("remove_or_leave_group", jid="g@g.us",
                                                   action="demote"))


class CommunityTests(ToolCase):
    OUTSIDE = mcp.ToolError("That chat is not available in the local WhatsApp index.")

    def test_a_group_inside_a_community_is_managed_through_the_gateway(self) -> None:
        recorder = self.use(**{"group-action": self.OUTSIDE,
                               "wacli groups invite": {"data": {"link": "https://chat.whatsapp.com/X"}}})
        self.run_tool("remove_or_leave_group", jid="sub@g.us", action="remove",
                      user="a@s.whatsapp.net")
        self.assertEqual(recorder.wacli()[-1], ["groups", "participants", "remove", "--jid",
                                                "sub@g.us", "--user", "a@s.whatsapp.net"])
        self.assertEqual(recorder.token(), "destructive")
        link = self.run_tool("manage_group", jid="sub@g.us", action="invite_link")
        self.assertEqual(recorder.token(), "remote-read")
        self.assertEqual(link["link"], "https://chat.whatsapp.com/X")
        self.assertTrue(link["outside_rail"])
        self.run_tool("manage_group", jid="sub@g.us", action="rename", value="Obra 2")
        self.assertEqual(recorder.wacli()[-1][:2], ["groups", "rename"])
        self.assertEqual(recorder.token(), "whatsapp-write")
        self.run_tool("remove_or_leave_group", jid="community@g.us", action="leave")
        self.assertEqual(recorder.wacli()[-1], ["groups", "leave", "--jid", "community@g.us"])
        self.assertEqual(recorder.token(), "destructive")

    def test_other_helper_errors_are_not_retried_through_the_gateway(self) -> None:
        recorder = self.use(**{"group-action": mcp.ToolError("Offline mode is on.")})
        self.assertIn("Offline", self.tool_error("remove_or_leave_group", jid="g@g.us",
                                                 action="leave"))
        self.assertEqual(recorder.wacli(), [])

    def test_a_community_needs_no_participants_and_a_subgroup_names_its_parent(self) -> None:
        recorder = self.use(**{"wacli groups create": {"data": {"JID": "parent@g.us"}}})
        self.run_tool("create_group", name="Company", community=True)
        self.assertIn("--community", recorder.wacli()[-1])
        self.run_tool("create_group", name="Site", participants=["a@s.whatsapp.net"],
                      community_jid="parent@g.us")
        arguments = recorder.wacli()[-1]
        self.assertEqual(arguments[arguments.index("--linked-parent") + 1], "parent@g.us")


class SecondWaveTests(ToolCase):
    def test_older_history_first_asks_the_user_to_open_the_phone(self) -> None:
        # The owner's idea: the phone answers only while WhatsApp runs there,
        # so the first call only says what to ask and pauses nothing.
        recorder = self.use(chats={"chats": [chat("a@s.whatsapp.net", "Ana")]},
                            **{"chat-details": {"counts": {"total": 10}, "since": 1780000000,
                                                "chat": {"name": "Ana", "kind": "dm"}},
                               "wacli auth status": {"data": {"authenticated": True,
                                                              "phone": "5516000000000"}}})
        answer = self.run_tool("fetch_older_history", chat="Ana")
        self.assertFalse(answer["done"])
        self.assertIn("Open WhatsApp on the phone with the number +5516000000000", answer["ask_user"])
        self.assertIn("not Ana's phone", answer["ask_user"], "the linked phone, not the contact's")
        self.assertIn("nothing older", answer["ask_user"])
        self.assertIn("phone_ready: true", answer["next"])
        self.assertEqual(answer["messages_here"], 10)
        self.assertTrue(answer["local_archive_starts"])
        self.assertEqual([args[:2] for args in recorder.wacli()], [["auth", "status"]],
                         "only a local read; nothing is asked of the phone yet")
        self.assertEqual(recorder.token(), "")

    def test_older_history_asks_the_phone_once_the_user_is_ready(self) -> None:
        counts = iter([{"counts": {"total": 10}}, {"counts": {"total": 60}}])
        recorder = self.use(chats={"chats": [chat("a@s.whatsapp.net", "Ana")]},
                            **{"chat-details": lambda payload, args: next(counts)})
        answer = self.run_tool("fetch_older_history", chat="Ana", batches=2, phone_ready=True)
        self.assertEqual(answer, {"done": True, "fetched": 50, "messages_before": 10,
                                  "messages_now": 60})
        self.assertEqual(recorder.wacli()[0][:3], ["history", "backfill", "--chat"])
        self.assertIn("2", recorder.wacli()[0])
        self.assertEqual(recorder.token(), "sync")

    def test_a_silent_phone_is_explained_not_retried(self) -> None:
        recorder = self.use(chats={"chats": [chat("a@s.whatsapp.net", "Ana")]},
                            **{"chat-details": {"counts": {"total": 10}},
                               "wacli history backfill": mcp.ToolError("WhatsApp took too long to respond.")})
        text = self.tool_error("fetch_older_history", chat="Ana", phone_ready=True)
        self.assertIn("did not answer", text)
        self.assertIn("nothing older", text)
        self.assertIn("phone of the linked number", text)
        self.assertEqual(len(recorder.wacli()), 1, "one attempt, never an automatic retry")

    def test_nothing_new_from_the_phone_says_so(self) -> None:
        self.use(chats={"chats": [chat("a@s.whatsapp.net", "Ana")]},
                 **{"chat-details": {"counts": {"total": 10}}})
        answer = self.run_tool("fetch_older_history", chat="Ana", phone_ready=True)
        self.assertEqual(answer["fetched"], 0)
        self.assertIn("nothing new", answer["note"])

    def test_tags_and_aliases_are_local_writes(self) -> None:
        recorder = self.use()
        answer = self.run_tool("tag_contacts", jids=["a@s.whatsapp.net", "b@s.whatsapp.net"],
                               tag=" suppliers ")
        self.assertEqual(answer["people"], 2)
        self.assertEqual(recorder.wacli()[0], ["contacts", "tags", "add", "--jid",
                                               "a@s.whatsapp.net", "--tag", "suppliers"])
        self.run_tool("tag_contacts", jids=["a@s.whatsapp.net"], tag="suppliers", remove=True)
        self.assertEqual(recorder.wacli()[-1][2], "rm")
        self.run_tool("set_contact_alias", jid="a@s.whatsapp.net", alias="Mechanic João")
        self.run_tool("set_contact_alias", jid="a@s.whatsapp.net", alias="")
        self.assertEqual(recorder.wacli()[-2][:3], ["contacts", "alias", "set"])
        self.assertEqual(recorder.wacli()[-1][:3], ["contacts", "alias", "rm"])
        self.assertTrue(all(payload["authorization"] == "local-write"
                            for name, payload, _ in recorder.calls if name == "wacli"))

    def test_send_individually_personalizes_and_stops_at_a_failure(self) -> None:
        def send(payload: dict, args: tuple) -> dict:
            if payload["jid"] == "c@s.whatsapp.net":
                return mcp.ToolError("Offline mode is on.")
            return {}
        recorder = self.use(
            chats={"chats": [chat("a@s.whatsapp.net", "Ana Souza"),
                             chat("c@s.whatsapp.net", "Caio")]},
            send=send,
            **{"contacts-search": {"people": [{"jid": "b@s.whatsapp.net", "name": "Bruno Lima"}]}})
        answer = self.run_tool("send_individually",
                               jids=["a@s.whatsapp.net", "b@s.whatsapp.net", "a@s.whatsapp.net",
                                     "c@s.whatsapp.net", "d@s.whatsapp.net"],
                               text="Oi {name}, amanhã não tem expediente.")
        self.assertFalse(answer["done"])
        self.assertEqual(answer["sent_to"], ["a@s.whatsapp.net", "b@s.whatsapp.net"])
        self.assertEqual(answer["stopped_at"], "c@s.whatsapp.net")
        self.assertEqual(answer["not_sent"], ["d@s.whatsapp.net"])
        self.assertEqual(recorder.of("send")[0]["text"], "Oi Ana, amanhã não tem expediente.")
        self.assertEqual(recorder.of("send-new")[0]["target"], {"jid": "b@s.whatsapp.net"},
                         "a contact without a chat gets a first message")
        self.assertEqual(recorder.of("send-new")[0]["text"], "Oi Bruno, amanhã não tem expediente.")
        self.assertIn("for people", self.tool_error("send_individually", jids=["g@g.us"],
                                                    text="hi"))

    def test_polls_locations_and_votes(self) -> None:
        recorder = self.use(**{"wacli poll show": {"data": {"question": "Day?"}}})
        self.assertEqual(self.run_tool("poll_results", chat_jid="g@g.us", id="p1")["poll"],
                         {"question": "Day?"})
        self.assertEqual(recorder.token(), "")
        self.run_tool("vote_poll", chat_jid="g@g.us", id="p1", options=["Mon", "Tue"])
        self.assertEqual(recorder.wacli()[-1], ["poll", "vote", "--to", "g@g.us", "--id", "p1",
                                                "--option", "Mon", "--option", "Tue"])
        self.assertEqual(recorder.token(), "whatsapp-write")
        self.run_tool("send_location", jid="a@s.whatsapp.net", latitude=-21.79,
                      longitude=-48.17, name="Obra")
        location = recorder.wacli()[-1]
        self.assertEqual(location[location.index("--latitude") + 1], "-21.79")
        self.assertIn("--name", location)
        self.assertIn("Latitude", self.tool_error("send_location", jid="a@s.whatsapp.net",
                                                  latitude=100, longitude=0))

    def test_profile_and_status_writes(self) -> None:
        recorder = self.use()
        self.assertIn("Choose", self.tool_error("update_profile"))
        with tempfile.NamedTemporaryFile(suffix=".jpg") as photo:
            answer = self.run_tool("update_profile", name="Atos", about="De férias até dia 10",
                                   photo_path=photo.name)
        self.assertEqual(answer["changed"], ["name", "about", "photo"])
        self.assertEqual([item[:2] for item in recorder.wacli()],
                         [["profile", "set-name"], ["profile", "set-about"],
                          ["profile", "set-picture"]])
        self.run_tool("post_status", text="Hello", background_color="#112233")
        self.assertEqual(recorder.wacli()[-1][:2], ["send", "status"])
        self.assertIn("#RRGGBB", self.tool_error("post_status", text="x", background_color="red"))

    def test_a_posted_status_can_be_listed_and_deleted(self) -> None:
        recorder = self.use(**{"wacli send status": {"data": {"sent": True, "id": "ST1"}},
                               "statuses": {"statuses": [
                                   {"id": "ST1", "timestamp": 1790280000, "from_me": True,
                                    "sender": "You", "text": "On holiday"},
                                   {"id": "X", "timestamp": 1790279000, "from_me": False,
                                    "sender": "Sam", "sender_jid": "sam@s.whatsapp.net",
                                    "text": "New tools"}]}})
        posted = self.run_tool("post_status", text="On holiday")
        self.assertEqual(posted["status_id"], "ST1")
        statuses = self.run_tool("list_statuses")["statuses"]
        self.assertEqual([item["id"] for item in statuses], ["ST1", "X"])
        self.assertEqual(statuses[1]["sender"], "Sam")
        self.assertFalse(recorder.of("statuses")[0]["mine_only"])
        self.run_tool("delete_status", id="ST1")
        self.assertEqual(recorder.of("delete-status")[0]["id"], "ST1")

    def test_a_business_number_refusing_the_about_is_explained(self) -> None:
        self.use(**{"wacli profile set-about": mcp.ToolError(
            '{"success":false,"error":"set profile about: graphql error: 400 Bad Request (CRITICAL)"}')})
        text = self.tool_error("update_profile", name="Atos", about="Busy")
        self.assertIn("WhatsApp Business accounts keep it in the business profile", text)
        self.assertIn("Already changed: name", text)

    def test_contact_profile_survives_a_person_without_a_business(self) -> None:
        recorder = self.use(**{"wacli profile get-about": {"data": {"about": "Busy"}},
                               "wacli profile business": mcp.ToolError("not a business")})
        answer = self.run_tool("contact_profile", jid="a@s.whatsapp.net")
        self.assertEqual(answer, {"about": {"about": "Busy"}})
        self.assertEqual(recorder.token(), "remote-read")

    def test_channels_use_their_classes(self) -> None:
        recorder = self.use(**{"wacli channels list": {"data": [{"jid": "n@newsletter"}]},
                               "wacli channels join": {"data": {"joined": True}}})
        self.assertEqual(self.run_tool("list_channels")["channels"], [{"jid": "n@newsletter"}])
        self.run_tool("join_channel", invite="https://whatsapp.com/channel/ABC")
        self.run_tool("leave_channel", jid="n@newsletter")
        self.assertEqual([payload["authorization"] for name, payload, _ in recorder.calls],
                         ["remote-read", "whatsapp-write", "destructive"])

    def test_export_authorizes_the_resolved_destination(self) -> None:
        recorder = self.use(chats={"chats": [chat("a@s.whatsapp.net", "Ana")]})
        with tempfile.TemporaryDirectory() as folder:
            linked = Path(folder) / "link"
            linked.symlink_to(folder)
            self.run_tool("export_chat", chat="Ana", path=str(linked / "ana.json"),
                          after="2026-09-01")
            real = str(Path(folder).resolve() / "ana.json")
        arguments = recorder.wacli()[0]
        self.assertEqual(arguments[arguments.index("--output") + 1], real)
        self.assertEqual(recorder.token(), f"private-export:{real}")
        self.assertIn("absolute", self.tool_error("export_chat", chat="Ana", path="ana.json"))
        with tempfile.TemporaryDirectory() as folder:
            existing = Path(folder) / "ana.json"
            existing.write_text("mine", encoding="utf-8")
            self.assertIn("already there", self.tool_error("export_chat", chat="Ana", path=str(existing)))
            self.assertEqual(existing.read_text(encoding="utf-8"), "mine")

    def test_a_file_expired_on_the_server_suggests_asking_the_phone(self) -> None:
        self.use(attachments={"attachments": [{"chat_jid": "a@s.whatsapp.net", "id": "m1",
                                                "available": True}]},
                 media=mcp.ToolError("download failed with status code 403"))
        answer = self.run_tool("download_pending_media")
        self.assertEqual(answer["expired"], 1)
        self.assertNotIn("failed", answer)
        self.assertIn("ask_phone", answer["hint"])

    def test_join_group_takes_a_link_or_a_code(self) -> None:
        recorder = self.use(**{"wacli groups join": {"data": {"jid": "g@g.us", "joined": True}}})
        answer = self.run_tool("join_group", invite="https://chat.whatsapp.com/AbCdEfGhIjKlMnOpQr12/")
        self.assertEqual(recorder.wacli()[0], ["groups", "join", "--code", "AbCdEfGhIjKlMnOpQr12"])
        self.assertEqual(answer, {"done": True, "jid": "g@g.us"})
        self.assertIn("not a WhatsApp group invite", self.tool_error("join_group", invite="hello"))

    def test_pending_media_downloads_beside_sync_and_skips_expired(self) -> None:
        pending = [{"chat_jid": "a@s.whatsapp.net", "id": "m1", "available": True},
                   {"chat_jid": "a@s.whatsapp.net", "id": "m2", "available": False},
                   {"chat_jid": "a@s.whatsapp.net", "id": "m3", "available": True,
                    "chat_name": "Ana"}]

        def media(payload: dict, args: tuple) -> dict:
            if payload["id"] == "m3":
                return mcp.ToolError("WhatsApp refused the download.")
            return {"local_path": "/private/m1"}
        recorder = self.use(attachments={"attachments": pending}, media=media,
                            **{"wacli media retry": {"data": {"retried": 1}}})
        answer = self.run_tool("download_pending_media", ask_phone=True)
        self.assertEqual(answer["downloaded"], 1)
        self.assertEqual(answer["expired"], 1)
        self.assertEqual(answer["failed"][0]["id"], "m3")
        self.assertNotIn("hint", answer)
        self.assertNotIn("location", recorder.of("attachments")[0]["kinds"])
        self.assertEqual(recorder.token(), "sync", "asking the phone is the only sync step")


FAKE_WACLI = r'''#!/usr/bin/env python3
import json, os, sys
arguments = sys.argv[1:]
with open(os.environ["FAKE_WACLI_LOG"], "a", encoding="utf-8") as log:
    log.write(json.dumps(arguments) + "\n")
if arguments and arguments[0] in ("version", "--version"):
    print("wacli 0.18.3")
    raise SystemExit(0)
# Global flags such as --store PATH come first, so look for the leaf itself.
joined = " " + " ".join(item for item in arguments if not item.startswith("-")) + " "
data = {}
if " groups create " in joined:
    data = {"JID": "new@g.us", "GroupName": {"Name": "Obra"}}
elif " send text " in joined:
    data = {"id": "SENT-1"}
elif " messages export " in joined:
    output = arguments[arguments.index("--output") + 1]
    with open(output, "w", encoding="utf-8") as handle:
        handle.write("[]")
    data = {"path": output}
elif " channels list " in joined:
    data = [{"jid": "n@newsletter", "name": "News"}]
print(json.dumps({"success": True, "data": data}))
'''


class EndToEndTests(unittest.TestCase):
    """The real server and helper over a synthetic mirror and a fake wacli."""

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        # Session markers (quit, launch) live in the runtime directory; keep
        # them in the test's own tree, never the desktop session's.
        runtime = self.root / "runtime"
        runtime.mkdir(mode=0o700, exist_ok=True)
        environment = mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(runtime)})
        environment.start()
        self.addCleanup(environment.stop)
        self.store = self.root / "wacli"
        self.store.mkdir()
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.executescript(SCHEMA)
            connection.executemany("INSERT INTO chats VALUES (?, ?, ?, ?, 0, 0, 0, 0, ?)", [
                ("alex@s.whatsapp.net", "dm", "Alex", 40, 1),
                ("team@g.us", "group", "Design team", 30, 0)])
            connection.executemany(
                """INSERT INTO messages (chat_jid, chat_name, msg_id, sender_jid, sender_name,
                   ts, from_me, text, media_type, filename)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""", [
                    ("alex@s.whatsapp.net", "Alex", "a1", "alex@s.whatsapp.net", "Alex", 40, 0,
                     "did you see the movie?", "", ""),
                    ("team@g.us", "Design team", "t1", "member@s.whatsapp.net", "Sam", 30, 0,
                     "", "document", "plan.pdf")])
            connection.executemany("INSERT INTO contacts VALUES (?, ?, ?, ?, ?, ?, ?, ?)", [
                ("alex@s.whatsapp.net", "15557654321", "Alex", "Alex Kim", "Alex", "", "", 1),
                ("member@s.whatsapp.net", "15551234567", "Sam", "Sam Rivera", "Sam", "", "", 1)])
            connection.execute("INSERT INTO groups (jid, name, updated_at) VALUES "
                               "('team@g.us', 'Design team', 1)")
            connection.execute("INSERT INTO group_participants VALUES "
                               "('team@g.us', 'member@s.whatsapp.net', 'member', 1)")
        self.wacli = self.root / "wacli-bin"
        self.wacli.write_text(FAKE_WACLI, encoding="utf-8")
        self.wacli.chmod(0o700)
        self.log = self.root / "wacli.log"
        self.environment = dict(os.environ, OMAW_HELPER=str(SCRIPT.with_name("omawhatsapp")), WACLI_BIN=str(self.wacli),
                                WACLI_STORE_DIR=str(self.store), HOME=str(self.root),
                                XDG_STATE_HOME=str(self.root / "state"),
                                XDG_CONFIG_HOME=str(self.root / "config"),
                                FAKE_WACLI_LOG=str(self.log))

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def session(self, *calls: tuple[str, dict]) -> list[dict]:
        requests = [{"jsonrpc": "2.0", "id": 0, "method": "initialize",
                     "params": {"protocolVersion": "2025-06-18"}},
                    {"jsonrpc": "2.0", "method": "notifications/initialized"}]
        requests += [{"jsonrpc": "2.0", "id": index + 1, "method": "tools/call",
                      "params": {"name": name, "arguments": arguments}}
                     for index, (name, arguments) in enumerate(calls)]
        result = subprocess.run(
            [sys.executable, str(SERVER)], input="\n".join(map(json.dumps, requests)) + "\n",
            capture_output=True, text=True, env=self.environment, timeout=120, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(replies[0]["result"]["serverInfo"]["name"], "omawhatsapp")
        return [reply["result"] for reply in replies[1:]]

    def wacli_calls(self) -> list[list[str]]:
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text(encoding="utf-8").splitlines()]

    def payload(self, result: dict) -> dict:
        self.assertFalse(result["isError"], result["content"][0]["text"])
        return json.loads(result["content"][0]["text"])

    def test_reads_come_from_the_local_mirror(self) -> None:
        chats, chat_page, attachments, people = self.session(
            ("list_chats", {}), ("read_chat", {"chat": "Alex"}),
            ("list_attachments", {"kinds": ["document"]}), ("find_contacts", {"query": "sam"}))
        self.assertEqual([row["name"] for row in self.payload(chats)["chats"]],
                         ["Alex Kim", "Design team"], "the name saved on the phone")
        self.assertEqual(self.payload(chat_page)["messages"][0]["text"], "did you see the movie?")
        self.assertEqual(self.payload(attachments)["attachments"][0]["filename"], "plan.pdf")
        self.assertEqual(self.payload(people)["people"][0]["jid"], "member@s.whatsapp.net")
        self.assertFalse(any("send" in call for call in self.wacli_calls()),
                         "reading never writes to WhatsApp")

    def test_a_reply_reaches_wacli_with_the_exact_target(self) -> None:
        (result,) = self.session(("send_message", {"jid": "alex@s.whatsapp.net", "text": "yes!"}))
        self.assertEqual(self.payload(result)["message_id"], "SENT-1")
        send = next(call for call in self.wacli_calls() if "send" in call and "text" in call)
        self.assertEqual(send[send.index("--to") + 1], "alex@s.whatsapp.net")
        self.assertEqual(send[send.index("--message") + 1], "yes!")

    def test_the_helper_accepts_every_token_the_server_sends(self) -> None:
        export = self.root / "exports" / "alex.json"
        export.parent.mkdir()
        results = self.session(
            ("create_group", {"name": "Obra", "participants": ["member@s.whatsapp.net"]}),
            ("tag_contacts", {"jids": ["member@s.whatsapp.net"], "tag": "suppliers"}),
            ("export_chat", {"chat": "alex@s.whatsapp.net", "path": str(export)}),
            ("list_channels", {}),
            ("fetch_older_history", {"chat": "alex@s.whatsapp.net", "phone_ready": True}),
            ("search_messages", {"query": "movie"}),
        )
        for result in results:
            self.payload(result)
        leaves = [" ".join(item for item in call if not item.startswith("-"))
                  for call in self.wacli_calls()]
        for expected in ("groups create", "contacts tags add", "messages export",
                         "channels list", "history backfill", "messages search"):
            self.assertTrue(any(expected in leaf for leaf in leaves), expected)
        self.assertEqual(export.read_text(encoding="utf-8"), "[]")
        self.assertEqual(self.payload(results[0])["jid"], "new@g.us")

    def test_a_guessed_recipient_never_reaches_wacli(self) -> None:
        (result,) = self.session(("send_message", {"jid": "stranger@s.whatsapp.net",
                                                   "text": "hi"}))
        self.assertTrue(result["isError"])
        self.assertFalse(any("send" in call for call in self.wacli_calls()))


if __name__ == "__main__":
    unittest.main()
