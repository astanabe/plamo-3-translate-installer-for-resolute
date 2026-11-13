#!/usr/bin/python3
"""PLaMo 3 Translate web server (WSGI application for uWSGI).

GET  /               translation form (HTML)
POST /api/translate  JSON API:
    request  {"text": str, "target_lang": str, "source_lang": str?,
              "form": "plain"|"polite"?, "glossary": [{"source", "target"}]?,
              "context": str?}
    response {"translation": str}  or  {"error": str}
             (400 for invalid input, including text that does not fit in the
             llama-server context; 502 for other llama-server errors)

The request is forwarded to llama-server's /v1/chat/completions with the
translation settings in chat_template_kwargs.  Python standard library only.

Environment variables:
    PLAMO3_LLAMA_URL        llama-server address: unix:<socket path> or http://<host>:<port>
                            (default unix:/run/plamo-3-translate-llama/llama.sock)
    PLAMO3_LLAMA_API_KEY    llama-server API key (default: none)
    PLAMO3_LLAMA_TIMEOUT    timeout in seconds for llama-server (default 3600)
    PLAMO3_MAX_TEXT_CHARS   maximum length of text/context in characters (default 1000000);
                            the token limit is the llama-server context size
    PLAMO3_MAX_TOKENS       maximum number of generated tokens (default 262144); each
                            request is also limited to 4 x len(text) + 256 tokens
"""

import http.client
import json
import os
import socket
import urllib.parse

LLAMA_URL = (os.environ.get("PLAMO3_LLAMA_URL") or "unix:/run/plamo-3-translate-llama/llama.sock").rstrip("/")
LLAMA_API_KEY = os.environ.get("PLAMO3_LLAMA_API_KEY", "")
LLAMA_TIMEOUT = float(os.environ.get("PLAMO3_LLAMA_TIMEOUT", "3600"))
MAX_TEXT_CHARS = int(os.environ.get("PLAMO3_MAX_TEXT_CHARS", "1000000"))
MAX_TOKENS = int(os.environ.get("PLAMO3_MAX_TOKENS", "262144"))
MAX_GLOSSARY_ENTRIES = 500
MAX_BODY_BYTES = 8 * 1024 * 1024
MODEL_ALIAS = "plamo-3-translate"
STOP = ["<|plamo:tag|>", "<|plamo:bos|>"]

# Supported languages (model card, "Supported Languages").
LANGUAGES = [
    ("ja", "Japanese"), ("en", "English"),
    ("zh-hans", "Chinese (Simplified)"), ("zh-hant", "Chinese (Traditional)"),
    ("ko", "Korean"), ("ar", "Arabic"), ("az", "Azerbaijani"),
    ("be", "Belarusian"), ("bg", "Bulgarian"), ("bn", "Bengali"),
    ("ca", "Catalan"), ("ceb", "Cebuano"), ("de", "German"),
    ("es", "Spanish"), ("et", "Estonian"), ("eu", "Basque"),
    ("fa", "Persian"), ("fr", "French"), ("gu", "Gujarati"),
    ("he", "Hebrew"), ("hi", "Hindi"), ("hr", "Croatian"),
    ("hu", "Hungarian"), ("hy", "Armenian"), ("id", "Indonesian"),
    ("it", "Italian"), ("jv", "Javanese"), ("ka", "Georgian"),
    ("kk", "Kazakh"), ("km", "Khmer"), ("lt", "Lithuanian"),
    ("lv", "Latvian"), ("ml", "Malayalam"), ("mr", "Marathi"),
    ("ms", "Malay"), ("my", "Burmese"), ("ne", "Nepali"),
    ("nl", "Dutch"), ("pa", "Punjabi"), ("pl", "Polish"),
    ("ru", "Russian"), ("si", "Sinhala"), ("sk", "Slovak"),
    ("sl", "Slovenian"), ("sr", "Serbian"), ("sw", "Swahili"),
    ("ta", "Tamil"), ("te", "Telugu"), ("th", "Thai"),
    ("tl", "Tagalog"), ("ur", "Urdu"), ("uz", "Uzbek"),
    ("vi", "Vietnamese"),
]
LANGUAGE_CODES = {code for code, _ in LANGUAGES}
FORMS = ("plain", "polite")
RESERVED = "<|plamo:"


class UnixHTTPConnection(http.client.HTTPConnection):
    """HTTP over a UNIX domain socket."""

    def __init__(self, path, timeout):
        super().__init__("localhost", timeout=timeout)
        self.socket_path = path

    def connect(self):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        try:
            sock.connect(self.socket_path)
        except OSError:
            sock.close()
            raise
        self.sock = sock


def llama_connection():
    """Return (connection, path prefix) for PLAMO3_LLAMA_URL."""
    if LLAMA_URL.startswith("unix:"):
        return UnixHTTPConnection(LLAMA_URL[len("unix:"):], LLAMA_TIMEOUT), ""
    url = urllib.parse.urlsplit(LLAMA_URL)
    if url.scheme != "http" or not url.hostname:
        raise UpstreamError("PLAMO3_LLAMA_URL must be unix:<path> or http://<host>:<port>")
    return http.client.HTTPConnection(url.hostname, url.port or 80, timeout=LLAMA_TIMEOUT), url.path


class BadRequest(Exception):
    pass


class UpstreamError(Exception):
    pass


def _check_text(value, name, allow_empty=False, max_chars=MAX_TEXT_CHARS):
    if not isinstance(value, str):
        raise BadRequest(f"{name} must be a string")
    if not allow_empty and not value.strip():
        raise BadRequest(f"{name} must not be empty")
    if len(value) > max_chars:
        raise BadRequest(f"{name} is too long (max {max_chars} characters)")
    if RESERVED in value:
        raise BadRequest(f"{name} must not contain reserved tokens ({RESERVED}...)")
    return value


def _optional(req, key):
    value = req.get(key)
    if value is None or (isinstance(value, str) and not value.strip()):
        return None
    return value


def validate_request(req):
    """Validate the API request and return chat_template_kwargs and the text."""
    if not isinstance(req, dict):
        raise BadRequest("request body must be a JSON object")
    unknown = set(req) - {"text", "target_lang", "source_lang", "form", "glossary", "context"}
    if unknown:
        raise BadRequest("unknown field(s): " + ", ".join(sorted(unknown)))

    text = _check_text(req.get("text"), "text")
    kwargs = {}

    target = req.get("target_lang")
    if not isinstance(target, str) or target not in LANGUAGE_CODES:
        raise BadRequest("target_lang must be one of the supported language codes")
    kwargs["target_lang"] = target

    source = _optional(req, "source_lang")
    if source is not None:
        if not isinstance(source, str) or source not in LANGUAGE_CODES:
            raise BadRequest("source_lang must be one of the supported language codes")
        kwargs["source_lang"] = source

    form = _optional(req, "form")
    if form is not None:
        if form not in FORMS:
            raise BadRequest("form must be plain or polite")
        if target != "ja":
            raise BadRequest('form requires target_lang "ja"')
        kwargs["form"] = form

    context = _optional(req, "context")
    if context is not None:
        kwargs["context"] = _check_text(context, "context")

    glossary = req.get("glossary")
    if glossary:
        if not isinstance(glossary, list):
            raise BadRequest("glossary must be a list of {source, target} objects")
        if len(glossary) > MAX_GLOSSARY_ENTRIES:
            raise BadRequest(f"glossary has too many entries (max {MAX_GLOSSARY_ENTRIES})")
        entries = []
        for term in glossary:
            if not isinstance(term, dict) or set(term) != {"source", "target"}:
                raise BadRequest("each glossary entry must have exactly source and target")
            entries.append({
                "source": _check_text(term["source"], "glossary source", max_chars=1000).strip(),
                "target": _check_text(term["target"], "glossary target", max_chars=1000).strip(),
            })
        kwargs["glossary"] = entries

    return text, kwargs


def translate(text, kwargs):
    payload = {
        "model": MODEL_ALIAS,
        "messages": [{"role": "user", "content": text}],
        "chat_template_kwargs": kwargs,
        "temperature": 0,
        # A translation is not much longer than its source; the bound stops runaway repetition.
        "max_tokens": min(MAX_TOKENS, 4 * len(text) + 256),
        "stop": STOP,
        "stream": False,
    }
    headers = {"Content-Type": "application/json"}
    if LLAMA_API_KEY:
        headers["Authorization"] = "Bearer " + LLAMA_API_KEY
    conn, prefix = llama_connection()
    try:
        conn.request("POST", prefix + "/v1/chat/completions",
                     body=json.dumps(payload).encode("utf-8"), headers=headers)
        response = conn.getresponse()
        data = response.read()
    except (OSError, http.client.HTTPException) as e:
        raise UpstreamError(f"cannot reach llama-server ({LLAMA_URL}): {e}")
    finally:
        conn.close()
    try:
        body = json.loads(data)
    except ValueError:
        body = None
    if response.status != 200:
        detail = ""
        if isinstance(body, dict) and isinstance(body.get("error"), dict):
            detail = body["error"].get("message", "")
        message = f"llama-server returned HTTP {response.status}" + (f": {detail}" if detail else "")
        if response.status == 400:  # e.g. the request exceeds the context size
            raise BadRequest(message)
        raise UpstreamError(message)
    try:
        content = body["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        raise UpstreamError("unexpected response from llama-server")
    if not isinstance(content, str):
        raise UpstreamError("unexpected response from llama-server")
    return content.strip()


def _json_response(start_response, status, obj):
    body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
    start_response(status, [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Content-Length", str(len(body))),
        ("Cache-Control", "no-store"),
    ])
    return [body]


def _read_body(environ):
    try:
        length = int(environ.get("CONTENT_LENGTH") or 0)
    except ValueError:
        raise BadRequest("invalid Content-Length")
    if length <= 0:
        raise BadRequest("request body is empty")
    if length > MAX_BODY_BYTES:
        raise BadRequest(f"request body is too large (max {MAX_BODY_BYTES} bytes)")
    data = environ["wsgi.input"].read(length)
    try:
        return json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        raise BadRequest("request body must be valid JSON")


def api_translate(environ, start_response):
    if environ.get("REQUEST_METHOD") != "POST":
        start_response("405 Method Not Allowed", [("Allow", "POST"), ("Content-Type", "application/json")])
        return [b'{"error": "method not allowed"}']
    content_type = environ.get("CONTENT_TYPE", "").split(";")[0].strip().lower()
    try:
        if content_type != "application/json":
            raise BadRequest("Content-Type must be application/json")
        text, kwargs = validate_request(_read_body(environ))
        translation = translate(text, kwargs)
    except BadRequest as e:
        return _json_response(start_response, "400 Bad Request", {"error": str(e)})
    except UpstreamError as e:
        return _json_response(start_response, "502 Bad Gateway", {"error": str(e)})
    return _json_response(start_response, "200 OK", {"translation": translation})


def index(environ, start_response):
    if environ.get("REQUEST_METHOD") not in ("GET", "HEAD"):
        start_response("405 Method Not Allowed", [("Allow", "GET, HEAD"), ("Content-Type", "text/plain")])
        return [b"method not allowed\n"]
    options = "\n".join(
        f'<option value="{code}">{name} ({code})</option>' for code, name in LANGUAGES
    )
    body = INDEX_HTML.replace("@@LANGUAGE_OPTIONS@@", options).encode("utf-8")
    start_response("200 OK", [
        ("Content-Type", "text/html; charset=utf-8"),
        ("Content-Length", str(len(body))),
        ("X-Content-Type-Options", "nosniff"),
        ("Content-Security-Policy",
         "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'"),
    ])
    return [] if environ.get("REQUEST_METHOD") == "HEAD" else [body]


def application(environ, start_response):
    path = environ.get("PATH_INFO", "/") or "/"
    if path == "/":
        return index(environ, start_response)
    if path == "/api/translate":
        return api_translate(environ, start_response)
    start_response("404 Not Found", [("Content-Type", "text/plain")])
    return [b"not found\n"]


INDEX_HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PLaMo 3 Translate</title>
<style>
  :root { color-scheme: light dark; --fg: #1d1d1f; --bg: #fafafa; --muted: #666;
          --border: #ccc; --card: #fff; --accent: #2f5fd0; --err: #b00020; }
  @media (prefers-color-scheme: dark) {
    :root { --fg: #e8e8e8; --bg: #161618; --muted: #9a9a9a; --border: #444;
            --card: #1f1f22; --accent: #7aa2ff; --err: #ff6b81; }
  }
  * { box-sizing: border-box; }
  body { margin: 0; padding: 1.5rem 1rem; font: 15px/1.5 system-ui, sans-serif;
         color: var(--fg); background: var(--bg); }
  main { max-width: 72rem; margin: 0 auto; }
  h1 { font-size: 1.4rem; margin: 0 0 1rem; }
  .row { display: flex; flex-wrap: wrap; gap: 1rem; }
  .row > * { flex: 1 1 18rem; min-width: 0; }
  label { display: block; font-weight: 600; margin: .75rem 0 .25rem; }
  .hint { font-weight: normal; color: var(--muted); font-size: .85rem; }
  textarea, select, input { width: 100%; font: inherit; color: inherit; background: var(--card);
         border: 1px solid var(--border); border-radius: 6px; padding: .5rem; }
  textarea { resize: vertical; }
  #text, #result { min-height: 14rem; }
  #result { white-space: pre-wrap; }
  details { margin-top: .75rem; }
  summary { cursor: pointer; font-weight: 600; }
  .actions { display: flex; align-items: center; gap: 1rem; margin-top: 1rem; }
  button { font: inherit; padding: .5rem 1.5rem; border: 0; border-radius: 6px;
           background: var(--accent); color: #fff; cursor: pointer; }
  button:disabled { opacity: .5; cursor: progress; }
  #status { color: var(--muted); }
  #status.error { color: var(--err); }
</style>
</head>
<body>
<main>
<h1>PLaMo 3 Translate</h1>
<form id="f">
  <div class="row">
    <div>
      <label for="source_lang">Source language</label>
      <select id="source_lang"><option value="">Detect automatically</option>
@@LANGUAGE_OPTIONS@@
      </select>
    </div>
    <div>
      <label for="target_lang">Target language</label>
      <select id="target_lang">
@@LANGUAGE_OPTIONS@@
      </select>
    </div>
    <div>
      <label for="form">Japanese style <span class="hint">(target Japanese only)</span></label>
      <select id="form"><option value="">Default</option>
        <option value="polite">Polite (desu/masu)</option>
        <option value="plain">Plain (da/dearu)</option>
      </select>
    </div>
  </div>
  <div class="row">
    <div>
      <label for="text">Source text</label>
      <textarea id="text" required></textarea>
    </div>
    <div>
      <label for="result">Translation</label>
      <textarea id="result" readonly></textarea>
    </div>
  </div>
  <details>
    <summary>Glossary and context</summary>
    <div class="row">
      <div>
        <label for="glossary">Glossary <span class="hint">(one term per line: source =&gt; target)</span></label>
        <textarea id="glossary" rows="5" placeholder="管理画面 =&gt; dashboard"></textarea>
      </div>
      <div>
        <label for="context">Context <span class="hint">(surrounding text or situation; not translated)</span></label>
        <textarea id="context" rows="5"></textarea>
      </div>
    </div>
  </details>
  <div class="actions">
    <button id="go" type="submit">Translate</button>
    <span id="status" role="status"></span>
  </div>
</form>
</main>
<script>
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var KEY = "plamo-3-translate-settings";
  var fields = ["source_lang", "target_lang", "form"];
  try {
    var saved = JSON.parse(localStorage.getItem(KEY) || "{}");
    fields.forEach(function (k) { if (saved[k] !== undefined) $(k).value = saved[k]; });
  } catch (e) {}
  if (!$("target_lang").value) $("target_lang").value = "en";
  function syncForm() { $("form").disabled = $("target_lang").value !== "ja"; }
  $("target_lang").addEventListener("change", syncForm);
  syncForm();

  function parseGlossary(src) {
    var out = [];
    src.split("\\n").forEach(function (line, i) {
      if (!line.trim()) return;
      var p = line.split("=>");
      if (p.length !== 2 || !p[0].trim() || !p[1].trim())
        throw new Error("Glossary line " + (i + 1) + " must be: source => target");
      out.push({ source: p[0].trim(), target: p[1].trim() });
    });
    return out;
  }

  $("f").addEventListener("submit", function (ev) {
    ev.preventDefault();
    var status = $("status");
    status.className = "";
    var req = { text: $("text").value, target_lang: $("target_lang").value };
    if ($("source_lang").value) req.source_lang = $("source_lang").value;
    if (!$("form").disabled && $("form").value) req.form = $("form").value;
    if ($("context").value.trim()) req.context = $("context").value;
    try {
      var g = parseGlossary($("glossary").value);
      if (g.length) req.glossary = g;
    } catch (e) { status.className = "error"; status.textContent = e.message; return; }
    try {
      var s = {}; fields.forEach(function (k) { s[k] = $(k).value; });
      localStorage.setItem(KEY, JSON.stringify(s));
    } catch (e) {}
    $("go").disabled = true;
    status.textContent = "Translating...";
    var t0 = Date.now();
    fetch("api/translate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(req)
    }).then(function (r) {
      return r.json().catch(function () { return { error: "HTTP " + r.status }; });
    }).then(function (d) {
      if (d.error) throw new Error(d.error);
      $("result").value = d.translation;
      status.textContent = "Done in " + ((Date.now() - t0) / 1000).toFixed(1) + " s";
    }).catch(function (e) {
      status.className = "error";
      status.textContent = "Error: " + e.message;
    }).finally(function () { $("go").disabled = false; });
  });
})();
</script>
</body>
</html>
"""


if __name__ == "__main__":
    # Development server: python3 plamo-3-translate-server.py [port]
    import sys
    from wsgiref.simple_server import make_server

    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    with make_server("127.0.0.1", port, application) as httpd:
        print(f"Serving on http://127.0.0.1:{port}/ (llama-server: {LLAMA_URL})")
        httpd.serve_forever()
