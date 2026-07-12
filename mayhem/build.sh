#!/usr/bin/env bash
#
# mayhem/build.sh — build the firmware-update `png` fuzz target (BMP parser) as a
# sanitized libFuzzer binary, plus the clean functional oracle for mayhem/test.sh.
#
# Runs inside the commit image (RUST mayhem/Dockerfile) as `mayhem` in /mayhem.
# The Rust toolchain + cargo registry live at $CARGO_HOME=/opt/toolchains/rust/cargo
# (pinned by the Dockerfile ENV — absolute, $HOME-independent).
#
# The upstream crate is a no_std/no_main UEFI binary, so we do NOT build it. We build
# two ADDITIVE crates under mayhem/ that INCLUDE the real upstream `image` module
# verbatim via #[path] (no copy, no upstream edits):
#   mayhem/fuzz    -> cargo-fuzz `png` target (sanitized)  -> /mayhem/png   (Mayhem target)
#   mayhem/oracle  -> clean `bmp_oracle` known-answer tool -> /mayhem/bmp_oracle (test.sh)
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE. The
# first (online) build populates $CARGO_HOME; the re-run resolves from that cache
# with CARGO_NET_OFFLINE=true supplied by the runtime — so do NOT hard-code --offline.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

# OSS-Fuzz Rust libFuzzer+ASan flags, honoring the image contracts:
#  - SANITIZER_FLAGS (C/C++ contract): for Rust the ASan member maps to -Zsanitizer=address
#    (UBSan is a C/C++ sanitizer; Rust's safe subset covers UB, so address is the Rust set).
#  - RUST_DEBUG_FLAGS (debug-info contract): .debug_info present + DWARF < 4 on every target.
# --cfg fuzzing matches libfuzzer-sys; force-frame-pointers aids ASan backtraces.
SAN=""
case "${SANITIZER_FLAGS:-address}" in *address*) SAN="-Zsanitizer=address" ;; esac
: "${RUST_DEBUG_FLAGS:=-Cdebuginfo=2 -Zdwarf-version=3}"
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing ${SAN} ${RUST_DEBUG_FLAGS} -Cforce-frame-pointers"
# The libFuzzer C++ runtime inside libfuzzer-sys is built by the cc crate with the
# host clang; force DWARF-3 there too so no DWARF-5 CUs leak into the target binary.
export CFLAGS="${CFLAGS:-} -gdwarf-3"
export CXXFLAGS="${CXXFLAGS:-} -gdwarf-3"

# Rust's prebuilt ASan runtime (librustc-nightly_rt.asan.a) ships DWARF-5 debug info
# and is linked FIRST, which would fail the DWARF < 4 contract. Strip its debug
# sections once (idempotent; the stripped .a is baked into the image, so the offline
# re-run sees the same file).
ASAN_RT="$(find "$RUSTUP_HOME/toolchains" -name 'librustc-nightly_rt.asan.a' 2>/dev/null | head -1)"
if [ -n "$ASAN_RT" ] && [ -f "$ASAN_RT" ]; then
  echo "Stripping debug info from Rust ASan runtime (DWARF < 4 contract): $ASAN_RT"
  objcopy --strip-debug "$ASAN_RT"
fi

FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

echo "=== cargo fuzz build (image nightly, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  # --build-std rebuilds the Rust std lib with the same RUSTFLAGS (sanitized +
  # DWARF-3) instead of linking the prebuilt DWARF-4 std — required for the
  # debug-info contract AND gives ASan coverage inside std. link-dead-code=off
  # (overriding cargo-fuzz's default) avoids a rustc ICE compiling core with
  # link-dead-code + build-std on this nightly.
  RUSTFLAGS="$RUSTFLAGS -Clink-dead-code=off" \
    cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions --build-std "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Clean (NON-sanitized) functional oracle so mayhem/test.sh is an honest known-answer
# oracle. Uses the same pinned toolchain/registry; no sanitizer flags.
echo "=== cargo build oracle (clean, no sanitizer) ==="
RUSTFLAGS="" cargo build --release --manifest-path mayhem/oracle/Cargo.toml
cp "$SRC/mayhem/oracle/target/release/bmp_oracle" "/mayhem/bmp_oracle"
echo "built /mayhem/bmp_oracle"

echo "build.sh complete"
