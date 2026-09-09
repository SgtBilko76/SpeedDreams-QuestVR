#!/bin/bash
# Build a self-contained dedicated-server package: copy it to a Linux box,
# untar, run. No compiler, no dependencies to install.
#
#   ./make-server-package.sh [prefix] [output dir]
#
# Run this on a machine whose glibc is no newer than the target's - glibc is
# backward compatible, not forward, so a package built on 26.04 will not start
# on 24.04. Build on the oldest release you intend to support.
#
# Everything the binaries need except the C library itself is bundled: SDL,
# plib, ENet, OpenAL, curl and, importantly, libGL and the X11 libraries. The
# server never opens a display, but tgfclient links them regardless and a
# headless VPS generally does not have them installed.

set -euo pipefail

PREFIX="${1:-$HOME/sdserver}"
OUT="${2:-$HOME/dist}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN="$PREFIX/games/speed-dreams-2"
[ -x "$BIN" ] || { echo "no server binary at $BIN" >&2; exit 1; }

. /etc/os-release 2>/dev/null || true
# awk rather than head: under pipefail a head that closes the pipe early kills
# the whole pipeline with SIGPIPE, and set -e takes the script with it.
GLIBC="$(ldd --version | awk 'NR==1 {print $NF}')"
NAME="speed-dreams-server-linux-x86_64"
STAGE="$OUT/$NAME"

echo "==> packaging from $PREFIX"
echo "    built on ${PRETTY_NAME:-unknown}, glibc $GLIBC"

rm -rf "$STAGE"
mkdir -p "$STAGE/lib/bundled"

cp -r "$PREFIX/games" "$STAGE/"
cp -r "$PREFIX/lib/games" "$STAGE/lib/"
cp -r "$PREFIX/share" "$STAGE/"

# --- bundle the shared libraries ---------------------------------------------
# Everything except the C library and its immediate companions: those must come
# from the host, or the dynamic loader and the libc it loads disagree.
SYSTEM='^(libc|libm|libdl|libpthread|librt|libresolv|ld-linux.*|libgcc_s)\.so'

echo "==> collecting libraries"
{
    ldd "$BIN"
    find "$PREFIX/lib" -name '*.so' -exec ldd {} \;
} 2>/dev/null | awk '/=>/ && $3 ~ /^\// {print $3}' | sort -u > /tmp/sdlibs.txt

n=0
while read -r lib; do
    base="$(basename "$lib")"
    echo "$base" | grep -qE "$SYSTEM" && continue
    real="$(readlink -f "$lib")"
    [ -f "$real" ] || continue
    cp -L "$real" "$STAGE/lib/bundled/$base" 2>/dev/null || continue
    n=$((n + 1))
done < /tmp/sdlibs.txt
echo "    bundled $n libraries"

# --- the settings template ---------------------------------------------------
# The game cannot lay these down itself: GfFileSetup gives up on the first entry
# of data/user-files, because config/logging.xml declares a DOCTYPE that only
# resolves inside a source checkout, so nothing after it gets installed either.
#
# Seeding from the data directory alone is not enough. A robot module's
# <module>.xml is only a cache, which GfDrivers::regen() rebuilds from the
# per-driver files at startup, and the shipped one is empty - a server started
# from that template has no robots at all and nothing to put on the grid. So run
# the game once here, let it generate them, and ship the result.
SEED="$STAGE/userdir-template"
SEEDHOME="$(mktemp -d)"
DATA="$PREFIX/share/games/speed-dreams-2"
mkdir -p "$SEED"

while read -r f; do
    f="${f%$'\r'}"                     # the data submodule is a Windows checkout
    [ -z "$f" ] && continue
    [ -f "$DATA/$f" ] || continue
    mkdir -p "$SEEDHOME/.speed-dreams-2/$(dirname "$f")"
    cp "$DATA/$f" "$SEEDHOME/.speed-dreams-2/$f"
done < "$DATA/user-files"
sed -i 's/val="osggraph"/val="ssggraph"/' "$SEEDHOME/.speed-dreams-2/config/raceengine.xml"

echo "==> generating the robot driver lists"
(
    cd "$PREFIX/games"
    LD_LIBRARY_PATH="$STAGE/lib/bundled:$PREFIX/lib/games/speed-dreams-2/lib" \
    HOME="$SEEDHOME" timeout 30 ./speed-dreams-2 -x -s netserver > /dev/null 2>&1 || true
)
cp -r "$SEEDHOME/.speed-dreams-2/." "$SEED/"
rm -rf "$SEEDHOME"

ROBOTS=$(ls "$SEED"/drivers/ 2>/dev/null | wc -l)
echo "    template carries $ROBOTS driver directories"

# --- the launcher ------------------------------------------------------------
cat > "$STAGE/speed-dreams-server" <<'LAUNCH'
#!/bin/bash
# Run the dedicated server from wherever this package was unpacked.
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

export LD_LIBRARY_PATH="$HERE/lib/bundled:$HERE/lib/games/speed-dreams-2/lib:${LD_LIBRARY_PATH:-}"
export SD_DATADIR="$HERE/share/games/speed-dreams-2"
export SD_USERDIR="${SD_USERDIR:-$HOME/.speed-dreams-2}"

# First run: lay down the settings, including the generated robot driver lists.
if [ ! -f "$SD_USERDIR/config/raceengine.xml" ] && [ -d "$HERE/userdir-template" ]; then
    echo "first run: seeding $SD_USERDIR"
    mkdir -p "$SD_USERDIR"
    cp -r "$HERE/userdir-template/." "$SD_USERDIR/"
fi

LAPS="${LAPS:-3}"
BOTS="${BOTS:-3}"
MINPLAYERS="${MINPLAYERS:-1}"
LOBBYWAIT="${LOBBYWAIT:-120}"

# Refuse to start if the port is already taken. Otherwise the new server exits
# immediately - activate() fails, main.cpp skips the event loop - while an older
# instance carries on serving from whatever race it was already running, which
# looks exactly like the new settings being ignored.
PORT="${PORT:-28500}"
if command -v ss >/dev/null && ss -lun 2>/dev/null | grep -q ":$PORT"; then
    echo "something is already listening on UDP $PORT." >&2
    echo "another server is probably still running; stop it first:" >&2
    echo "    pkill -f 'speed-dreams-2 -x -s netserver'" >&2
    exit 1
fi

# Pick the race before starting: the next track along unless told otherwise.
if [ -f "$HERE/configure-race.py" ] && command -v python3 >/dev/null; then
    if [ $# -gt 0 ]; then
        python3 "$HERE/configure-race.py" --laps "$LAPS" --bots "$BOTS" \
                --datadir "$SD_DATADIR" "$@"
    else
        python3 "$HERE/configure-race.py" --laps "$LAPS" --bots "$BOTS" --rotate \
                --datadir "$SD_DATADIR"
    fi
fi

cd "$HERE/games"
exec ./speed-dreams-2 -x -s netserver --minplayers "$MINPLAYERS" --lobbywait "$LOBBYWAIT"
LAUNCH
chmod +x "$STAGE/speed-dreams-server"

# --- the rest ----------------------------------------------------------------
cp "$HERE/configure-race.py" "$STAGE/"
cp "$HERE/speed-dreams-server.service" "$STAGE/" 2>/dev/null || true
chmod +x "$STAGE/configure-race.py"

TRACKS=$(find "$STAGE/share/games/speed-dreams-2/tracks" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | wc -l)

cat > "$STAGE/README.txt" <<EOF
Speed Dreams dedicated server
=============================

Built on ${PRETTY_NAME:-unknown} against glibc $GLIBC. glibc is backward
compatible but not forward, so this runs on that release or anything newer.

    ./speed-dreams-server

That is the whole thing. It seeds ~/.speed-dreams-2 on first run, picks the next
track in the rotation, and hosts one race on UDP 28500. Open that port.

    LAPS=5 BOTS=6 ./speed-dreams-server        # a longer race, bigger grid
    LOBBYWAIT=60 ./speed-dreams-server         # a shorter wait before the start
    ./speed-dreams-server --track jarama       # a specific track
    ./configure-race.py --list                 # what is installed

The lobby stays open for two minutes before every race, and clients see the
countdown. That gap is what lets a player who has just finished get back in
before the next race is under way; while a race is running the server turns
new players away rather than leaving them in a lobby it can no longer serve.

$TRACKS tracks are included and the server rotates through them one race at a
time. It exits when the race ends - run it under systemd with Restart=always and
each restart picks up the next track. speed-dreams-server.service is a starting
point; edit the paths in it.

Every library the server needs is in lib/bundled, including libGL and the X11
libraries. It never opens a display, but tgfclient links them anyway and a
headless machine usually does not have them.

Players join from the Quest build: Race -> Online Race -> Client -> Start Race,
with this machine's address in data/config/networking.xml on the headset.
EOF

# --- tar it ------------------------------------------------------------------
echo "==> compressing"
tar -C "$OUT" -czf "$OUT/$NAME.tar.gz" "$NAME"
echo "    $OUT/$NAME.tar.gz  ($(du -h "$OUT/$NAME.tar.gz" | cut -f1))"
