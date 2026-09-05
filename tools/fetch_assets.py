#!/usr/bin/env python3
"""Install the downloadable Speed Dreams cars and tracks into the staged data.

The game data submodule ships one track and one car; everything else - 74 tracks
and 90 cars, about 3.4 GB - is published separately and fetched by the in-game
download manager. That manager cannot work in this port: libcurl is built without
TLS (see cmake/deps.cmake) and every asset URL is https. Downloading 3.4 GB
through the headset would be the slow way round in any case, so this does the same
job from the PC and the result goes over with the rest of the data.

It follows the manifest the game itself uses (config/downloadservers.xml ->
https://www.speed-dreams.net/assets.json) and lays the packages out the way
DownloadsMenu::extract does, including the .revision file, except that assets go
into the data tree rather than the user directory - so they survive deleting
.speed-dreams to reset settings, and tools/push-data.ps1 pushes them.

    python tools/fetch_assets.py                # everything
    python tools/fetch_assets.py --tracks       # only tracks
    python tools/fetch_assets.py --list         # what is available, and its size
    python tools/fetch_assets.py --only jarama,petit,nordschleife

Interrupted runs resume: an asset whose .revision already matches is skipped.
"""

import argparse
import concurrent.futures
import hashlib
import io
import json
import os
import shutil
import sys
import tempfile
import urllib.request
import zipfile

MANIFEST_URL = "https://www.speed-dreams.net/assets.json"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STAGE = os.path.join(ROOT, "stage", "SpeedDreamsVR", "data")
CACHE = os.path.join(ROOT, "stage", "assets-cache")
TIMEOUT = 120


def human(n):
    return "%.1f MB" % (n / 1e6) if n < 1e9 else "%.2f GB" % (n / 1e9)


def fetch(url, dest=None, retries=3):
    """Download to memory, or to dest with a .part file so a retry can restart."""
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "SpeedDreamsVR/1.0"})
            with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
                if dest is None:
                    return r.read()
                tmp = dest + ".part"
                with open(tmp, "wb") as f:
                    shutil.copyfileobj(r, f, 1 << 20)
                os.replace(tmp, dest)
                return None
        except Exception as e:                      # noqa: BLE001 - report and retry
            last = e
    raise RuntimeError("%s: %s" % (url, last))


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def dest_dir(asset, kind):
    """Where the game looks for this asset (Asset::path in the game's source)."""
    if kind == "cars":
        return os.path.join(STAGE, "cars", "models", asset["directory"])
    return os.path.join(STAGE, "tracks", asset["category"], asset["directory"])


def installed_revision(path):
    try:
        with open(os.path.join(path, ".revision")) as f:
            return f.read().strip()
    except OSError:
        return None


def install(asset, kind, force=False):
    """Returns a short status string for the log."""
    name = asset["directory"]
    dest = dest_dir(asset, kind)
    revision = str(asset.get("revision", "1"))

    if not force and installed_revision(dest) == revision:
        return "skip %s (revision %s already installed)" % (name, revision)

    os.makedirs(CACHE, exist_ok=True)
    cached = os.path.join(CACHE, asset["hash"] + ".zip")

    if not os.path.exists(cached) or sha256(cached) != asset["hash"]:
        fetch(asset["url"], cached)
        got = sha256(cached)
        if got != asset["hash"]:
            os.remove(cached)
            raise RuntimeError("%s: hash mismatch (expected %s, got %s)"
                               % (name, asset["hash"], got))

    # Extract beside the destination and swap it in, so an interrupted run never
    # leaves a half-written asset that a later run would skip as complete.
    parent = os.path.dirname(dest)
    os.makedirs(parent, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix=".tmp-" + name + "-", dir=parent)
    try:
        with zipfile.ZipFile(cached) as z:
            members = [m for m in z.namelist()
                       if m == name + "/" or m.startswith(name + "/")]
            if not members:
                raise RuntimeError("%s: no %s/ directory in the package" % (name, name))
            z.extractall(tmp, members)

        extracted = os.path.join(tmp, name)
        with open(os.path.join(extracted, ".revision"), "w") as f:
            f.write(revision + "\n")

        if os.path.exists(dest):
            shutil.rmtree(dest)
        os.replace(extracted, dest)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    return "ok   %s (%s, revision %s)" % (name, human(int(asset["size"])), revision)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tracks", action="store_true", help="only tracks")
    ap.add_argument("--cars", action="store_true", help="only cars")
    ap.add_argument("--only", help="comma separated directory names")
    ap.add_argument("--list", action="store_true", help="list what is available and exit")
    ap.add_argument("--force", action="store_true", help="reinstall even if up to date")
    ap.add_argument("--jobs", type=int, default=4, help="parallel downloads (default 4)")
    ap.add_argument("--keep-cache", action="store_true",
                    help="keep the downloaded zips in stage/assets-cache")
    args = ap.parse_args()

    kinds = []
    if args.tracks or not args.cars:
        kinds.append("tracks")
    if args.cars or not args.tracks:
        kinds.append("cars")

    print("manifest: %s" % MANIFEST_URL)
    manifest = json.loads(fetch(MANIFEST_URL).decode("utf-8"))

    wanted = None
    if args.only:
        wanted = {s.strip() for s in args.only.split(",") if s.strip()}

    jobs = []
    for kind in kinds:
        for asset in manifest.get(kind, []):
            if wanted is None or asset["directory"] in wanted:
                jobs.append((asset, kind))

    if wanted:
        missing = wanted - {a["directory"] for a, _ in jobs}
        for m in sorted(missing):
            print("not in the manifest: %s" % m, file=sys.stderr)

    total = sum(int(a["size"]) for a, _ in jobs)

    if args.list:
        for asset, kind in sorted(jobs, key=lambda j: (j[1], j[0]["directory"])):
            print("%-6s %-24s %-10s %9s  %s"
                  % (kind[:-1], asset["directory"], asset.get("category", ""),
                     human(int(asset["size"])), asset["name"]))
        print("\n%d assets, %s" % (len(jobs), human(total)))
        return 0

    if not os.path.isdir(STAGE):
        print("staged data missing: run python tools/stage_data.py first", file=sys.stderr)
        return 1

    print("%d assets, %s to download into %s" % (len(jobs), human(total), STAGE))

    failures = []
    done = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(install, a, k, args.force): (a, k) for a, k in jobs}
        for fut in concurrent.futures.as_completed(futures):
            asset, kind = futures[fut]
            done += 1
            try:
                print("[%3d/%3d] %s" % (done, len(jobs), fut.result()), flush=True)
            except Exception as e:                  # noqa: BLE001 - keep going
                failures.append((asset["directory"], e))
                print("[%3d/%3d] FAIL %s: %s" % (done, len(jobs), asset["directory"], e),
                      file=sys.stderr, flush=True)

    if not args.keep_cache and not failures:
        shutil.rmtree(CACHE, ignore_errors=True)

    if failures:
        print("\n%d failed; re-run to retry just those:" % len(failures), file=sys.stderr)
        for name, e in failures:
            print("  %s: %s" % (name, e), file=sys.stderr)
        return 1

    print("\nDone. Push it with tools\\push-data.ps1 -Full")
    return 0


if __name__ == "__main__":
    sys.exit(main())
