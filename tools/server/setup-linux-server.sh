#!/bin/bash
# Build and prepare a headless Speed Dreams dedicated server on Linux.
#
# Verified on Ubuntu 26.04 (cmake 4.2, g++ 15) against the quest-port branch.
# It builds the game, installs it to a prefix, and prepares a user directory the
# server can actually race from - which takes more than "make install", for the
# reasons in the comments below.
#
#   ./setup-linux-server.sh /path/to/speed-dreams-code [prefix]
#
# Then run the server with run-server.sh.

set -euo pipefail

SRC="${1:?usage: setup-linux-server.sh <speed-dreams-code checkout> [prefix]}"
PREFIX="${2:-$HOME/sdserver}"
BUILD="${BUILD:-$HOME/sdbuild}"
JOBS="$(nproc)"

echo "==> source  $SRC"
echo "==> prefix  $PREFIX"
echo "==> build   $BUILD"

# --- dependencies ------------------------------------------------------------
# libplib-dev is the one that is usually missing; it is still in the Ubuntu
# repos. cJSON, minizip and rhash are required by simplix and the download
# manager respectively, and the configure step fails hard without them.
if command -v apt-get >/dev/null; then
    echo "==> installing dependencies"
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
        build-essential cmake pkg-config \
        libsdl2-dev libsdl2-mixer-dev libsdl2-ttf-dev \
        libpng-dev libjpeg-dev zlib1g-dev \
        libopenal-dev libenet-dev libexpat1-dev libcurl4-openssl-dev \
        libplib-dev libvorbis-dev libogg-dev \
        libcjson-dev libminizip-dev libglm-dev librhash-dev \
        libgl1-mesa-dev libglu1-mesa-dev libxrandr-dev libxxf86vm-dev \
        libxrender-dev libxi-dev
fi

# --- build -------------------------------------------------------------------
# The server needs no graphics, but tgfclient links GL and SDL regardless, so
# the -dev packages have to be present even though no display is ever opened.
# OSG is off because nothing headless uses it and it is a large dependency.
mkdir -p "$BUILD"
cd "$BUILD"
cmake "$SRC" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DOPTION_OSGGRAPH=OFF \
    -DOPTION_CLIENT_SERVER=ON
cmake --build . -j "$JOBS"
cmake --install .

# --- user directory ----------------------------------------------------------
# GfFileSetup() is supposed to copy everything listed in data/user-files into
# ~/.speed-dreams-2 on first run. It aborts on the very first entry:
# config/logging.xml declares a DOCTYPE of "../../src/libs/tgf/params.dtd",
# a path that only exists in a source checkout, so GfParmReadFile fails, the
# loop stops, and nothing after it is installed either. The visible symptom is
# a segfault (no raceengine.xml means the track loader module name falls back to
# the code default "track" instead of "trackv1", and the null loader is not
# checked), or "Driver not found" (no human preferences means the human modules
# fail to initialise). Seed it here instead.
DATA="$PREFIX/share/games/speed-dreams-2"
USERDIR="${SD_USERDIR:-$HOME/.speed-dreams-2}"

echo "==> seeding $USERDIR"
seeded=0
while read -r f; do
    f="${f%$'\r'}"                      # the data submodule is a Windows checkout
    [ -z "$f" ] && continue
    [ -f "$DATA/$f" ] || continue
    mkdir -p "$USERDIR/$(dirname "$f")"
    if [ ! -f "$USERDIR/$f" ]; then
        cp "$DATA/$f" "$USERDIR/$f"
        seeded=$((seeded + 1))
    fi
done < "$DATA/user-files"
echo "    seeded $seeded files"

# The shipped raceengine.xml asks for osggraph, which is not built here. The
# server loads no graphics module at all, but the name still has to resolve.
sed -i 's/val="osggraph"/val="ssggraph"/' "$USERDIR/config/raceengine.xml"

echo
echo "Done. Build: $PREFIX/games/speed-dreams-2"
echo "Next: tools/server/run-server.sh"
