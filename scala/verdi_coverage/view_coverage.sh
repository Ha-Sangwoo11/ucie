#!/bin/bash
# Open a coverage database in the Verdi coverage GUI (needs X11/DISPLAY).
#
#   ./view_coverage.sh              # global merged.vdb (trend number only — the
#                                   # cross-design merge drops non-matching modules)
#   ./view_coverage.sh <Suite>      # ACCURATE per-suite DB, e.g.
#                                   #   ./view_coverage.sh SidebandSwitchTest
#
# Extra args after the suite name are passed through to verdi.
cd "$(dirname "$0")"

if [ $# -ge 1 ] && [ "${1#-}" = "$1" ]; then
  DB="suites/$1.vdb"
  shift
  if [ ! -d "$DB" ]; then
    echo "ERROR: $DB not found. Available suites:"
    ls suites 2>/dev/null | sed 's/\.vdb$//; s/^/  /' || echo "  (none — run ./run_verdi_coverage.sh first)"
    exit 1
  fi
else
  DB="merged.vdb"
  if [ ! -d "$DB" ]; then
    echo "ERROR: merged.vdb not found — run ./run_verdi_coverage.sh first"
    exit 1
  fi
fi

exec verdi -cov -covdir "$DB" "$@"
