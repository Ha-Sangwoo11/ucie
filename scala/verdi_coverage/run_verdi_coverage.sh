#!/bin/bash
# VCS coverage run + merge for ucie tests. Lives in scala/verdi_coverage/;
# all merged outputs stay in this directory.
#
# Usage:
#   ./run_verdi_coverage.sh                                            # full suite
#   ./run_verdi_coverage.sh --clean                                    # clean and run full suite
#   ./run_verdi_coverage.sh edu.berkeley.cs.uciedigital.logphy.UcieLFSRTest ...
#                                                                      # specific suites
#   ./run_verdi_coverage.sh --merge-only                               # just re-merge existing vdbs
#
# Per-test coverage DBs land in build/chiselsim/<Test>/<scenario>/workdir-vcs/simulation.vdb
# (fixed by ChiselSim). The merge stage produces, in this directory:
#   suites/<Suite>.vdb    <- ACCURATE per-suite merged DB (open these in Verdi)
#   reports/<Suite>/      <- per-suite urg report (all modules, line-annotated source
#                            in modinfo.txt / mod*.html)
#   modules_summary.txt   <- per-module scores of every suite, in one file
#   area_summary.txt      <- per-subsystem map: every RTL module, tested or not
#   merged.vdb, urgReport <- global all-suite merge: single trend number ONLY.
#                            Each suite elaborates a DIFFERENT design under the same
#                            top name (svsimTestbench/dut), so urg's cross-design
#                            merge silently drops non-matching module definitions.
#                            For per-module / per-line analysis use suites/ and
#                            reports/, never the global DB.
#
# View:  ./view_coverage.sh <Suite>    (no arg: global merged.vdb)

set -u
COV_DIR="$(cd "$(dirname "$0")" && pwd)"
# guard: COV_DIR feeds rm -rf paths below — never proceed with an empty value
[ -n "$COV_DIR" ] || { echo "ERROR: cannot resolve script directory"; exit 1; }
SCALA_DIR="$(dirname "$COV_DIR")"
cd "$SCALA_DIR" || exit 1

if [ "${1:-}" = "--clean" ]; then
  shift
  echo "Cleaning build/chiselsim and previous coverage outputs"
  rm -rf build/chiselsim
  # also drop every generated output, so nothing stale survives an aborted run
  rm -rf "$COV_DIR/suites" "$COV_DIR/reports" "$COV_DIR/merged.vdb" "$COV_DIR/urgReport" \
         "$COV_DIR/modules_summary.txt" "$COV_DIR/area_summary.txt"
fi

# svsim invokes $VCS_HOME/bin/vcs directly (PATH is rebuilt by mill's test fork,
# so PATH tricks don't survive). The shim VCS_HOME interposes a vcs wrapper that
# restores the real VCS_HOME and puts a C++17-capable g++ (conda gcc-15, -no-pie)
# ahead of system g++ 4.8 for VCS csrc builds. Machine-specific; skipped elsewhere.
if [ -d /home/sangwoo/tools/vcs-home-shim ]; then
  export VCS_HOME=/home/sangwoo/tools/vcs-home-shim
fi

if [ "${1:-}" != "--merge-only" ]; then
  # --no-daemon: the mill daemon caches its startup environment, so
  # UCIE_SIM_BACKEND only reliably reaches the forked test JVM without it.
  if [ $# -gt 0 ]; then
    UCIE_SIM_BACKEND=vcs ./mill --no-daemon test.testOnly "$@" \
      || echo "WARN: some tests failed (continuing to merge coverage)"
  else
    UCIE_SIM_BACKEND=vcs ./mill --no-daemon test \
      || echo "WARN: some tests failed (continuing to merge coverage)"
  fi
fi

if [ ! -d build/chiselsim ]; then
  echo "ERROR: build/chiselsim not found — did the VCS run produce coverage?"
  exit 1
fi

# --- Stage 1: accurate per-suite merges + reports ----------------------------
rm -rf "$COV_DIR/suites" "$COV_DIR/reports"
mkdir -p "$COV_DIR/suites" "$COV_DIR/reports"
TOTAL=0
SUITES=()
for sd in build/chiselsim/*/; do
  s=$(basename "$sd")
  URG_ARGS=()
  n=0
  while IFS= read -r v; do
    URG_ARGS+=(-dir "$SCALA_DIR/$v")
    n=$((n + 1))
  done < <(find "$sd" -type d -name simulation.vdb 2>/dev/null | sort)
  [ "$n" -eq 0 ] && continue
  TOTAL=$((TOTAL + n))
  SUITES+=("$s")
  echo "[$s] merging $n vdbs"
  # urg mishandles -dbname paths containing directories (it collapses them to
  # the parent name), so run from suites/ with a plain db name instead.
  ( cd "$COV_DIR/suites" \
    && urg -full64 "${URG_ARGS[@]}" -dbname "$s" \
        -report "$COV_DIR/reports/$s" -format both > /dev/null ) \
    || echo "WARN: urg failed for suite $s"
done

if [ "$TOTAL" -eq 0 ]; then
  echo "ERROR: no simulation.vdb found under build/chiselsim — did the VCS run produce coverage?"
  exit 1
fi

# --- Combined per-module summary across all suites ---------------------------
{
  echo "Per-suite module coverage (accurate; generated $(date '+%Y-%m-%d %H:%M'))"
  echo "(each section carries its own column header; ASSERT column appears only where assertions exist)"
  for s in "${SUITES[@]}"; do
    echo
    echo "===== $s ====="
    # module table of the suite report, without the leading blurb
    awk '/^-{10,}/{on=1; next} on' "$COV_DIR/reports/$s/modlist.txt" 2>/dev/null
  done
} > "$COV_DIR/modules_summary.txt"

# --- Area verification map (per-subsystem tested/untested module table) ------
"$COV_DIR/area_summary.sh" > /dev/null 2>&1 \
  && echo "area map    -> $COV_DIR/area_summary.txt" \
  || echo "WARN: area_summary.sh failed"

# --- Stage 2: global merge (trend number only — see header caveat) -----------
URG_ARGS=()
while IFS= read -r v; do URG_ARGS+=(-dir "$SCALA_DIR/$v"); done \
  < <(find build/chiselsim -type d -name simulation.vdb 2>/dev/null | sort)
echo "[global] merging $TOTAL vdbs (trend number only)"
( cd "$COV_DIR" \
  && urg -full64 "${URG_ARGS[@]}" -dbname merged -report urgReport -format both > /dev/null ) \
  || echo "WARN: global urg merge failed"

echo ""
echo "Done. Outputs in $COV_DIR:"
echo "  reports/<Suite>/dashboard.txt|.html   per-suite coverage (accurate)"
echo "  modules_summary.txt                   all suites' module scores in one file"
echo "  area_summary.txt                      per-subsystem tested/untested module map"
echo "  ./view_coverage.sh <Suite>            Verdi GUI on an accurate suite DB"
echo "  ./view_coverage.sh                    Verdi GUI on the global merged DB (trend only)"
