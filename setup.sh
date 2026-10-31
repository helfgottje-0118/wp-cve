#!/bin/sh
set -e

URL="${WP_URL:-http://192.168.4.36:18180}"
ADMIN_USER="${WP_ADMIN_USER:-admin}"
ADMIN_PASS="${WP_ADMIN_PASS:-AdminPass123!}"
ADMIN_EMAIL="${WP_ADMIN_EMAIL:-admin@lab.local}"
AUTHOR_USER="${WP_AUTHOR_USER:-author}"
AUTHOR_PASS="${WP_AUTHOR_PASS:-AuthorPass123!}"
AUTHOR_EMAIL="${WP_AUTHOR_EMAIL:-author@lab.local}"

echo "[setup] waiting for WordPress files..."
for i in $(seq 1 60); do
  [ -f /var/www/html/wp-includes/version.php ] && break
  sleep 2
done

echo "[setup] waiting for database..."
for i in $(seq 1 60); do
  wp db check >/dev/null 2>&1 && break
  sleep 2
done

if ! wp core is-installed >/dev/null 2>&1; then
  echo "[setup] installing WordPress..."
  wp core install --url="$URL" --title="WP 5.0.0 CVE-2019-8942 Lab" \
    --admin_user="$ADMIN_USER" --admin_password="$ADMIN_PASS" \
    --admin_email="$ADMIN_EMAIL" --skip-email
fi

wp option update home "$URL" >/dev/null
wp option update siteurl "$URL" >/dev/null

if ! wp user get "$AUTHOR_USER" >/dev/null 2>&1; then
  echo "[setup] creating author user..."
  wp user create "$AUTHOR_USER" "$AUTHOR_EMAIL" --role=author --user_pass="$AUTHOR_PASS"
fi

AUTHOR_ID=$(wp user get "$AUTHOR_USER" --field=ID 2>/dev/null || true)
if [ -n "$AUTHOR_ID" ] && ! wp post list --post_type=post --author="$AUTHOR_ID" --format=ids 2>/dev/null | grep -q .; then
  echo "[setup] creating an author-owned post for REST enumeration..."
  wp post create --post_type=post --post_status=publish --post_title='Author Post' \
    --post_author="$AUTHOR_ID" --post_content='Author post for REST enumeration.' >/dev/null
fi

echo "[setup] enabling XML-RPC, pingbacks, open comments, and a ping target..."
wp option update default_ping_status open >/dev/null
wp option update default_pingback_flag 1 >/dev/null
wp option update default_comment_status open >/dev/null
wp option update blog_public 1 >/dev/null
wp post update 1 --ping_status=open >/dev/null 2>&1 || true

echo "[setup] writing lab mu-plugin (clickjacking + XML-RPC/private-IP)..."
mkdir -p /var/www/html/wp-content/mu-plugins
cat > /var/www/html/wp-content/mu-plugins/lab-config.php <<'PHP'
<?php
/*
Plugin Name: Lab Config
Description: Intentionally weakens headers and XML-RPC for the CVE-2019-8942 lab.
*/

// Clickjacking: remove WordPress's X-Frame-Options header on admin/login.
remove_action( 'admin_init', 'send_frame_options_header' );
remove_action( 'login_init', 'send_frame_options_header' );

// XML-RPC/pingback: keep enabled and allow it to reach private lab addresses.
add_filter( 'xmlrpc_enabled', '__return_true' );
add_filter( 'http_request_host_is_external', '__return_true' );

// Reveal real pingback errors (useful while testing the lab).
remove_filter( 'xmlrpc_pingback_error', 'xmlrpc_pingback_error' );

// Note: WordPress 5.0 only accepts pingback sources on ports 80/443/8080,
// so the pingback helper in this lab runs on 8080.
PHP

echo "[setup] adding readme version marker..."
WP_VERSION="$(wp core version)"
if ! grep -q 'Lab-Version:' /var/www/html/readme.html; then
  sed -i "s#</body>#<p>Lab-Version: WordPress ${WP_VERSION}</p>\n</body>#" /var/www/html/readme.html
fi

echo "[setup] ensuring public debug.log..."
touch /var/www/html/wp-content/debug.log
chmod 644 /var/www/html/wp-content/debug.log
if ! grep -q 'Lab debug log is publicly readable' /var/www/html/wp-content/debug.log 2>/dev/null; then
  echo "[$(date '+%d-%b-%Y %H:%M:%S')] PHP Notice:  Lab debug log is publicly readable at /wp-content/debug.log" >> /var/www/html/wp-content/debug.log
fi

echo "[setup] done. WordPress version: $(wp core version)"
