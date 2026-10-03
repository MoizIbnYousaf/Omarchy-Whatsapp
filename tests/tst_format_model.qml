import QtQuick
import QtTest
import "../plugins/omawhatsapp/FormatModel.js" as FormatModel

// WhatsApp's formatting, as the phone reads it, and the only path from a
// message to rich text: everything the message holds is escaped first.
TestCase {
  name: "FormatModel"

  function body(text) {
    var html = FormatModel.toHtml(text, { dim: "#999999", code: "#33000000" })
    return html.replace(/^<span style="white-space: pre-wrap">/, "").replace(/<\/span>$/, "")
  }

  function test_inline_markers() {
    compare(body("*bold*"), "<b>bold</b>")
    compare(body("_italic_"), "<i>italic</i>")
    compare(body("~gone~"), "<s>gone</s>")
    compare(body("a *very* good _day_"), "a <b>very</b> good <i>day</i>")
    compare(body("*_both_*"), "<b><i>both</i></b>")
    compare(body("(*bold*)."), "(<b>bold</b>).")
  }

  function test_what_whatsapp_leaves_as_typed() {
    compare(body("snake_case_name"), "snake_case_name")
    compare(body("2*3*4"), "2*3*4")
    compare(body("* not bold *"), "&nbsp;•&nbsp;not bold *")
    compare(body("a * b * c"), "a * b * c")
    compare(body("**"), "**")
    compare(body("*open"), "*open")
    compare(body("file_v2_final.pdf"), "file_v2_final.pdf")
  }

  function test_code_and_monospace_hold_their_text_as_is() {
    verify(body("`*raw*`").indexOf("*raw*") >= 0, "no formatting inside inline code")
    verify(body("`x`").indexOf("font-family: monospace") >= 0)
    var block = body("```line one\n*two*```")
    verify(block.indexOf("line one<br>*two*") >= 0, "monospace keeps lines and markers")
  }

  function test_lists_and_quotes_at_the_start_of_a_line() {
    compare(body("- milk\n- eggs"), "&nbsp;•&nbsp;milk<br>&nbsp;•&nbsp;eggs")
    compare(body("1. first\n2. *second*"), "&nbsp;1.&nbsp;first<br>&nbsp;2.&nbsp;<b>second</b>")
    compare(body("> said this"), "<span style=\"color: #999999\">▍ said this</span>")
    compare(body("not - a list"), "not - a list")
  }

  function test_nothing_from_a_message_becomes_markup() {
    compare(body("<b>x</b>"), "&lt;b&gt;x&lt;/b&gt;")
    compare(body("<img src=x onerror=alert(1)>"), "&lt;img src=x onerror=alert(1)&gt;")
    compare(body("<a href=\"http://x\">y</a>"), "&lt;a href=&quot;http://x&quot;&gt;y&lt;/a&gt;")
    compare(body("&amp; &lt;"), "&amp;amp; &amp;lt;")
    compare(body("`<script>`"), "<span style=\"font-family: monospace; background-color: #33000000\">&lt;script&gt;</span>")
    compare(body("*<i>*"), "<b>&lt;i&gt;</b>")
    verify(body("\u0000" + "0" + "\u0000").indexOf("<span") < 0, "a message cannot forge a held block")
  }

  function test_plain_text_stays_plain() {
    verify(!FormatModel.hasFormatting("just words, 2*3 and snake_case"))
    verify(FormatModel.hasFormatting("a *b* c"))
    verify(FormatModel.hasFormatting("- item"))
    verify(FormatModel.hasFormatting("`x`"))
    compare(FormatModel.plain("*Hi* _there_, `code` and ```block```"), "Hi there, code and block")
  }

  function test_wrap_adds_and_removes_markers_around_the_words() {
    compare(FormatModel.wrap("hello world", 6, 11, "bold"), { text: "hello *world*", start: 7, end: 12 })
    compare(FormatModel.wrap("hello *world*", 7, 12, "bold"), { text: "hello world", start: 6, end: 11 })
    compare(FormatModel.wrap("say hi ", 4, 7, "italic"), { text: "say _hi_ ", start: 5, end: 7 },
      "the trailing space stays outside the marker")
    compare(FormatModel.wrap("ab", 1, 1, "strike"), { text: "a~~b", start: 2, end: 2 })
    compare(FormatModel.wrap("x", 0, 1, "mono"), { text: "```x```", start: 3, end: 4 })
    compare(FormatModel.wrap("x", 0, 1, "code"), { text: "`x`", start: 1, end: 2 })
  }

  function test_prefix_lines_makes_and_undoes_lists_and_quotes() {
    compare(FormatModel.prefixLines("milk\neggs", 0, 9, "bullet").text, "- milk\n- eggs")
    compare(FormatModel.prefixLines("- milk\n- eggs", 0, 13, "bullet").text, "milk\neggs")
    compare(FormatModel.prefixLines("a\nb\nc", 0, 5, "numbered").text, "1. a\n2. b\n3. c")
    compare(FormatModel.prefixLines("intro\nquoted", 8, 8, "quote").text, "intro\n> quoted",
      "only the line under the cursor")
    compare(FormatModel.prefixLines("- a", 0, 3, "numbered").text, "1. a", "a bullet becomes a number")
  }
}
