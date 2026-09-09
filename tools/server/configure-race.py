#!/usr/bin/env python3
"""Set up the dedicated server's race: track, laps, and a grid of bots.

The netserver raceman ships with an empty Drivers section - it assumes a human
is hosting from the menus and that their local drivers get converted into
network players. A dedicated server has no local humans, so the grid is empty
and the race engine refuses to start at all:

    Error   No competitor in this race : cancelled.

This fills the grid from the robots that are actually installed, reading their
names out of the per-module driver XMLs in the user directory. Each entry gets
both a "driver name" and an "idx": the race engine matches on the name and
rejects an entry without one, while the networking code keys on the index, and
two drivers from the same module are indistinguishable without it.

    ./configure-race.py --track jarama --laps 10 --bots 8

Run it after setup-linux-server.sh, and again whenever you want to change the
track or the field.
"""

import argparse
import os
import re
import sys
import xml.etree.ElementTree as ET

# Robot modules worth racing, best first. human/networkhuman are excluded: the
# first needs a keyboard, the second is the shell a connected player drives.
ROBOTS = ("simplix", "shadow", "usr", "axiom", "dandroid", "urbanski")


def userdir():
    return os.environ.get("SD_USERDIR", os.path.expanduser("~/.speed-dreams-2"))


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
                # The section name is the driver's index within its module, and
                # the networking code keys on that. Without it two drivers from
                # the same module are indistinguishable and collapse into one.
                try:
                    idx = int(driver.get("name"))
                except (TypeError, ValueError):
                    continue
                for attr in driver.findall("attstr"):
                    if attr.get("name") == "name" and attr.get("val"):
                        found.append((module, attr.get("val"), idx))
    return found


def xml_escape(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;")
             .replace(">", "&gt;").replace('"', "&quot;").replace("'", "&apos;"))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--track", default="jarama")
    ap.add_argument("--category", default="circuit")
    ap.add_argument("--laps", type=int, default=10)
    ap.add_argument("--bots", type=int, default=8,
                    help="grid size; capped at the number installed")
    ap.add_argument("--list", action="store_true", help="list the robots and exit")
    args = ap.parse_args()

    root = userdir()
    cfg = os.path.join(root, "config", "raceman", "netserver.xml")
    if not os.path.exists(cfg):
        print("no %s - run setup-linux-server.sh first" % cfg, file=sys.stderr)
        return 1

    bots = available_bots(root)
    if args.list:
        for module, name, idx in bots:
            print("%-10s idx %-3d %s" % (module, idx, name))
        print("\n%d robot drivers installed" % len(bots))
        return 0

    if not bots:
        print("no robot drivers found under %s/drivers" % root, file=sys.stderr)
        return 1

    grid = bots[:args.bots]
    if len(grid) < args.bots:
        print("only %d robots installed, grid will be %d"
              % (len(bots), len(grid)), file=sys.stderr)

    # Both attributes: the race engine matches a driver on "driver name" and
    # rejects an entry without one, while the networking code keys on "idx".
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
               r'\g<1>%s\g<2>' % args.track, s, count=1)
    s = re.sub(r'(<attstr name="category" val=")[^"]*(")',
               r'\g<1>%s\g<2>' % args.category, s, count=1)
    s = re.sub(r'(<attnum name="laps" val=")[^"]*(")',
               r'\g<1>%d\g<2>' % args.laps, s, count=1)

    with open(cfg, "w", encoding="utf-8") as f:
        f.write(s)

    print("track %s (%s), %d laps, %d bots:"
          % (args.track, args.category, args.laps, len(grid)))
    for module, name, idx in grid:
        print("  %-10s idx %-3d %s" % (module, idx, name))
    return 0


if __name__ == "__main__":
    sys.exit(main())
