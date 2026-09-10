#!/bin/bash
# Run the Speed Dreams dedicated server for one race.
#
#   ./run-server.sh                       # next track in the rotation
#   ./run-server.sh --track jarama        # a specific one
#   LAPS=5 BOTS=6 ./run-server.sh
#
# The server listens on UDP 28500 (config/networking.xml, or --port), holds the
# lobby open for LOBBYWAIT seconds, races, and then does it again on the next
# track. ONCE=1 stops after one race.

set -euo pipefail

PREFIX="${PREFIX:-$HOME/sdserver}"
LAPS="${LAPS:-3}"
BOTS="${BOTS:-3}"
MINPLAYERS="${MINPLAYERS:-1}"
LOBBYWAIT="${LOBBYWAIT:-120}"
MAXRACETIME="${MAXRACETIME:-0}"
FINISHWAIT="${FINISHWAIT:-45}"

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

BIN="$PREFIX/games/speed-dreams-2"
[ -x "$BIN" ] || { echo "no server binary at $BIN - run setup-linux-server.sh" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGURE="$HERE/configure-race.py"

# Race after race, each one a fresh process.
#
# The track, physics and robot modules all keep static state across a reload,
# so a long-lived process looping back to the lobby carries the last race into
# the next one - this port has already produced several bugs in exactly that
# territory. Starting again is the only way to be sure, and because the race is
# configured out here rather than in the binary, each turn of this loop picks up
# the next track in the rotation.
#
# ONCE=1 runs a single race and stops: use that under systemd with
# Restart=always if you would rather it supervised the loop.
races=0
quick=0

while true; do
    # Anything passed through goes to configure-race.py, so --track/--modules
    # work; with nothing, take the next track along.
    if [ -f "$CONFIGURE" ]; then
        if [ $# -gt 0 ]; then
            python3 "$CONFIGURE" --laps "$LAPS" --bots "$BOTS" \
                    --datadir "$PREFIX/share/games/speed-dreams-2" "$@" || true
        else
            python3 "$CONFIGURE" --laps "$LAPS" --bots "$BOTS" --rotate \
                    --datadir "$PREFIX/share/games/speed-dreams-2" || true
        fi
    else
        echo "configure-race.py not beside this script; racing whatever is configured" >&2
    fi

    races=$((races + 1))
    echo "== race $races =="
    started=$SECONDS

    cd "$(dirname "$BIN")"
    ./speed-dreams-2 -x -s netserver --minplayers "$MINPLAYERS" \
                     --lobbywait "$LOBBYWAIT" \
                     --maxracetime "$MAXRACETIME" \
                     --finishdelay "$FINISHWAIT" || true

    # Not "[ ... ] && break": under set -e a test that is false is a failed
    # command at statement level, and the loop would exit on the first race.
    if [ "${ONCE:-0}" = "1" ]; then
        break
    fi

    # A race that was over in seconds did not run at all. Looping on that as
    # fast as the kernel allows helps nobody.
    if [ $((SECONDS - started)) -lt 10 ]; then
        quick=$((quick + 1))
        if [ "$quick" -ge 5 ]; then
            echo "five races ended at once; stopping. Look at the log above." >&2
            exit 1
        fi
        sleep 5
    else
        quick=0
    fi

    # Let the socket go before the next one asks for it.
    sleep 2
done
