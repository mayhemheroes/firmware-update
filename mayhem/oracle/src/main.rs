//! Known-answer oracle for the upstream BMP parser (`image::bmp::parse`).
//!
//! Upstream ships NO test suite (no `#[test]`/`#[cfg(test)]`, no `tests/`, no
//! `make check`), so this is an AUTHORED behavioral oracle (tests_found=0). It
//! includes the EXACT upstream `image` module verbatim via `#[path]` (no copy),
//! builds a handful of hand-crafted BMP byte streams whose parse results are known
//! by construction, and prints one `RESULT <name> <value>` line per case. The
//! assertions live in mayhem/test.sh, which compares each printed value to a
//! hand-computed golden. If the parser is neutered (e.g. a sabotage `exit(0)`),
//! this binary prints nothing and test.sh fails — so the oracle is behavioral,
//! not exit-code-based.

use orbclient::Renderer; // brings Image::width()/height() into scope

// Same verbatim include as the fuzz target — the genuine upstream code path.
#[path = "../../../src/image/mod.rs"]
mod image;

/// Build a 24bpp, uncompressed BITMAPINFOHEADER BMP header (54 bytes), pixel data
/// starts at offset 54.
fn header(width: u32, height: u32) -> Vec<u8> {
    let mut b = vec![0u8; 54];
    b[0] = b'B';
    b[1] = b'M';
    b[10] = 54; // pixel data offset (LE u32)
    b[14] = 40; // DIB header size
    b[18..22].copy_from_slice(&width.to_le_bytes());
    b[22..26].copy_from_slice(&height.to_le_bytes());
    b[26] = 1; // planes
    b[28] = 24; // bits per pixel
                // offset 30 (compression) left 0 => BI_RGB, default channel masks
    b
}

fn emit(name: &str, data: &[u8]) {
    match image::bmp::parse(data) {
        Ok(img) => {
            let w = img.width();
            let h = img.height();
            let px = img.into_data();
            let hexes: Vec<String> = px.iter().map(|c| format!("{:08X}", c.data)).collect();
            println!("RESULT {} ok:{}x{}:{}", name, w, h, hexes.join(","));
        }
        Err(e) => println!("RESULT {} err:{}", name, e),
    }
}

fn main() {
    // Non-BMP inputs must be rejected with the exact upstream error message.
    emit("sig_bad", b"ZZ");
    emit("empty", b"");

    // 1x1 24bpp: single pixel B=0x10 G=0x20 R=0x30 => Color::rgb(0x30,0x20,0x10)=0xFF302010.
    let mut v = header(1, 1);
    v.extend_from_slice(&[0x10, 0x20, 0x30, 0x00]);
    emit("valid1x1", &v);

    // 2x2 24bpp: BMP rows are bottom-up. Bottom row at offset 54, top row at 62
    // (row stride = 8 bytes). Pixels (as stored, BGR):
    //   off54: 11 22 33  (bottom-left)   off57: 44 55 66  (bottom-right)
    //   off62: 77 88 99  (top-left)      off65: AA BB CC  (top-right)
    // parse emits top-to-bottom, left-to-right:
    //   top-left  = getd(62) -> R99 G88 B77 -> FF998877
    //   top-right = getd(65) -> RCC GBB BAA -> FFCCBBAA
    //   bot-left  = getd(54) -> R33 G22 B11 -> FF332211
    //   bot-right = getd(57) -> R66 G55 B44 -> FF665544
    let mut v = header(2, 2);
    let mut px = vec![0u8; 16];
    px[0] = 0x11;
    px[1] = 0x22;
    px[2] = 0x33;
    px[3] = 0x44;
    px[4] = 0x55;
    px[5] = 0x66;
    px[8] = 0x77;
    px[9] = 0x88;
    px[10] = 0x99;
    px[11] = 0xAA;
    px[12] = 0xBB;
    px[13] = 0xCC;
    v.extend_from_slice(&px);
    emit("valid2x2", &v);
}
