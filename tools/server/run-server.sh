#!/bin/bash
# Run the Speed Dreams dedicated server.
#
#   ./run-server.sh [prefix] [-- extra speed-dreams args]
#
# The server listens on UDP 28500 (config/networking.xml, or --port), waits in
# the lobby until --minplayers players have connected and all of them are ready,
# runs the race, and then exits. Exiting is deliberate: a long-lived process
# looping back to the lobby has to survive a full module reload between races,
# and the track, physics and robot modules keep static state across that. Let
# systemd restart it instead - see speed-dreams-server.service.

set -euo pipefail

PREFIX="${1:-$HOME/sdserver}"
shift || true
[ "${1:-}" = "--" ] && shift || true

BIN="$PREFIX/games/speed-dreams-2"
[ -x "$BIN" ] || { echo "no server binary at $BIN - run setup-linux-server.sh" >&2; exit 1; }

cd "$(dirname "$BIN")"
exec ./speed-dreams-2 -x -s netserver "$@"
