#import "Controller.h"
#import "Gestures.h"
#import "PreferenceKeys.h"
#import "WindowFrame.h"
#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>

enum {
  kMaxScreens = 16,
  kMaxSavedWindowFrames = 64,
};
static const double kFilledTolerance = 24;

int previousFingerCount;
GestureSettings gestureSettings;
TapState tap;
ClickState click;

BOOL needToClick;
CFMutableArrayRef currentDeviceList;
CFMachPortRef currentEventTap;
CFRunLoopSourceRef currentRunLoopSource;
CFMutableDictionaryRef savedWindowFrames;

@implementation Controller {
  NSTimer* _restartTimer __weak;
  BOOL _isUserSessionActive;
  BOOL _isAccessibilityTrusted;
}

- (void)start
{
  NSLog(@"Starting all listeners...");

  _isUserSessionActive = YES;
  _isAccessibilityTrusted = AXIsProcessTrusted();
  
  loadTouchSettings();
  
  NSString* needToClickNullable = [[NSUserDefaults standardUserDefaults] valueForKey:@"needClick"];
  needToClick = needToClickNullable ? [[NSUserDefaults standardUserDefaults] boolForKey:@"needClick"] : [self getIsSystemTapToClickDisabled];
  
  [[[NSWorkspace sharedWorkspace] notificationCenter]
   addObserver:self
   selector:@selector(receiveWakeNote:)
   name:NSWorkspaceDidWakeNotification
   object:NULL];
  
  [[[NSWorkspace sharedWorkspace] notificationCenter]
   addObserver:self
   selector:@selector(receiveSessionResignActiveNote:)
   name:NSWorkspaceSessionDidResignActiveNotification
   object:NULL];
  [[[NSWorkspace sharedWorkspace] notificationCenter]
   addObserver:self
   selector:@selector(receiveSessionBecomeActiveNote:)
   name:NSWorkspaceSessionDidBecomeActiveNotification
   object:NULL];
  
  IONotificationPortRef port = IONotificationPortCreate(kIOMasterPortDefault);
  CFRunLoopAddSource(CFRunLoopGetMain(),
                     IONotificationPortGetRunLoopSource(port),
                     kCFRunLoopDefaultMode);
  io_iterator_t handle;
  kern_return_t err = IOServiceAddMatchingNotification(
                                                       port, kIOFirstMatchNotification,
                                                       IOServiceMatching("AppleMultitouchDevice"), multitouchDeviceAddedCallback,
                                                       self, &handle);
  if (err) {
    NSLog(@"Failed to register notification for touchpad attach: %xd, will not "
          @"handle newly "
          @"attached devices",
          err);
    IONotificationPortDestroy(port);
  } else {
    io_object_t item;
    while ((item = IOIteratorNext(handle))) {
      IOObjectRelease(item);
    }
  }
  
  CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallBack, self);

  [self updateListeners];
}

- (void)updateListeners
{
  BOOL wantsTouch = _isUserSessionActive;
  BOOL wantsEventTap = wantsTouch && needToClick && _isAccessibilityTrusted;

  if (wantsTouch && !currentDeviceList) {
    registerTouchCallback();
  } else if (!wantsTouch && currentDeviceList) {
    unregisterTouchCallback();
  }

  if (wantsEventTap && !currentEventTap) {
    registerMouseCallback();
  } else if (!wantsEventTap && currentEventTap) {
    unregisterMouseCallback();
  }
}

static void registerTouchCallback(void)
{
    currentDeviceList = MTDeviceCreateList();

    for (CFIndex i = 0; i < CFArrayGetCount(currentDeviceList); i++)
    {
      registerMTDeviceCallback((MTDeviceRef)CFArrayGetValueAtIndex(currentDeviceList, i), touchCallback);
    }
}
static void unregisterTouchCallback(void)
{
    if (!currentDeviceList) {
      return;
    }

    for (CFIndex i = 0; i < CFArrayGetCount(currentDeviceList); i++)
    {
      unregisterMTDeviceCallback((MTDeviceRef)CFArrayGetValueAtIndex(currentDeviceList, i), touchCallback);
    }

    // MultitouchSupport gives the list the only reference to each device, so this releases the devices too.
    CFRelease(currentDeviceList);
    currentDeviceList = NULL;
}

static void registerMouseCallback(void)
{
    CGEventMask eventMask = (CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventLeftMouseUp));

    CFMachPortRef eventTap = CGEventTapCreate(
                                              kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                                              eventMask, mouseCallback, NULL);
    currentEventTap = eventTap;

    if (eventTap) {
        CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
        currentRunLoopSource = runLoopSource;
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource,
                           kCFRunLoopCommonModes);

        CGEventTapEnable(eventTap, true);
    } else {
        NSLog(@"Couldn't create event tap! Check accessibility permissions.");
    }
}

- (void)setAccessibilityTrusted:(BOOL)isTrusted
{
  _isAccessibilityTrusted = isTrusted;
  [self updateListeners];
}

static void unregisterMouseCallback(void)
{
    if (currentRunLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), currentRunLoopSource, kCFRunLoopCommonModes);
        CFRelease(currentRunLoopSource);
        currentRunLoopSource = NULL;
    }
    if (currentEventTap) {
        CGEventTapEnable(currentEventTap, false);
        CFMachPortInvalidate(currentEventTap);
        CFRelease(currentEventTap);
        currentEventTap = NULL;
    }
}

- (void)scheduleRestart:(NSTimeInterval)delay
{
  if (_restartTimer != nil) {
    [_restartTimer invalidate];
  }
  
  _restartTimer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                  repeats:NO
                                                    block:^(NSTimer* timer) {
                                                      [self restartListeners];
                                                    }];
}

- (void)receiveWakeNote:(NSNotification*)note
{
  NSLog(@"System woke up, restarting...");
  [self scheduleRestart:10];
}

- (void)receiveSessionResignActiveNote:(NSNotification*)note
{
  NSLog(@"User session resigned active, stopping listeners...");
  _isUserSessionActive = NO;
  [self updateListeners];
}

- (void)receiveSessionBecomeActiveNote:(NSNotification*)note
{
  NSLog(@"User session became active, restarting...");
  _isUserSessionActive = YES;
  [self restartListeners];
}

- (BOOL)getClickMode
{
  return needToClick;
}

- (void)setMode:(BOOL)click
{
  [[NSUserDefaults standardUserDefaults] setBool:click forKey:@"needClick"];
  needToClick = click;
  [self updateListeners];
}
- (void)resetClickMode
{
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"needClick"];
  needToClick = [self getIsSystemTapToClickDisabled];
  [self updateListeners];
}

CGEventRef mouseCallback(CGEventTapProxy proxy, CGEventType type,
                         CGEventRef event, void* refcon)
{
  if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
    NSLog(@"Event tap was disabled by the system, re-enabling...");
    CGEventTapEnable(currentEventTap, true);
    return event;
  }
  
  BOOL isButtonDown = type == kCGEventLeftMouseDown;
  if (needToClick && ClickBecomesMiddle(&click, isButtonDown)) {
    CGEventSetType(event, isButtonDown ? kCGEventOtherMouseDown : kCGEventOtherMouseUp);
    CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, kCGMouseButtonCenter);
  }
  return event;
}

static void loadTouchSettings(void)
{
  @autoreleasepool {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    int fingers = (int)[defaults integerForKey:kFingersNum];
    int fillFingers = [defaults boolForKey:kFillTap] ? (int)[defaults integerForKey:kFillFingers] : 0;
    if (fillFingers == fingers) {
      fillFingers = 0;
    }
    int fullscreenFingers = [defaults boolForKey:kFullscreenTap] ? (int)[defaults integerForKey:kFullscreenFingers] : 0;
    if (fullscreenFingers == fingers || fullscreenFingers == fillFingers) {
      fullscreenFingers = 0;
    }
    gestureSettings = (GestureSettings){
      .fingers = fingers,
      .fillFingers = fillFingers,
      .fullscreenFingers = fullscreenFingers,
      .maxDistanceDelta = [defaults floatForKey:kMaxDistanceDelta],
      .maxTimeDelta = [defaults integerForKey:kMaxTimeDeltaMs] / 1000.0,
    };
  }
}

int touchCallback(int device, Finger* data, int nFingers, double timestamp,
                  int frame)
{
  if (nFingers > 0 && previousFingerCount == 0) {
    loadTouchSettings();
  }
  previousFingerCount = nFingers;
  
  if (needToClick) {
    click.fingersDown = nFingers == gestureSettings.fingers;
  }

  int tapFingers = TapFrameCompletesTapWithFingers(&tap, &gestureSettings, data, nFingers, timestamp);
  if (tapFingers == 0) {
    return 0;
  }
  if (tapFingers == gestureSettings.fillFingers) {
    dispatch_async_f(dispatch_get_main_queue(), NULL, toggleFocusedWindowFill);
  } else if (tapFingers == gestureSettings.fullscreenFingers) {
    dispatch_async_f(dispatch_get_main_queue(), NULL, toggleFocusedWindowFullscreen);
  } else if (!needToClick) {
    CGEventRef ourEvent = CGEventCreate(NULL);
    CGPoint ourLoc = CGEventGetLocation(ourEvent);
    CFRelease(ourEvent);
    
    postMouseEvent(kCGEventOtherMouseDown, kCGMouseButtonCenter, ourLoc);
    postMouseEvent(kCGEventOtherMouseUp, kCGMouseButtonCenter, ourLoc);
  }
  
  return 0;
}

- (void)restartListeners
{
  NSLog(@"Restarting app functionality...");
  unregisterTouchCallback();
  unregisterMouseCallback();
  [self updateListeners];
}

void multitouchDeviceAddedCallback(void* _controller,
                                   io_iterator_t iterator)
{
  io_object_t item;
  while ((item = IOIteratorNext(iterator))) {
    IOObjectRelease(item);
  }
  
  NSLog(@"Multitouch device added, restarting...");
  Controller* controller = (Controller*)_controller;
  [controller scheduleRestart:2];
}

void displayReconfigurationCallBack(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void* _controller)
{
  if(flags & kCGDisplaySetModeFlag || flags & kCGDisplayAddFlag || flags & kCGDisplayRemoveFlag || flags & kCGDisplayDisabledFlag)
  {
    NSLog(@"Display reconfigured, restarting...");
    Controller* controller = (Controller*)_controller;
    [controller scheduleRestart:2];
  }
}

static void registerMTDeviceCallback(MTDeviceRef device, MTContactCallbackFunction callback) {
    MTRegisterContactFrameCallback(device, callback);
    MTDeviceStart(device, 0);
}
static void unregisterMTDeviceCallback(MTDeviceRef device, MTContactCallbackFunction callback) {
    MTUnregisterContactFrameCallback(device, callback);
    MTDeviceStop(device);
}

static void postMouseEvent(CGEventType eventType, CGMouseButton buttonType, CGPoint ourLoc) {
    CGEventRef mouseEvent = CGEventCreateMouseEvent(NULL, eventType, ourLoc, buttonType);
    CGEventPost(kCGHIDEventTap, mouseEvent);
    CFRelease(mouseEvent);
}

static void postFullscreenShortcut(void) {
    for (int isKeyDown = 1; isKeyDown >= 0; isKeyDown--) {
        CGEventRef keyEvent = CGEventCreateKeyboardEvent(NULL, kVK_ANSI_F, isKeyDown);
        CGEventSetFlags(keyEvent, kCGEventFlagMaskControl | kCGEventFlagMaskCommand);
        CGEventPost(kCGHIDEventTap, keyEvent);
        CFRelease(keyEvent);
    }
}

static CFTypeRef copyFocusedWindow(void) {
    if (!AXIsProcessTrusted()) {
        return NULL;
    }

    pid_t pid;
    @autoreleasepool {
        pid = [[[NSWorkspace sharedWorkspace] frontmostApplication] processIdentifier];
    }
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    CFTypeRef window = NULL;
    AXError error = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute, &window);
    CFRelease(app);
    if (error != kAXErrorSuccess) {
        if (window) {
            CFRelease(window);
        }
        return NULL;
    }
    return window;
}

static bool windowIsFullscreen(CFTypeRef window) {
    CFTypeRef isFullscreen = NULL;
    if (AXUIElementCopyAttributeValue(window, CFSTR("AXFullScreen"), &isFullscreen) != kAXErrorSuccess || !isFullscreen) {
        return false;
    }
    bool result = CFGetTypeID(isFullscreen) == CFBooleanGetTypeID() && CFBooleanGetValue(isFullscreen);
    CFRelease(isFullscreen);
    return result;
}

static bool copyAXValue(CFTypeRef window, CFStringRef attribute, AXValueType type, void* value) {
    CFTypeRef axValue = NULL;
    if (AXUIElementCopyAttributeValue(window, attribute, &axValue) != kAXErrorSuccess || !axValue) {
        return false;
    }
    bool result = CFGetTypeID(axValue) == AXValueGetTypeID() && AXValueGetValue(axValue, type, value);
    CFRelease(axValue);
    return result;
}

static bool copyWindowFrame(CFTypeRef window, WindowRect* frame) {
    CGPoint position;
    CGSize size;
    if (!copyAXValue(window, kAXPositionAttribute, kAXValueTypeCGPoint, &position) ||
        !copyAXValue(window, kAXSizeAttribute, kAXValueTypeCGSize, &size)) {
        return false;
    }
    *frame = (WindowRect){position.x, position.y, size.width, size.height};
    return true;
}

static void setWindowFrame(CFTypeRef window, WindowRect frame) {
    CGPoint origin = {frame.x, frame.y};
    CGSize size = {frame.width, frame.height};
    AXValueRef position = AXValueCreate(kAXValueTypeCGPoint, &origin);
    AXValueRef dimensions = AXValueCreate(kAXValueTypeCGSize, &size);
    // Apps clamp a new size to the screen space left from the current position, so move, resize, then move again.
    AXUIElementSetAttributeValue(window, kAXPositionAttribute, position);
    AXUIElementSetAttributeValue(window, kAXSizeAttribute, dimensions);
    AXUIElementSetAttributeValue(window, kAXPositionAttribute, position);
    CFRelease(position);
    CFRelease(dimensions);
}

static WindowRect windowRectFromCocoa(NSRect rect, double primaryScreenHeight) {
    WindowRect frame = {rect.origin.x, rect.origin.y, rect.size.width, rect.size.height};
    return WindowFrameFlipped(frame, primaryScreenHeight);
}

static bool usableFrameForWindow(WindowRect window, WindowRect* usable) {
    @autoreleasepool {
        NSArray* screens = [NSScreen screens];
        int count = (int)MIN([screens count], kMaxScreens);
        if (count == 0) {
            return false;
        }
        double primaryScreenHeight = NSHeight([[screens objectAtIndex:0] frame]);
        WindowRect frames[kMaxScreens];
        for (int i = 0; i < count; i++) {
            frames[i] = windowRectFromCocoa([[screens objectAtIndex:i] frame], primaryScreenHeight);
        }
        int index = WindowFrameScreenIndex(window, frames, count);
        *usable = windowRectFromCocoa([[screens objectAtIndex:index] visibleFrame], primaryScreenHeight);
        return true;
    }
}

static void toggleFocusedWindowFill(void* unused) {
    CFTypeRef window = copyFocusedWindow();
    if (!window) {
        return;
    }

    Boolean isSettable = false;
    WindowRect frame, usable;
    if (!windowIsFullscreen(window) &&
        AXUIElementIsAttributeSettable(window, kAXSizeAttribute, &isSettable) == kAXErrorSuccess && isSettable &&
        copyWindowFrame(window, &frame) && usableFrameForWindow(frame, &usable)) {
        if (!savedWindowFrames) {
            savedWindowFrames = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
                                                          &kCFTypeDictionaryValueCallBacks);
        }
        if (!WindowFrameIsFilled(frame, usable, kFilledTolerance)) {
            if (CFDictionaryGetCount(savedWindowFrames) >= kMaxSavedWindowFrames) {
                CFDictionaryRemoveAllValues(savedWindowFrames);
            }
            CFDataRef saved = CFDataCreate(kCFAllocatorDefault, (const UInt8*)&frame, sizeof(frame));
            CFDictionarySetValue(savedWindowFrames, window, saved);
            CFRelease(saved);
            setWindowFrame(window, usable);
        } else {
            CFDataRef saved = CFDictionaryGetValue(savedWindowFrames, window);
            WindowRect restored = WindowFrameCenteredShrink(usable, 2.0 / 3);
            if (saved && CFDataGetLength(saved) == sizeof(restored)) {
                CFDataGetBytes(saved, CFRangeMake(0, sizeof(restored)), (UInt8*)&restored);
            }
            CFDictionaryRemoveValue(savedWindowFrames, window);
            setWindowFrame(window, restored);
        }
    }
    CFRelease(window);
}

static void toggleFocusedWindowFullscreen(void* unused) {
    CFTypeRef window = copyFocusedWindow();
    if (!window) {
        return;
    }

    CFStringRef fullscreenAttribute = CFSTR("AXFullScreen");
    Boolean isSettable = false;
    CFTypeRef isFullscreen = NULL;
    if (AXUIElementIsAttributeSettable(window, fullscreenAttribute, &isSettable) == kAXErrorSuccess && isSettable &&
        AXUIElementCopyAttributeValue(window, fullscreenAttribute, &isFullscreen) == kAXErrorSuccess &&
        CFGetTypeID(isFullscreen) == CFBooleanGetTypeID()) {
        AXUIElementSetAttributeValue(window, fullscreenAttribute,
                                     CFBooleanGetValue(isFullscreen) ? kCFBooleanFalse : kCFBooleanTrue);
    } else {
        postFullscreenShortcut();
    }
    if (isFullscreen) {
        CFRelease(isFullscreen);
    }
    CFRelease(window);
}

- (BOOL)getIsSystemTapToClickDisabled {
  Boolean isDefined = false;
  Boolean isEnabled = CFPreferencesGetAppBooleanValue(CFSTR("Clicking"), CFSTR("com.apple.driver.AppleBluetoothMultitouch.trackpad"), &isDefined);
  return isDefined && !isEnabled;
}

@end
