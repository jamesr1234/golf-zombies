"""Add a batch of bottle codes and write the QR web addresses for the printer.

    python3 make_codes.py --count 50000 --batch spring-2027 --out spring-2027.csv

Uses the same LEADERBOARD_DB as the server, so run it on the droplet. Each row
of the CSV is one bottle: the code and the full address its QR should open.
"""

import argparse
import csv
import os
from pathlib import Path

from store import Store

HERE = Path(__file__).resolve().parent
PUBLIC_URL = os.environ.get("LEADERBOARD_PUBLIC_URL", "https://golfis.8bev.ca")


def write_batch(store, count, batch, out_path, public_url=PUBLIC_URL):
    codes = store.add_codes(count, batch)
    with open(out_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["code", "url"])
        for code in codes:
            writer.writerow([code, "%s/?c=%s" % (public_url.rstrip("/"), code)])
    return codes


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--count", type=int, required=True)
    parser.add_argument("--batch", required=True, help="a name for this print run")
    parser.add_argument("--out", required=True, help="CSV file to write")
    args = parser.parse_args()
    if args.count < 1:
        parser.error("--count must be at least 1")
    store = Store(os.environ.get("LEADERBOARD_DB", str(HERE / "leaderboard.db")))
    codes = write_batch(store, args.count, args.batch, args.out)
    print("added %d codes to batch %s, wrote %s" % (len(codes), args.batch, args.out))


if __name__ == "__main__":
    main()
