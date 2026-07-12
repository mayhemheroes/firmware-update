#!/usr/bin/env bash
#
# mayhem/test.sh — functional oracle for the upstream BMP parser (image::bmp::parse).
#
# UPSTREAM SUITE: system76/firmware-update ships NO usable test suite — there are no
# `#[test]`/`#[cfg(test)]` items, no `tests/` dir, and no `make check`/`cargo test`
# target (the crate is a no_std/no_main UEFI binary that can't `cargo test` on a
# host). So this is an AUTHORED behavioral known-answer oracle (tests_found=0).
#
# It RUNS the prebuilt clean oracle (/mayhem/bmp_oracle from build.sh), which parses
# hand-crafted BMP byte streams with the GENUINE upstream parser (included verbatim
# via #[path]) and prints one `RESULT <name> <value>` line per case. We assert each
# printed value against a hand-computed golden. A patch that breaks parsing changes a
# value; a parser neutered to exit(0) prints nothing -> every case fails (behavioral,
# not reward-hackable).
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "${SRC:-/mayhem}"

BIN=/mayhem/bmp_oracle

# case name -> golden expected value (see mayhem/oracle/src/main.rs for the derivation)
declare -A GOLDEN=(
  [sig_bad]="err:BMP: invalid signature"
  [empty]="err:BMP: invalid signature"
  [valid1x1]="ok:1x1:FF302010"
  [valid2x2]="ok:2x2:FF998877,FFCCBBAA,FF332211,FF665544"
)

passed=0; failed=0
declare -A GOT=()

if [ -x "$BIN" ]; then
  while read -r _tag name value; do
    [ "$_tag" = "RESULT" ] || continue
    GOT["$name"]="$value"
  done < <("$BIN" 2>/dev/null)
fi

check() { if [ "$2" -eq 0 ]; then echo "  ok   - $1"; passed=$((passed+1)); else echo "  FAIL - $1"; failed=$((failed+1)); fi; }

for name in sig_bad empty valid1x1 valid2x2; do
  want="${GOLDEN[$name]}"
  got="${GOT[$name]:-<missing>}"
  if [ "$got" = "$want" ]; then
    check "bmp::parse $name => $want" 0
  else
    echo "        expected: $want"
    echo "        got:      $got"
    check "bmp::parse $name => $want" 1
  fi
done

emit_ctrf() {
  local tool="$1" p="$2" f="$3" s="${4:-0}"; local tests=$(( p + f + s ))
  cat > "${CTRF_REPORT:-${SRC:-/mayhem}/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": { "tests": $tests, "passed": $p, "failed": $f, "pending": 0, "skipped": $s, "other": 0 }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":0,"skipped":%d,"other":0}}}\n' \
    "$tool" "$tests" "$p" "$f" "$s"
  [ "$f" -eq 0 ]
}

echo "test.sh: passed=$passed failed=$failed"
emit_ctrf firmware-update "$passed" "$failed"
