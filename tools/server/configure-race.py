#!/usr/bin/env python3
"""Set up the dedicated server's next race: track, laps, and a grid of bots.

The netserver raceman ships with an empty Drivers section - it assumes a human
is hosting from the menus and that their local drivers become the network
players. A dedicated server has no local humans, so the grid is empty and the
race engine refuses to start at all:

    Error   No competitor in this race : cancelled.

This fills the grid from the robots that are actually installed, reading their
names out of the per-module driver XMLs. Each entry gets both a "driver name"
and an "idx": the race engine matches on the name and rejects an entry without
one, while the networking code keys on the index, and two drivers from the same
module are indistinguishable without it.

    ./configure-race.py --laps 3 --bots 4          # a specific race
    ./configure-race.py --laps 3 --bots 4 --rotate # the next track along
    ./configure-race.py --list                     # what is installed

--rotate advances through the installed tracks one race at a time, taking the
position from the track the race config is already set to. run-server.sh calls
it that way before every race, so a server restarted by systemd works its way
round the calendar instead of sitting on one circuit forever.
"""

import argparse
import os
import re
import sys
import xml.etree.ElementTree as ET

# Robot modules worth racing, best first. human/networkhuman are excluded: the
# first needs a keyboard, the second is the shell a connected player drives.
ROBOTS = ("simplix", "shadow", "usr", "axiom", "dandroid", "urbanski")

ROTATION_STATE = ".track-rotation"


def userdir():
    return os.environ.get("SD_USERDIR", os.path.expanduser("~/.speed-dreams-2"))


def datadir(explicit):
    """Where the installed tracks live."""
    if explicit:
        return explicit
    env = os.environ.get("SD_DATADIR")
    if env:
        return env
    for prefix in (os.path.expanduser("~/sdserver"), os.path.expanduser("~/sdinstall")):
        d = os.path.join(prefix, "share", "games", "speed-dreams-2")
        if os.path.isdir(os.path.join(d, "tracks")):
            return d
    return ""


def installed_tracks(data):
    """[(category, track)] for every usable track, sorted."""
    found = []
    root = os.path.join(data, "tracks")
    if not os.path.isdir(root):
        return found

    for category in sorted(os.listdir(root)):
        cdir = os.path.join(root, category)
        if not os.path.isdir(cdir) or category == "categories":
            continue
        for track in sorted(os.listdir(cdir)):
            tdir = os.path.join(cdir, track)
            if not os.path.isdir(tdir):
                continue
            if not os.path.exists(os.path.join(tdir, track + ".xml")):
                continue
            # A track with no 3D model is listed by the game but unusable, and a
            # client that cannot load one drops straight out of the race.
            if not any(f.endswith((".ac", ".acc")) for f in os.listdir(tdir)):
                continue
            found.append((category, track))
    return found


def available_bots(root):
    """[(module, driver name, index)] for every installed robot driver."""
    found = []
    for module in ROBOTS:
        path = os.path.join(root, "drivers", module, module + ".xml")
        if not os.path.exists(path):
            continue
        try:
            tree = ET.parse(path).getroot()
        except ET.ParseError as e:
            print("  skipping %s: %s" % (module, e), file=sys.stderr)
            continue
        for section in tree.iter("section"):
            if section.get("name") != "index":
                continue
            for driver in section.findall("section"):
                try:
                    idx = int(driver.get("name"))
                except (TypeError, ValueError):
                    continue
                for attr in driver.findall("attstr"):
                    if attr.get("name") == "name" and attr.get("val"):
                        found.append((module, attr.get("val"), idx))
    return found


def current_track(cfg):
    """The track the race config is set to right now, as (category, name)."""
    try:
        with open(cfg, encoding="utf-8") as f:
            s = f.read()
    except OSError:
        return None

    name = re.search(r'<section name="1">\s*<attstr name="name" val="([^"]*)"', s)
    category = re.search(r'<attstr name="category" val="([^"]*)"', s)

    if not name or not category:
        return None

    return (category.group(1), name.group(1))


def next_track(tracks, root, cfg):
    """The track after the one that is configured now, wrapping round.

    Taken from the race config itself rather than from a state file beside it.
    The config has to be writable for any of this to work at all, so reading the
    position back out of it cannot fail separately - whereas a state file can,
    and does: under systemd with ProtectHome the user directory is read-only
    unless it is named in ReadWritePaths, and a rotation that cannot record
    where it got to starts from the first track every single time. Silently,
    which is the worst of it - the server just looks like it is ignoring
    --rotate.

    The state file is still written, for anyone who reads it, but nothing
    depends on it any more.
    """
    names = ["%s/%s" % (c, t) for c, t in tracks]
    last = current_track(cfg)
    last = "%s/%s" % last if last else ""

    try:
        i = (names.index(last) + 1) % len(names)
    except ValueError:
        i = 0

    print("rotation: %s -> %s" % (last or "(unknown)", names[i]))

    state = os.path.join(root, ROTATION_STATE)
    try:
        with open(state, "w") as f:
            f.write(names[i] + "\n")
    except OSError as e:
        print("could not record the rotation position: %s" % e, file=sys.stderr)

    return tracks[i]


def xml_escape(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;")
             .replace(">", "&gt;").replace('"', "&quot;").replace("'", "&apos;"))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--track", help="track name; its category is looked up")
    ap.add_argument("--rotate", action="store_true",
                    help="use the track after the one used last time")
    ap.add_argument("--laps", type=int, default=3)
    ap.add_argument("--bots", type=int, default=4,
                    help="grid size; capped at the number installed")
    ap.add_argument("--modules",
                    help="comma separated robot modules to draw the grid from. "
                         "The server sends every robot's driver file to clients, "
                         "so they do not need the same robots installed")
    ap.add_argument("--datadir", help="the installed data directory")
    ap.add_argument("--list", action="store_true",
                    help="list the installed tracks and robots, then exit")
    args = ap.parse_args()

    root = userdir()
    data = datadir(args.datadir)
    cfg = os.path.join(root, "config", "raceman", "netserver.xml")

    tracks = installed_tracks(data)
    bots = available_bots(root)

    if args.list:
        print("tracks in %s:" % (data or "(not found)"))
        for category, track in tracks:
            print("  %-10s %s" % (category, track))
        print("\nrobots:")
        for module, name, idx in bots:
            print("  %-10s idx %-3d %s" % (module, idx, name))
        print("\n%d track(s), %d robot driver(s)" % (len(tracks), len(bots)))
        return 0

    if not os.path.exists(cfg):
        print("no %s - run setup-linux-server.sh first" % cfg, file=sys.stderr)
        return 1
    if not tracks:
        print("no usable tracks under %s" % (data or "(not found)"), file=sys.stderr)
        return 1

    if args.modules:
        wanted = set(m.strip() for m in args.modules.split(",") if m.strip())
        bots = [b for b in bots if b[0] in wanted]
    if not bots:
        print("no robot drivers found under %s/drivers" % root, file=sys.stderr)
        return 1

    if args.rotate:
        category, track = next_track(tracks, root, cfg)
    elif args.track:
        match = [(c, t) for c, t in tracks if t == args.track]
        if not match:
            print("track '%s' is not installed; --list shows what is"
                  % args.track, file=sys.stderr)
            return 1
        category, track = match[0]
    else:
        category, track = tracks[0]

    grid = bots[:args.bots]
    if len(grid) < args.bots:
        print("only %d robot driver(s) installed, grid will be %d"
              % (len(bots), len(grid)), file=sys.stderr)

    rows = "".join(
        '    <section name="%d">\n'
        '      <attstr name="driver name" val="%s"/>\n'
        '      <attnum name="idx" val="%d"/>\n'
        '      <attstr name="module" val="%s"/>\n'
        '    </section>\n\n' % (i + 1, xml_escape(name), idx, module)
        for i, (module, name, idx) in enumerate(grid))

    drivers = ('  <section name="Drivers">\n'
               '    <attnum name="maximum number" val="40"/>\n'
               '    <attstr name="focused module" val="human"/>\n\n'
               + rows + '  </section>\n')

    with open(cfg, encoding="utf-8") as f:
        s = f.read()

    s, n = re.subn(r'  <section name="Drivers">.*?\n  </section>\n',
                   drivers, s, count=1, flags=re.S)
    if not n:
        print("could not find the Drivers section in %s" % cfg, file=sys.stderr)
        return 1

    s = re.sub(r'(<section name="1">\s*<attstr name="name" val=")[^"]*(")',
               r'\g<1>%s\g<2>' % track, s, count=1)
    s = re.sub(r'(<attstr name="category" val=")[^"]*(")',
               r'\g<1>%s\g<2>' % category, s, count=1)
    s = re.sub(r'(<attnum name="laps" val=")[^"]*(")',
               r'\g<1>%d\g<2>' % args.laps, s, count=1)

    with open(cfg, "w", encoding="utf-8") as f:
        f.write(s)

    print("%s (%s), %d laps, %d bots:" % (track, category, args.laps, len(grid)))
    for module, name, idx in grid:
        print("  %-10s idx %-3d %s" % (module, idx, name))
    return 0


if __name__ == "__main__":
    sys.exit(main())
