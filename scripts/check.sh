#!/usr/bin/env bash
# Health / version check for the WordPress 5.0.0 CVE-2019-8942 lab.
set -uo pipefail

BASE="${WP_URL:-http://localhost:18080}"
fail=0

pass() { printf '  [PASS] %s\n' "$1"; }
failmsg() { printf '  [FAIL] %s\n' "$1"; fail=1; }

echo "[*] Target: $BASE"

code="$(curl -fsS -o /dev/null -w '%{http_code}' "$BASE/" 2>/dev/null || true)"
if [ "$code" = "200" ]; then pass "WordPress is responding (HTTP 200)"; else failmsg "WordPress not reachable (HTTP ${code:-none})"; fi

code="$(curl -fsS -o /dev/null -w '%{http_code}' "$BASE/wp-login.php" 2>/dev/null || true)"
if [ "$code" = "200" ]; then pass "wp-login.php reachable"; else failmsg "wp-login.php unreachable"; fi

version="$(curl -fsS "$BASE/readme.html" 2>/dev/null | grep -oE 'Lab-Version: WordPress [0-9.]+' | head -1 || true)"
if [ -n "$version" ]; then pass "$version"; else failmsg "Could not read version marker from readme.html"; fi

theme="$(curl -fsS "$BASE/" 2>/dev/null | grep -oE '/wp-content/themes/[A-Za-z0-9_-]+/' | head -1 || true)"
if [ -n "$theme" ]; then pass "Active theme: $theme"; else failmsg "Could not detect active theme"; fi

if curl -fsS "$BASE/wp-content/debug.log" >/dev/null 2>&1; then
  pass "debug.log is publicly readable (intentional)"
else
  failmsg "debug.log not readable"
fi

code="$(curl -fsS -o /dev/null -w '%{http_code}' "$BASE/xmlrpc.php" 2>/dev/null || true)"
if [ "$code" = "405" ] || [ "$code" = "200" ]; then pass "XML-RPC enabled (HTTP $code)"; else failmsg "XML-RPC unexpected (HTTP ${code:-none})"; fi

if curl -fsS "$BASE/wp-json/wp/v2/users" 2>/dev/null | grep -q '"slug"'; then
  pass "REST user enumeration is available (intentional)"
else
  failmsg "REST user enumeration returned no users"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "[+] Lab looks healthy."
else
  echo "[-] One or more checks failed. Try: docker compose logs -f setup"
fi
exit "$fail"
