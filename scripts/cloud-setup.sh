#!/bin/bash
# Garden Route Ultra - cloud environment setup script.
#
# Paste this into the Setup script field of the grt-tracker cloud environment at
# claude.ai/code. It runs as root on Ubuntu 24.04, before Claude Code launches,
# once per cache build (roughly every seven days, or whenever this script or the
# network allowlist changes).
#
# Dependencies ONLY. The filesystem is snapshotted after this runs, so anything
# secret written here would persist in that snapshot and go stale the moment the
# Garmin token is rotated. scripts/sync_garmin.py materialises the token at
# runtime from the GARMIN_TOKENS environment variable instead, which is correct
# on both counts.
#
# Ubuntu 24.04 marks its Python as externally managed (PEP 668), so a plain
# `pip install` is refused. --break-system-packages is the supported way through
# on a throwaway VM; the fallbacks cover images where it is not needed.

set -u

pip install --quiet --break-system-packages garminconnect 2>/dev/null \
  || pip install --quiet garminconnect 2>/dev/null \
  || pip3 install --quiet --break-system-packages garminconnect 2>/dev/null \
  || true

if python3 -c "import garminconnect, garth" 2>/dev/null; then
  echo "OK    garminconnect and garth importable"
else
  echo "WARN  garminconnect did not install - the routine will report and stop"
fi

# Never exit non-zero: a failing setup script stops the session from starting at
# all, which is a worse failure than a routine that reports it cannot sync.
exit 0
