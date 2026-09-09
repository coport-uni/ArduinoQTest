"""Pre-check Tapo account credentials against specific plugs (LP §2).

Confirms the account authenticates and reports each plug's real alias
BEFORE the credentials are handed to Home Assistant's config flow, so a
failed HA flow is never ambiguous between "wrong password" and "flow
problem". Credentials come from TAPO_USER / TAPO_PASS so they are never
written to disk on the board.

Usage (from the repo root, with secure.env filled in):
  set -a; . ./secure.env; set +a
  ssh unoq "TAPO_USER='$TAPO_USER' TAPO_PASS='$TAPO_PASS' \
    /home/arduino/ha_venv/bin/python3 - 192.168.31.156" \
    < claude_test/kasa_auth_check.py
"""

import asyncio
import os
import sys

from kasa import Credentials, Discover


async def main():
    creds = Credentials(os.environ["TAPO_USER"], os.environ["TAPO_PASS"])
    failures = 0
    for ip in sys.argv[1:]:
        try:
            dev = await Discover.discover_single(ip, credentials=creds)
            await dev.update()
            print(
                f"{ip}  AUTH OK  alias={dev.alias!r} model={dev.model} "
                f"mac={dev.mac} is_on={dev.is_on}"
            )
        except Exception as e:
            failures += 1
            print(f"{ip}  AUTH FAIL  {type(e).__name__}: {e}")
    sys.exit(1 if failures else 0)


asyncio.run(main())
