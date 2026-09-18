#!/usr/bin/env bash
# monitor_failpath_test.sh — exercise the monitor's FAILURE branches.
#
# The faers-mobi seat's generalisation, 2026-09-18: "a branch that only executes
# when something is broken is a branch nobody has run." Five harness defects in
# this loop were all of that shape. The monitor's own failure handling is the
# same: `open a PR` ran once by luck (#75), `comment because the failing set
# changed` and `comment recovery` had never run at all until this script.
#
# It cannot use production — production is healthy, which is the point. So it
# serves BROKEN responses from a local HTTP server (GPS_MONITOR_BASE) and stubs
# `gh` and `git` on PATH, so no GitHub call is made and no branch is pushed. The
# stubs record what the monitor TRIED to do, and this asserts on that.
#
# Usage: bash scripts/monitor_failpath_test.sh

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"; [ -n "${SRV:-}" ] && kill "$SRV" 2>/dev/null' EXIT
STATE="$TMP/state"; LOG="$TMP/calls.log"; mkdir -p "$STATE" "$TMP/bin"

# --- a server that answers every path with a body we control -----------------
cat > "$TMP/srv.py" <<'PY'
import http.server, os, sys, threading, time
MODE = os.environ["MODE_FILE"]


def _die_with(owner):
    """Exit when the HARNESS dies.

    SIGKILL cannot be trapped, so the trap in this script never runs, and in
    broken-b mode this server PROXIES PRODUCTION -- an orphan is an open
    forwarder to faers.mobi that nobody owns. Measured 2026-09-18: killing the
    harness left exactly that.

    Watching getppid() is not enough: the server's parent is an intermediate
    shell that survives a kill of the harness, so getppid() never changes.
    Watch the harness PID itself, passed as argv[2].
    """
    while True:
        try:
            os.kill(owner, 0)
        except OSError:
            os._exit(0)
        time.sleep(1)


threading.Thread(target=_die_with, args=(int(sys.argv[2]),), daemon=True).start()
class H(http.server.BaseHTTPRequestHandler):
    def _mode(self): return open(MODE).read().strip()
    def do_GET(self):
        m = self._mode()
        if m == "healthy":
            # passes nothing: the point is to be BROKEN in a controlled way
            self.send_response(200); self.send_header("Content-Type","application/json")
            self.end_headers(); self.wfile.write(b'{"ok":true}')
        elif m == "broken-a":
            self.send_response(500); self.send_header("Content-Type","text/html")
            self.end_headers(); self.wfile.write(b"boom")
        else:
            # broken-b must change the failing SET, not just the bodies. Serving
            # junk everywhere fails all 33 checks in both modes, so the set is
            # identical and the "set changed" branch correctly does not fire --
            # the first version of this test asserted otherwise and was wrong.
            # So: proxy production, and break exactly one path.
            import urllib.request
            if self.path.startswith("/api"):
                self.send_response(500); self.send_header("Content-Type","text/html")
                self.end_headers(); self.wfile.write(b"boom"); return
            try:
                r = urllib.request.urlopen("https://faers.mobi" + self.path, timeout=30)
                body = r.read()
                self.send_response(r.status)
                self.send_header("Content-Type", r.headers.get("Content-Type","text/plain"))
                self.end_headers(); self.wfile.write(body)
            except urllib.error.HTTPError as e:
                body = e.read()
                self.send_response(e.code)
                self.send_header("Content-Type", e.headers.get("Content-Type","text/plain"))
                self.end_headers(); self.wfile.write(body)
    do_POST = do_GET
    def do_HEAD(self): self.do_GET()
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY

# --- stubs: record the call, never touch GitHub ------------------------------
cat > "$TMP/bin/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$LOG"
case "\$1 \$2" in
  "pr create")   echo "https://github.com/harlananelson/globalpatientsafety/pull/999" ;;
  "pr view")     echo "OPEN" ;;
  "pr comment")  : ;;
esac
exit 0
EOF
cat > "$TMP/bin/git" <<EOF
#!/usr/bin/env bash
echo "git \$*" >> "$LOG"
case "\$1" in
  # destination is the LAST argument, not \$4 -- \$4 is "1" from "--depth 1".
  # Assuming \$4 made the stub create a directory called "1", the cd failed, and
  # the test reported the MONITOR as broken. Sixth harness fault of this loop.
  clone) dest="\${@: -1}"; mkdir -p "\$dest/.git" "\$dest/issues" ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh" "$TMP/bin/git"

PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
echo broken-a > "$TMP/mode"
MODE_FILE="$TMP/mode" python3 "$TMP/srv.py" "$PORT" "$$" & SRV=$!   # $$ = this harness, the PID the server watches
for _ in $(seq 20); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.2; done

run() {
  env -i HOME="$HOME" PATH="$TMP/bin:/usr/bin:/bin" \
      GPS_MONITOR_DIR="$STATE" GPS_MONITOR_BASE="${BASE_OVERRIDE:-http://127.0.0.1:$PORT}" \
      GPS_MONITOR_RETRY_SLEEP=0 GPS_MONITOR_PACE=0 GPS_MONITOR_ALLOW_WRITES=1 \
      GPS_MONITOR_GH="$TMP/bin/gh" GPS_MONITOR_GIT="$TMP/bin/git" \
      bash "$HERE/monitor_faers_mobi.sh" >"$TMP/out.$1" 2>&1
  echo "  run $1 exit=$? : $(tail -1 "$TMP/out.$1" | cut -c1-80)"
}

pass=0; fail=0
want() { # want <description> <grep-pattern> <file>
  if grep -q -- "$2" "$3"; then echo "  PASS $1"; pass=$((pass+1)); else echo "  FAIL $1 (no /$2/ in $3)"; fail=$((fail+1)); fi
}
wantnot() {
  if grep -q -- "$2" "$3"; then echo "  FAIL $1 (unexpected /$2/)"; fail=$((fail+1)); else echo "  PASS $1"; pass=$((pass+1)); fi
}

echo "1. first failure -> opens ONE episode PR"
run 1
want "filed a PR" "gh pr create" "$LOG"
want "recorded the episode" "999" "$STATE/episode-pr"
want "wrote the spec file" "git add issues/monitor-alert-" "$LOG"

echo "2. same failing set again -> NO second PR, NO comment"
: > "$LOG"; run 2
wantnot "did not file a second PR" "gh pr create" "$LOG"
wantnot "did not re-comment an unchanged set" "gh pr comment" "$LOG"

echo "3. DIFFERENT failing set (proxy production, break only /api) -> comments on the SAME PR"
echo broken-b > "$TMP/mode"; : > "$LOG"; run 3
want "commented the change" "gh pr comment 999" "$LOG"
wantnot "still no second PR" "gh pr create" "$LOG"

echo "4. recovery -> comments recovery and clears the episode"
# production, so every check passes; gh/git still stubbed via GPS_MONITOR_GH/GIT
BASE_OVERRIDE="https://faers.mobi"
# Run against PRODUCTION so every check passes -- but keep the gh/git stubs, and
# assert on the stub log. Run 4 previously used the real gh (see #87).
: > "$LOG"; GPS_MONITOR_PACE=0.3 run 4
want "commented recovery" "gh pr comment 999" "$LOG"
if [ -f "$STATE/episode-pr" ]; then echo "  FAIL episode not cleared"; fail=$((fail+1)); else echo "  PASS episode cleared"; pass=$((pass+1)); fi

echo
echo "pass $pass  fail $fail"
[ "$fail" = 0 ]
