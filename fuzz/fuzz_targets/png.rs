#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let _ = system76_firmware_update::image::bmp::parse(data);
});
