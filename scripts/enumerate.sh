#!/bin/bash
# WordPress enumeration script

TARGET=${1:-http://192.168.4.36:18180}

echo "[*] Enumerating WordPress at $TARGET"
echo

echo "[+] Checking WordPress version:"
curl -s "$TARGET/readme.html" | grep -i "version\|Lab-Version" | head -2
echo

echo "[+] Checking debug.log:"
curl -s "$TARGET/wp-content/debug.log" | head -3
echo

echo "[+] Checking XML-RPC:"
curl -s -o /dev/null -w "HTTP: %{http_code}\n" "$TARGET/xmlrpc.php"
echo

echo "[+] Checking users via REST API:"
curl -s "$TARGET/wp-json/wp/v2/users" 2>&1 | head -c 200
echo
echo

echo "[+] Checking login page for X-Frame-Options:"
curl -sI "$TARGET/wp-login.php" | grep -i x-frame-options || echo "X-Frame-Options: NOT SET"
echo
