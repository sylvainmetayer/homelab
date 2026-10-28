#!/usr/bin/env python3
"""Stand-in for `beszel superuser upsert EMAIL PASSWORD`, for the beszel
Molecule scenario (beszel_superuser_command): records the superuser where
beszel_api_mock.py reads it, and counts the calls for verify.yml."""

import json
import os
import sys

DIRECTORY = "/var/lib/beszel-superuser-mock"
SUPERUSERS_JSON = os.path.join(DIRECTORY, "superusers.json")
CALLS = os.path.join(DIRECTORY, "calls")


def main(argv):
    if len(argv) != 3 or argv[0] != "upsert":
        print("usage: beszel-superuser-mock upsert EMAIL PASSWORD", file=sys.stderr)
        return 2
    _, email, password = argv
    os.umask(0o077)
    try:
        with open(SUPERUSERS_JSON, encoding="utf-8") as f:
            superusers = json.load(f)
    except FileNotFoundError:
        superusers = {}
    superusers[email] = password
    with open(SUPERUSERS_JSON, "w", encoding="utf-8") as f:
        json.dump(superusers, f)
    with open(CALLS, "a", encoding="utf-8") as f:
        f.write(email + "\n")
    print(f"Successfully saved superuser {email}!")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
