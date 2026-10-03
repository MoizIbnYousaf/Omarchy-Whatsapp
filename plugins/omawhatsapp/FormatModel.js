.pragma library

// WhatsApp's text formatting, read and written.
//
// toHtml() is the only path from a message to rich text. It escapes every
// character first and then emits a fixed set of tags (b, i, s, spans for code,
// monospace blocks, lists and quotes), so nothing a message contains can
// become a link, an image, a style or any other markup.
//
// Rules follow WhatsApp: *bold*, _italic_, ~strikethrough~, ```monospace```,
// `inline code`, "- " or "* " bullets, "1. " numbers and "> " quotes at the
// start of a line. An inline marker opens after a space, punctuation or the
// line start and before a non-space, and closes after a non-space and before
// a space, punctuation or the line end, so snake_case and 2*3*4 stay as typed.

var INLINE = { "*": "b", "_": "i", "~": "s" }

function escapeHtml(value) {
  return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;")
}

// Letters and digits of the scripts people write in, as marker boundaries.
function isWordChar(ch) {
  return !!ch && /[0-9A-Za-zªµºÀ-ÖØ-öø-˿Ͱ-῿Ⰰ-퟿]/.test(ch)
}

function isSpace(ch) { return !ch || /\s/.test(ch) }

// Inline markers over one escaped line, nesting allowed (*_both_*).
function inline(line) {
  var out = ""
  var i = 0
  while (i < line.length) {
    var ch = line[i]
    var tag = INLINE[ch]
    if (tag && !isWordChar(line[i - 1]) && !isSpace(line[i + 1]) && line[i + 1] !== ch) {
      var close = -1
      var j = i + 1
      while ((j = line.indexOf(ch, j + 1)) !== -1) {
        if (!isSpace(line[j - 1]) && !isWordChar(line[j + 1])) { close = j; break }
      }
      if (close > i + 1) {
        out += "<" + tag + ">" + inline(line.substring(i + 1, close)) + "</" + tag + ">"
        i = close + 1
        continue
      }
    }
    out += ch
    i += 1
  }
  return out
}

function codeSpan(content, colors) {
  return "<span style=\"font-family: monospace; background-color: " + colors.code + "\">"
    + content + "</span>"
}

// Rich text for a message body; colors = { dim, code } as #RRGGBB or #AARRGGBB.
function toHtml(text, colors) {
  var palette = colors || {}
  var tones = { dim: palette.dim || "#888888", code: palette.code || "#33888888" }
  // A message never carries the NUL marks that stand for held blocks.
  var source = String(text || "").replace(/\u0000/g, "")
  var held = []
  function hold(html) {
    held.push(html)
    return "\u0000" + (held.length - 1) + "\u0000"
  }
  // Monospace blocks first: nothing inside them is formatting.
  source = source.replace(/```([\s\S]+?)```/g, function(match, body) {
    return hold("<span style=\"font-family: monospace; background-color: " + tones.code
      + "\">" + escapeHtml(body).replace(/\n/g, "<br>") + "</span>")
  })
  source = source.replace(/`([^`\n]+)`/g, function(match, body) {
    return hold(codeSpan(escapeHtml(body), tones))
  })
  var lines = escapeHtml(source).split("\n").map(function(line) {
    var bullet = /^(\s*)[-*] (.*)$/.exec(line)
    if (bullet) return bullet[1] + "&nbsp;•&nbsp;" + inline(bullet[2])
    var numbered = /^(\s*)(\d{1,3})\. (.*)$/.exec(line)
    if (numbered) return numbered[1] + "&nbsp;" + numbered[2] + ".&nbsp;" + inline(numbered[3])
    var quote = /^&gt; ?(.*)$/.exec(line)
    if (quote) return "<span style=\"color: " + tones.dim + "\">▍ " + inline(quote[1]) + "</span>"
    return inline(line)
  })
  var html = lines.join("<br>").replace(/\u0000(\d+)\u0000/g, function(match, index) {
    return held[Number(index)]
  })
  return "<span style=\"white-space: pre-wrap\">" + html + "</span>"
}

// Whether a message uses any formatting, so plain ones stay plain text.
function hasFormatting(text) {
  var value = String(text || "")
  if (/```[\s\S]+?```|`[^`\n]+`/.test(value)) return true
  if (/^(\s*[-*] |\s*\d{1,3}\. |> ?)/m.test(value)) return true
  return inline(escapeHtml(value)) !== escapeHtml(value)
}

// The words without markers, for previews and notifications.
function plain(text) {
  var value = String(text || "")
  value = value.replace(/```([\s\S]+?)```/g, "$1").replace(/`([^`\n]+)`/g, "$1")
  return value.split("\n").map(function(line) {
    var out = ""
    var i = 0
    while (i < line.length) {
      var ch = line[i]
      if (INLINE[ch] && !isWordChar(line[i - 1]) && !isSpace(line[i + 1]) && line[i + 1] !== ch) {
        var j = i + 1
        var close = -1
        while ((j = line.indexOf(ch, j + 1)) !== -1) {
          if (!isSpace(line[j - 1]) && !isWordChar(line[j + 1])) { close = j; break }
        }
        if (close > i + 1) {
          out += plain(line.substring(i + 1, close))
          i = close + 1
          continue
        }
      }
      out += ch
      i += 1
    }
    return out
  }).join("\n")
}

// ------------------------------------------------------------------ writing

var WRAPS = { bold: "*", italic: "_", strike: "~", mono: "```", code: "`" }
var PREFIXES = { bullet: "- ", numbered: "", quote: "> " }

// Wrap the selection in a marker, or unwrap it when it already is. Spaces at
// the edges of the selection stay outside, because WhatsApp needs the marker
// against the words. With no selection, the pair is inserted around the
// cursor. Returns { text, start, end } for the new selection.
function wrap(text, start, end, kind) {
  var marker = WRAPS[kind]
  var value = String(text || "")
  var from = Math.max(0, Math.min(start, end))
  var to = Math.min(value.length, Math.max(start, end))
  if (!marker) return { text: value, start: from, end: to }
  while (from < to && /\s/.test(value[from])) from += 1
  while (to > from && /\s/.test(value[to - 1])) to -= 1
  var size = marker.length
  if (from >= size && value.substring(from - size, from) === marker
      && value.substring(to, to + size) === marker) {
    return {
      text: value.substring(0, from - size) + value.substring(from, to) + value.substring(to + size),
      start: from - size, end: to - size
    }
  }
  return {
    text: value.substring(0, from) + marker + value.substring(from, to) + marker + value.substring(to),
    start: from + size, end: to + size
  }
}

// Turn the lines under the selection into a list or a quote, or back.
function prefixLines(text, start, end, kind) {
  var value = String(text || "")
  var from = Math.max(0, Math.min(start, end))
  var to = Math.min(value.length, Math.max(start, end))
  var lineStart = value.lastIndexOf("\n", from - 1) + 1
  var nextBreak = value.indexOf("\n", to > from ? to - 1 : to)
  var lineEnd = nextBreak < 0 ? value.length : nextBreak
  var lines = value.substring(lineStart, lineEnd).split("\n")
  var pattern = kind === "numbered" ? /^\d{1,3}\. / : (kind === "quote" ? /^> / : /^[-*] /)
  var all = lines.every(function(line) { return pattern.test(line) })
  var changed = lines.map(function(line, index) {
    if (all) return line.replace(pattern, "")
    var bare = line.replace(/^([-*] |\d{1,3}\. |> )/, "")
    return (kind === "numbered" ? (index + 1) + ". " : PREFIXES[kind]) + bare
  }).join("\n")
  return {
    text: value.substring(0, lineStart) + changed + value.substring(lineEnd),
    start: lineStart, end: lineStart + changed.length
  }
}

// Apply a formatting kind to a composer's text and selection. Returns the
// minimal edit (remove [head, end), insert text at head) so an editor can
// apply it with remove/insert and keep its undo history, and the selection
// to restore; null when nothing changes.
function apply(text, start, end, kind) {
  var before = String(text || "")
  var result = ["bullet", "numbered", "quote"].indexOf(kind) >= 0
    ? prefixLines(before, start, end, kind) : wrap(before, start, end, kind)
  var next = result.text
  if (next === before) return null
  var head = 0
  while (head < before.length && head < next.length && before[head] === next[head]) head++
  var tail = 0
  while (tail < before.length - head && tail < next.length - head
         && before[before.length - 1 - tail] === next[next.length - 1 - tail]) tail++
  return { head: head, end: before.length - tail, insert: next.substring(head, next.length - tail),
           start: result.start, selectEnd: result.end, text: next }
}

if (typeof module !== "undefined") {
  module.exports = { toHtml: toHtml, hasFormatting: hasFormatting, plain: plain,
                     wrap: wrap, prefixLines: prefixLines, escapeHtml: escapeHtml }
}
