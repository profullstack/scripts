#!/usr/bin/env bash
# test/alert.sh: bin/alert against a fake smshub. No network, no real email:
# HOME is a temp dir whose ~/.local/bin/mail records what it was asked to send.
# Run by bin/scripts-check.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for t in python3 jq curl; do command -v "$t" >/dev/null || { echo "  alert test skipped: no $t"; exit 0; }; done

tmp=$(mktemp -d); trap 'kill "$srv" 2>/dev/null; rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home/.local/bin"
cat >"$tmp/home/.local/bin/mail" <<'M'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"$HOME/mail.out"
M
chmod +x "$tmp/home/.local/bin/mail"

# Fake smshub: key "good" is accepted, anything else gets smshub's real 401 body.
cat >"$tmp/srv.py" <<'P'
import http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def reply(self):
        ok = self.headers.get("X-API-Key") == "good"
        n = int(self.headers.get("Content-Length") or 0)
        if n: self.rfile.read(n)
        body = {"alert": {"channels": ["call"]}, "note": "calling", "alerts": []} if ok else {"error": "Invalid API key"}
        self.send_response(200 if ok else 401); self.end_headers(); self.wfile.write(json.dumps(body).encode())
    do_GET = do_POST = reply
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H); print(s.server_port, flush=True); s.serve_forever()
P
python3 -I "$tmp/srv.py" >"$tmp/port" & srv=$!
for _ in $(seq 50); do [ -s "$tmp/port" ] && break; sleep 0.1; done
export SMSHUB_URL="http://127.0.0.1:$(cat "$tmp/port")"

fails=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1" >&2; fails=1; }
run() { HOME="$tmp/home" SMSHUB_ALERT_API_KEY=$1 "$root/bin/alert" "${@:2}" >/dev/null 2>&1; }
mailed() { cat "$tmp/home/mail.out" 2>/dev/null; }

run good --key t1 "disk full" && [ ! -s "$tmp/home/mail.out" ] && ok "accepted key: sent, no email" || bad "accepted key"

run bad --key t2 "disk full"; rc=$?
[ $rc = 0 ] && mailed | grep -q 'smshub alert key REJECTED (HTTP 401)' && mailed | grep -q 'disk full' \
  && mailed | grep -q 'environment variable (not the vault)' \
  && ok "401: emailed, subject says key REJECTED, keeps the alert, names the key source" || bad "401 email: $(mailed)"
grep -q 'KEY REJECTED' "$tmp/home/.local/state/alert/alert.log" && ok "401: logged KEY REJECTED" || bad "401 log"

: >"$tmp/home/mail.out"
run bad --key t3 "second outage" && mailed | grep -q 'second outage' && ok "401 again: every real alert still emailed" || bad "401 second alert"

: >"$tmp/home/mail.out"; rm -f "$tmp/home/.local/state/alert/smshub-key-broken.last"
run bad --check; rc=$?
[ $rc = 1 ] && mailed | grep -q 'key REJECTED' && ok "--check on rejected key: exit 1 + email" || bad "--check rejected (rc $rc)"
: >"$tmp/home/mail.out"
run bad --check; [ ! -s "$tmp/home/mail.out" ] && ok "--check: one key email per 6h" || bad "--check repeated email"
run good --check && [ ! -f "$tmp/home/.local/state/alert/smshub-key-broken.last" ] && ok "--check on good key: exit 0, clears" || bad "--check good"


# Vault outage: the last key the vault gave is cached and used. No logicsrc in
# this HOME means "vault did not answer"; a fake logicsrc stands in for the vault.
: >"$tmp/home/mail.out"; rm -f "$tmp/home/.local/state/alert/"*.last
cat >"$tmp/home/.local/bin/logicsrc" <<'L'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do [ "$1" = -o ] && { printf 'team,project,env,category,key,value,updated_at\np,smshub,prod,,SMSHUB_ALERT_API_KEY,good,\n' >"$2"; }; shift; done
L
chmod +x "$tmp/home/.local/bin/logicsrc"
vrun() { HOME="$tmp/home" PATH="$tmp/home/.local/bin:$PATH" "$root/bin/alert" "$@" >/dev/null 2>&1; }
vrun --key v1 "vault up" && [ "$(stat -c %a "$tmp/home/.local/state/alert/smshub-key")" = 600 ] && ok "vault key used and cached 0600" || bad "vault key cache"
rm "$tmp/home/.local/bin/logicsrc"
vrun --key v2 "vault down" && [ ! -s "$tmp/home/mail.out" ] && grep -q 'using cached smshub key' "$tmp/home/.local/state/alert/alert.log" \
  && ok "vault down: cached key still calls, no email" || bad "vault down: $(mailed)"

exit $fails
