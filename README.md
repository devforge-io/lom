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

Listens on `0.0.0.0:1717`. Put a TLS-terminating reverse proxy in front for
`https://` and `wss://` — the server speaks plain HTTP and WebSocket — and
point the client at that origin at build time (`VITE_SERVER_URL`).

As a service, a unit like this does:

```ini
# /etc/systemd/system/lom-server.service
[Unit]
Description=Letters of Marque server
After=network-online.target

[Service]
ExecStart=/usr/local/bin/lom-server
Restart=on-failure
User=lom
# The world and the settings must be readable by this user.

[Install]
WantedBy=multi-user.target
```

## Upgrade

Run the installer again. The new version lands beside the old under
`/opt/lom/`, `current` moves to it, and `lom.env` and the world are left
exactly as they were. Roll back by pointing `current` at the previous
directory.

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
