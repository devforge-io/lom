#!/bin/sh
# Letters of Marque — server installer
#
#   curl -fsSL https://raw.githubusercontent.com/devforge-io/lom/main/install.sh | sh
#
# Fetches the latest release from github.com/devforge-io/lom (or the one named
# in LOM_VERSION), verifies it, unpacks it under /opt/lom/<version>, points
# /opt/lom/current at it, and writes a `lom-server` command that runs it with
# the world in /var/lib/lom and settings from /etc/lom/lom.env.
#
# Every location can be overridden through the environment:
#
#   INSTALL_DIR  /opt/lom          the versioned trees and the `current` link
#   BIN_DIR      /usr/local/bin    where the `lom-server` command goes
#   CONFIG_DIR   /etc/lom          lom.env — AUTH_SECRET, BIND, ...
#   WORLD_DIR    /var/lib/lom      the durable world; survives upgrades
#   LOM_VERSION  latest            a tag, e.g. v0.0.2
#   GITHUB_TOKEN                   needed while the repository is private
set -eu

REPO="devforge-io/lom"
INSTALL_DIR="${INSTALL_DIR:-/opt/lom}"
BIN_DIR="${BIN_DIR:-/usr/local/bin}"
CONFIG_DIR="${CONFIG_DIR:-/etc/lom}"
WORLD_DIR="${WORLD_DIR:-/var/lib/lom}"

# ── Platform ─────────────────────────────────────────────────────────────────
# Only Linux x86-64 is built today. The names here are the names the release
# workflow gives its tarballs.
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
    Linux) OS="linux" ;;
    *)     echo "Error: no build for $OS yet — releases are Linux x86_64 only"; exit 1 ;;
esac
case "$ARCH" in
    x86_64|amd64) ARCH="x86_64" ;;
    *)            echo "Error: no build for $ARCH yet — releases are Linux x86_64 only"; exit 1 ;;
esac
TARGET="${LOM_TARGET:-${OS}-${ARCH}}"

# ── GitHub ───────────────────────────────────────────────────────────────────
# Through the API rather than the /releases/download/ URL: that URL is a
# redirect that a private repository refuses, and the API works for both.
api() {
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: $2" "$1"
    else
        curl -fsSL -H "Accept: $2" "$1"
    fi
}

if [ -n "${LOM_VERSION:-}" ]; then
    RELEASE_URL="https://api.github.com/repos/${REPO}/releases/tags/${LOM_VERSION}"
else
    RELEASE_URL="https://api.github.com/repos/${REPO}/releases/latest"
fi

echo "Fetching release..."
RELEASE="$(api "$RELEASE_URL" application/vnd.github+json)" || {
    echo "Error: could not read ${RELEASE_URL}"
    echo "If the repository is private, set GITHUB_TOKEN to a token that can read it."
    exit 1
}
TAG="$(printf '%s' "$RELEASE" | grep '"tag_name"' | head -1 | cut -d'"' -f4)"
if [ -z "$TAG" ]; then
    echo "Error: could not determine the release tag"
    exit 1
fi

ARCHIVE="lom-server-${TAG}-${TARGET}.tar.gz"
# The asset's API url, on the line after its name. Assets are listed as
# `"url": ..., "id": ..., "name": ...`, so the url PRECEDES the name; take
# the last url seen before the matching name.
asset_url() {
    printf '%s' "$RELEASE" | awk -v want="\"$1\"" '
        /"url":/ { url = $0; sub(/.*"url": *"/, "", url); sub(/".*/, "", url) }
        /"name":/ { name = $0; sub(/.*"name": *"/, "", name); sub(/".*/, "", name)
                    if ("\"" name "\"" == want) { print url; exit } }'
}
ARCHIVE_URL="$(asset_url "$ARCHIVE")"
SUM_URL="$(asset_url "${ARCHIVE}.sha256")"
if [ -z "$ARCHIVE_URL" ]; then
    echo "Error: release ${TAG} has no ${ARCHIVE}"
    exit 1
fi

# ── Download and verify ──────────────────────────────────────────────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading ${ARCHIVE}..."
api "$ARCHIVE_URL" application/octet-stream > "${TMP}/${ARCHIVE}"

if [ -n "$SUM_URL" ] && command -v sha256sum >/dev/null 2>&1; then
    api "$SUM_URL" application/octet-stream > "${TMP}/${ARCHIVE}.sha256"
    (cd "$TMP" && sha256sum -c "${ARCHIVE}.sha256" >/dev/null) || {
        echo "Error: ${ARCHIVE} does not match its checksum"
        exit 1
    }
    echo "Checksum verified."
fi

tar xzf "${TMP}/${ARCHIVE}" -C "$TMP"
SRC="${TMP}/lom-server-${TAG}-${TARGET}"
[ -x "${SRC}/pirates-server" ] || { echo "Error: the archive does not contain pirates-server"; exit 1; }

# ── Install ──────────────────────────────────────────────────────────────────
# With sudo where it is needed and not where it is not, so the same script
# works as root, as a user with sudo, and as a user installing under \$HOME
# with INSTALL_DIR/BIN_DIR/CONFIG_DIR/WORLD_DIR pointed there.
writable() {
    # Can we write at $1 — or, where it does not exist yet, at the nearest
    # ancestor that does?
    p="$1"
    while [ ! -e "$p" ]; do p="$(dirname "$p")"; done
    [ -w "$p" ]
}
as_needed() {
    # $1 = a path we must be able to write beneath; the rest is the command.
    target="$1"; shift
    if [ "$(id -u)" -eq 0 ] || writable "$target"; then
        "$@"
    else
        sudo "$@"
    fi
}

DEST="${INSTALL_DIR}/${TAG}"
echo "Installing to ${DEST}..."
as_needed "$INSTALL_DIR" mkdir -p "$INSTALL_DIR"
as_needed "$INSTALL_DIR" rm -rf "$DEST"
as_needed "$INSTALL_DIR" cp -R "$SRC" "$DEST"
as_needed "$INSTALL_DIR" ln -sfn "$DEST" "${INSTALL_DIR}/current"

as_needed "$WORLD_DIR" mkdir -p "$WORLD_DIR"
as_needed "$CONFIG_DIR" mkdir -p "$CONFIG_DIR"

# Settings, once. AUTH_SECRET signs every session and ticket; without one the
# server mints a random key at boot and every restart logs everybody out.
if [ ! -f "${CONFIG_DIR}/lom.env" ]; then
    echo "Writing ${CONFIG_DIR}/lom.env..."
    if command -v openssl >/dev/null 2>&1; then
        SECRET="$(openssl rand -hex 32)"
    else
        SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    fi
    cat > "${TMP}/lom.env" <<CONF
# Letters of Marque server — read by the lom-server command.
# Signs sessions and tickets. Generated at install; keep it, keep it secret.
AUTH_SECRET=${SECRET}
# Where the server listens. Plain http on this port; for https, set the
# two TLS lines and bind :443 — the server speaks TLS itself, no proxy.
BIND=0.0.0.0:1717
# TLS_CERT=/etc/letsencrypt/live/anvil.devforge.io/fullchain.pem
# TLS_KEY=/etc/letsencrypt/live/anvil.devforge.io/privkey.pem
# 1 in production. 0 accepts anonymous sockets, which is only for local dev.
REQUIRE_TICKET=1
# Log level and shape. LOG_FORMAT=json for a collector.
RUST_LOG=info
# Weather seed; change for a different climate.
# WEATHER_SEED=101189061838337
CONF
    as_needed "$CONFIG_DIR" install -m 600 "${TMP}/lom.env" "${CONFIG_DIR}/lom.env"
else
    echo "Config already exists at ${CONFIG_DIR}/lom.env, keeping it."
fi

# The command. Loads the settings, then runs whatever `current` points at.
cat > "${TMP}/lom-server" <<CMD
#!/bin/sh
# Letters of Marque server — installed by install.sh. Settings: ${CONFIG_DIR}/lom.env
set -a
[ -f "${CONFIG_DIR}/lom.env" ] && . "${CONFIG_DIR}/lom.env"
set +a
export WORLD_DIR="\${WORLD_DIR:-${WORLD_DIR}}"
exec "${INSTALL_DIR}/current/run.sh" "\$@"
CMD
as_needed "$BIN_DIR" mkdir -p "$BIN_DIR"
as_needed "$BIN_DIR" install -m 755 "${TMP}/lom-server" "${BIN_DIR}/lom-server"
as_needed "$BIN_DIR" ln -sfn "${INSTALL_DIR}/current/dbtool" "${BIN_DIR}/lom-dbtool"

echo ""
echo "Letters of Marque server ${TAG} installed."
echo ""
echo "  Command:   ${BIN_DIR}/lom-server   (and lom-dbtool)"
echo "  Release:   ${DEST}  ->  ${INSTALL_DIR}/current"
echo "  Settings:  ${CONFIG_DIR}/lom.env"
echo "  World:     ${WORLD_DIR}/"
echo ""
echo "Run 'lom-server' to start it on :1717."
