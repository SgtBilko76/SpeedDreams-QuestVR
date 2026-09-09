#!/bin/bash
# Run the Speed Dreams dedicated server for one race.
#
#   ./run-server.sh                       # next track in the rotation
#   ./run-server.sh --track jarama        # a specific one
#   LAPS=5 BOTS=6 ./run-server.sh
#
# The server listens on UDP 28500 (config/networking.xml, or --port), waits in
# the lobby until MINPLAYERS players have connected and all of them are ready,
# runs the race, and exits.
#
# Exiting is deliberate. A long-lived process looping back to the lobby has to
# survive a full module reload between races, and the track, physics and robot
# modules all keep static state across that - this port has already produced
# several bugs in exactly that territory. systemd restarts it instead, and
# because the race is configured here rather than in the binary, each restart
# picks up the next track in the rotation. See speed-dreams-server.service.

set -euo pipefail

PREFIX="${PREFIX:-$HOME/sdserver}"
LAPS="${LAPS:-3}"
BOTS="${BOTS:-4}"
MINPLAYERS="${MINPLAYERS:-1}"

BIN="$PREFIX/games/speed-dreams-2"
[ -x "$BIN" ] || { echo "no server binary at $BIN - run setup-linux-server.sh" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGURE="$HERE/configure-race.py"

# Pick the race. Anything passed through goes to configure-race.py, so
# --track/--modules work; with nothing, take the next track along.
if [ -x "$CONFIGURE" ] || [ -f "$CONFIGURE" ]; then
    if [ $# -gt 0 ]; then
        python3 "$CONFIGURE" --laps "$LAPS" --bots "$BOTS" \
                --datadir "$PREFIX/share/games/speed-dreams-2" "$@"
    else
        python3 "$CONFIGURE" --laps "$LAPS" --bots "$BOTS" --rotate \
                --datadir "$PREFIX/share/games/speed-dreams-2"
    fi
else
    echo "configure-race.py not beside this script; racing whatever is configured" >&2
fi

cd "$(dirname "$BIN")"
exec ./speed-dreams-2 -x -s netserver --minplayers "$MINPLAYERS"
