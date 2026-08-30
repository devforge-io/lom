# Letters of Marque

Release downloads for the Letters of Marque server. Source lives in
`devforge-io/lom-server`; every tag there publishes a release here with the
built binaries, the `data/` catalogues they were built against, and a `run.sh`.

## Install

Linux x86-64. Fetches the latest release, verifies its checksum, and installs
it system-wide (it asks for `sudo` where it needs it):

```bash
curl -fsSL https://raw.githubusercontent.com/devforge-io/lom/main/install.sh | sh
```

While this repository is private, both the script and the release need a
token that can read it:

```bash
export GITHUB_TOKEN=github_pat_…
curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://raw.githubusercontent.com/devforge-io/lom/main/install.sh | sh
```

What it puts where:

| | Path | |
|---|---|---|
| Command | `/usr/local/bin/lom-server` | starts the server; `lom-dbtool` beside it |
| Release | `/opt/lom/<version>/` | binaries + `data/`; `/opt/lom/current` points at the one in use |
| Settings | `/etc/lom/lom.env` | `AUTH_SECRET` (generated), `BIND`, `REQUIRE_TICKET`, `RUST_LOG` |
| World | `/var/lib/lom/` | accounts, captains, gold, ports — survives upgrades |

A specific version: `LOM_VERSION=v0.0.2 sh install.sh`. Somewhere other than
the defaults, without root:

```bash
INSTALL_DIR=$HOME/lom BIN_DIR=$HOME/bin CONFIG_DIR=$HOME/lom/etc WORLD_DIR=$HOME/lom/world sh install.sh
```

## Run

```bash
lom-server
```

Listens on `0.0.0.0:1717`, plain http. That is right on a laptop and wrong
on a server: the client is served over https, and a browser will not let an
https page call `http://` or open `ws://`.

### HTTPS

The server speaks TLS itself — no proxy — when `lom.env` names a certificate
and key. With Let's Encrypt, on a host whose DNS name points at it:

```bash
sudo apt install certbot
sudo certbot certonly --standalone -d lom-api.devforge.io    # port 80 must be free and open
```

Then in `/etc/lom/lom.env`:

```bash
BIND=0.0.0.0:443
TLS_CERT=/etc/letsencrypt/live/lom-api.devforge.io/fullchain.pem
TLS_KEY=/etc/letsencrypt/live/lom-api.devforge.io/privkey.pem
```

and let the `lom` user read them (`sudo chgrp -R lom /etc/letsencrypt/live
/etc/letsencrypt/archive && sudo chmod -R g+rX /etc/letsencrypt/live
/etc/letsencrypt/archive`). The server re-reads the files once a day, so
certbot's automatic renewal needs no restart. Port 443 is privileged: the
unit below grants it with `AmbientCapabilities`; running by hand, use a high
port or `sudo`.

`https://lom-api.devforge.io/health` should then answer `ok`, and the client
is built with `VITE_SERVER_URL=https://lom-api.devforge.io` (the socket
derives to `wss://…/ws`).

### As a service (systemd)

Run it under its own user, started at boot and restarted if it dies.

1. A user to run as, owning the world and able to read the settings:

   ```bash
   sudo useradd --system --home /var/lib/lom --shell /usr/sbin/nologin lom
   sudo chown -R lom:lom /var/lib/lom
   sudo chgrp lom /etc/lom/lom.env && sudo chmod 640 /etc/lom/lom.env
   ```

2. The unit:

   ```bash
   sudo tee /etc/systemd/system/lom-server.service >/dev/null <<'EOF'
   [Unit]
   Description=Letters of Marque server
   After=network-online.target
   Wants=network-online.target

   [Service]
   User=lom
   Group=lom
   ExecStart=/usr/local/bin/lom-server
   Restart=on-failure
   RestartSec=5
   # Lets an unprivileged user bind :443 for HTTPS.
   AmbientCapabilities=CAP_NET_BIND_SERVICE
   # Give a region time to checkpoint on the way down.
   TimeoutStopSec=30
   # The world is the only thing it writes.
   ReadWritePaths=/var/lib/lom
   ProtectSystem=strict
   ProtectHome=true
   NoNewPrivileges=true

   [Install]
   WantedBy=multi-user.target
   EOF
   ```

3. Load it, start it, and have it start at boot:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now lom-server
   ```

Then:

```bash
systemctl status lom-server          # is it up
journalctl -u lom-server -f          # its log, live
curl -fsS http://127.0.0.1:1717/health
sudo systemctl restart lom-server    # after an upgrade or a change to lom.env
sudo systemctl disable --now lom-server   # stop it and take it off startup
```

`RUST_LOG`, `BIND` and the rest still come from `/etc/lom/lom.env` — the
`lom-server` command loads it, so the unit needs no `Environment=` lines.

## Upgrade

Run the installer again. The new version lands beside the old under
`/opt/lom/`, `current` moves to it, and `lom.env` and the world are left
exactly as they were. Roll back by pointing `current` at the previous
directory. Either way, `sudo systemctl restart lom-server` picks it up —
the running process keeps the old binary until then.

## Uninstall

```bash
sudo rm -rf /opt/lom /usr/local/bin/lom-server /usr/local/bin/lom-dbtool
sudo rm -rf /etc/lom          # settings — the AUTH_SECRET with them
sudo rm -rf /var/lib/lom      # THE WORLD. Every account and every captain.
```

## Manual

Each release's tarball unpacks to a directory with `pirates-server`,
`dbtool`, `data/` and a `run.sh` that starts the server from wherever it is,
with the world in `./world`:

```bash
tar xzf lom-server-v0.0.2-linux-x86_64.tar.gz
AUTH_SECRET=… ./lom-server-v0.0.2-linux-x86_64/run.sh
```
