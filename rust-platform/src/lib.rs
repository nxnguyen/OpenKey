#![no_std]

use core::ffi::{c_char, c_void, CStr};
use core::panic::PanicInfo;

type CFTypeRef = *const c_void;
type CFIndex = isize;
type Boolean = u8;

#[link(name = "Carbon", kind = "framework")]
extern "C" {
    fn TISCopyCurrentKeyboardInputSource() -> CFTypeRef;
    fn TISGetInputSourceProperty(input_source: CFTypeRef, property: CFTypeRef) -> CFTypeRef;
    static kTISPropertyInputSourceLanguages: CFTypeRef;

    fn CFArrayGetCount(array: CFTypeRef) -> CFIndex;
    fn CFArrayGetValueAtIndex(array: CFTypeRef, index: CFIndex) -> CFTypeRef;
    fn CFStringGetCString(
        string: CFTypeRef,
        buffer: *mut c_char,
        buffer_size: CFIndex,
        encoding: u32,
    ) -> Boolean;
    fn CFRelease(value: CFTypeRef);
}

#[link(name = "System")]
extern "C" {
    fn abort() -> !;
}

#[panic_handler]
fn rust_panic(_info: &PanicInfo) -> ! {
    unsafe { abort() }
}

struct OwnedCf(CFTypeRef);

impl Drop for OwnedCf {
    fn drop(&mut self) {
        unsafe { CFRelease(self.0) };
    }
}

/// Returns 1 for English, 0 for another language, and -1 if macOS cannot
/// provide a language. The caller fails open for the last case.
#[no_mangle]
pub extern "C" fn openkey_current_input_source_is_english() -> i32 {
    unsafe {
        let input_source = TISCopyCurrentKeyboardInputSource();
        if input_source.is_null() {
            return -1;
        }
        let _owned_input_source = OwnedCf(input_source);

        let languages = TISGetInputSourceProperty(input_source, kTISPropertyInputSourceLanguages);
        if languages.is_null() || CFArrayGetCount(languages) == 0 {
            return -1;
        }

        // CFArrayGetValueAtIndex returns a borrowed value. It must not be released.
        let language = CFArrayGetValueAtIndex(languages, 0);
        if language.is_null() {
            return -1;
        }

        let mut buffer = [0 as c_char; 128];
        // kCFStringEncodingUTF8 from CoreFoundation's CFStringEncoding.h.
        const UTF8_ENCODING: u32 = 0x0800_0100;
        if CFStringGetCString(
            language,
            buffer.as_mut_ptr(),
            buffer.len() as CFIndex,
            UTF8_ENCODING,
        ) == 0
        {
            return -1;
        }

        let language_tag = CStr::from_ptr(buffer.as_ptr()).to_bytes();
        // Preserve NSString's old isLike:@"en" behavior: with no wildcards,
        // only the exact BCP 47 language tag "en" matches.
        let is_english = language_tag == b"en";

        if is_english {
            1
        } else {
            0
        }
    }
}
