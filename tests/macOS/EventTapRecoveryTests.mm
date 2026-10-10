#import <Cocoa/Cocoa.h>
#import "OpenKeyManager.h"
#include "Engine.h"

extern "C" CGEventRef OpenKeyCallback(CGEventTapProxy, CGEventType, CGEventRef, void *);
extern int vFixChromiumBrowser;

// Fake only the OS event-tap boundary. The manager, callback and Telex engine
// are the application's real compiled objects. No global keystrokes are posted.
static CFMachPortRef testTap;
typedef CGEventRef (*TestCallback)(CGEventTapProxy, CGEventType, CGEventRef, void *);
static TestCallback callback;
static bool tapEnabled;
static NSMutableString *typedText;
static int failures;

static void expect(bool condition, const char *message) {
    printf("%s: %s\n", condition ? "PASS" : "FAIL", message);
    if (!condition) ++failures;
}

CFMachPortRef CGEventTapCreate(CGEventTapLocation location, CGEventTapPlacement place,
                             CGEventTapOptions options, CGEventMask mask,
                             CGEventTapCallBack handler, void *context) {
    callback = handler;
    testTap = CFMachPortCreate(kCFAllocatorDefault, NULL, NULL, NULL);
    return testTap;
}

void CGEventTapEnable(CFMachPortRef tap, bool enable) {
    expect(tap == testTap && CFMachPortIsValid(tap), "enable uses the live owned tap");
    tapEnabled = enable;
}

static void receiveEvent(CGEventRef event) {
    if (!event || CGEventGetType(event) != kCGEventKeyDown) return;
    if (CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) == 51) {
        if (typedText.length) [typedText deleteCharactersInRange:NSMakeRange(typedText.length - 1, 1)];
        return;
    }
    UniChar characters[64];
    UniCharCount length = 0;
    CGEventKeyboardGetUnicodeString(event, 64, &length, characters);
    [typedText appendString:[NSString stringWithCharacters:characters length:length]];
}

void CGEventTapPostEvent(CGEventTapProxy proxy, CGEventRef event) {
    receiveEvent(event);
}

static void typeKey(CGKeyCode keycode, UniChar character) {
    CGEventRef event = CGEventCreateKeyboardEvent(NULL, keycode, true);
    CGEventSetFlags(event, 0);
    CGEventKeyboardSetUnicodeString(event, 1, &character);
    receiveEvent(tapEnabled ? callback(NULL, kCGEventKeyDown, event, NULL) : event);
    CFRelease(event);
}

static void checkTelex(const char *message) {
    startNewSession();
    [typedText setString:@""];
    typeKey(KEY_A, 'a');
    typeKey(KEY_S, 's');
    expect([typedText isEqualToString:@"á"], message);
}

int main(void) {
    @autoreleasepool {
        typedText = [NSMutableString string];
        expect([OpenKeyManager initEventTap], "manager initializes");
        expect(callback == OpenKeyCallback, "manager installs the production callback");
        vLanguage = 1;
        vInputType = 0;
        vCodeTable = 0;
        vCheckSpelling = 0;
        vUseMacro = 0;
        vUseSmartSwitchKey = 0;
        vOtherLanguage = 0;
        vFixRecommendBrowser = 0;
        vFixChromiumBrowser = 0;
        checkTelex("normal Telex converts as to á");

        const CGEventType notifications[] = {
            kCGEventTapDisabledByTimeout, kCGEventTapDisabledByUserInput
        };
        for (CGEventType notification : notifications) {
            for (int attempt = 0; attempt < 3; ++attempt) {
                tapEnabled = false;
                callback(NULL, notification, NULL, NULL);
                expect(tapEnabled, notification == kCGEventTapDisabledByTimeout
                       ? "timeout notification restores typing" : "user-input notification restores typing");
                checkTelex("Telex works after recovery without restarting");
            }
        }

        CGEventRef event = CGEventCreate(NULL);
        CGEventSetType(event, kCGEventNull);
        expect(callback(NULL, kCGEventNull, event, NULL) == event, "unrelated event passes through");
        CFRelease(event);
        [OpenKeyManager stopEventTap];
        expect(![OpenKeyManager isInited], "manager stops cleanly");
        // A late notification must not re-enable or dereference a released tap.
        tapEnabled = false;
        callback(NULL, kCGEventTapDisabledByTimeout, NULL, NULL);
        expect(!tapEnabled, "late notification after stop leaves the tap stopped");
    }
    return failures ? 1 : 0;
}
