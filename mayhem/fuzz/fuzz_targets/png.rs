#![no_main]
//! In-process libFuzzer harness over the REAL upstream BMP parser.
//!
//! The upstream project is a `no_std`/`no_main` UEFI binary, so its parser can't be
//! reached through the normal crate root on a host build. Instead of copying code
//! (which would drift from upstream), we INCLUDE the exact upstream source module
//! verbatim via `#[path]`: `src/image/mod.rs` (+ its `pub mod bmp;` sibling
//! `src/image/bmp.rs`). This compiles the genuine `image::bmp::parse` code path —
//! the same function the original `png` target fuzzed — fully ASan-instrumented.
//!
//! Target name is kept `png` for parity with the archived original integration,
//! though it drives `image::bmp::parse` (the original harness did the same).
use libfuzzer_sys::fuzz_target;

// `src/image/mod.rs` is a `mod.rs`, so its `pub mod bmp;` resolves to the sibling
// `src/image/bmp.rs` automatically — the whole real module tree compiles here.
#[path = "../../../src/image/mod.rs"]
mod image;

fuzz_target!(|data: &[u8]| {
    let _ = image::bmp::parse(data);
});
