#import "Controller.h"
#import "Gestures.h"
#import "PreferenceKeys.h"
#import <Cocoa/Cocoa.h>

#pragma mark Globals

int previousFingerCount;
GestureSettings gestureSettings;
TapState tap;
ClickState click;

BOOL needToClick;
CFMutableArrayRef currentDeviceList;
CFMachPortRef currentEventTap;
CFRunLoopSourceRef currentRunLoopSource;

#pragma mark Implementation

@implementation Controller {
  NSTimer* _restartTimer __weak; // Using `weak` so that the pointer is automatically set to `nil` when the referenced object is released ( https://en.wikipedia.org/wiki/Automatic_Reference_Counting#Zeroing_Weak_References ). This helps preventing fatal EXC_BAD_ACCESS.
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
  
  // register a callback to know when osx come back from sleep
  [[[NSWorkspace sharedWorkspace] notificationCenter]
   addObserver:self
   selector:@selector(receiveWakeNote:)
   name:NSWorkspaceDidWakeNotification
   object:NULL];
  
  // Multitouch devices registered from more than one logged-in session stop delivering frames,
  // so listen only while this user's session is on the console.
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
  
  // Register IOService notifications for added devices.
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
  
  // when displays are reconfigured restart of the app is needed, so add a calback to the
  // reconifguration of Core Graphics
  CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallBack, self);

  [self updateListeners];
}

/// Installs or removes each listener to match the current state. Every state change ends here.
/// The touch listeners run only while this user's session is on the console, because multitouch
/// devices registered from more than one logged-in session stop delivering frames.
/// The event tap also needs click mode, since tap mode posts its own clicks, and the Accessibility
/// permission, since a default tap without it can block all mouse input.
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
    /// Get list of all multi touch devices
    currentDeviceList = MTDeviceCreateList();

    // Iterate and register callbacks for multitouch devices.
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

    // Iterate and unregister callbacks for multitouch devices.
    for (CFIndex i = 0; i < CFArrayGetCount(currentDeviceList); i++)
    {
      unregisterMTDeviceCallback((MTDeviceRef)CFArrayGetValueAtIndex(currentDeviceList, i), touchCallback);
    }

    // The list holds the only reference to each device, so this releases the devices too.
    CFRelease(currentDeviceList);
    currentDeviceList = NULL;
}

static void registerMouseCallback(void)
{
    /// we only want to see left mouse down and left mouse up, because we only want
    /// to change that one
    CGEventMask eventMask = (CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventLeftMouseUp));

    /// create eventTap which listens for core grpahic events with the filter
    /// specified above (so left mouse down and up again)
    CFMachPortRef eventTap = CGEventTapCreate(
                                              kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                                              eventMask, mouseCallback, NULL);
    currentEventTap = eventTap;

    if (eventTap) {
        // Add to the current run loop.
        CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
        currentRunLoopSource = runLoopSource;
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource,
                           kCFRunLoopCommonModes);

        // Enable the event tap.
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
    // Remove from the current run loop.
    if (currentRunLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), currentRunLoopSource, kCFRunLoopCommonModes);
        CFRelease(currentRunLoopSource);
        currentRunLoopSource = NULL;
    }
    // Disable and destroy the event tap.
    if (currentEventTap) {
        CGEventTapEnable(currentEventTap, false);
        CFMachPortInvalidate(currentEventTap);
        CFRelease(currentEventTap);
        currentEventTap = NULL;
    }
}

/// Schedule listeners to be restarted, if a restart is pending, delay it.
- (void)scheduleRestart:(NSTimeInterval)delay
{
  if (_restartTimer != nil) { // Check whether the timer object was not released.
    [_restartTimer invalidate]; // Invalidate any existing timer.
  }
  
  _restartTimer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                  repeats:NO
                                                    block:^(NSTimer* timer) {
                                                      [self restartListeners];
                                                    }];
}

/// Callback for system wake up. This restarts the app to initialize callbacks.
/// Can be tested by entering `pmset sleepnow` in the Terminal
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

/// listening to mouse clicks to replace them with middle clicks if there are 3
/// fingers down at the time of clicking this is done by replacing the left click
/// down with a other click down and setting the button number to middle click
/// when 3 fingers are down when clicking, and by replacing left click up with
/// other click up and setting three button number to middle click when 3 fingers
/// were down when the last click went down.
CGEventRef mouseCallback(CGEventTapProxy proxy, CGEventType type,
                         CGEventRef event, void* refcon)
{
  // macOS disables a tap that responds too slowly, and does not re-enable it on its own.
  if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
    NSLog(@"Event tap was disabled by the system, re-enabling...");
    CGEventTapEnable(currentEventTap, true);
    return event;
  }
  
  BOOL isButtonDown = type == kCGEventLeftMouseDown;
  if (needToClick && ClickRemap(&click, isButtonDown)) {
    CGEventSetType(event, isButtonDown ? kCGEventOtherMouseDown : kCGEventOtherMouseUp);
    CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, kCGMouseButtonCenter);
  }
  return event;
}

/// Read once per gesture rather than per frame, so that `defaults write` still applies without a relaunch.
static void loadTouchSettings(void)
{
  @autoreleasepool {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    gestureSettings = (GestureSettings){
      .fingers = (int)[defaults integerForKey:kFingersNum],
      .maxDistanceDelta = [defaults floatForKey:kMaxDistanceDelta],
      .maxTimeDelta = [defaults integerForKey:kMaxTimeDeltaMs] / 1000.0,
    };
  }
}

/// Mulittouch callback, see what is touched. If 3 are on the mouse set
/// threedowns, else unset threedowns.
/// Runs for every frame while touching, so it must not allocate.
int touchCallback(int device, Finger* data, int nFingers, double timestamp,
                  int frame)
{
  if (nFingers > 0 && previousFingerCount == 0) {
    loadTouchSettings();
  }
  previousFingerCount = nFingers;
  
  if (needToClick) {
    click.fingersDown = nFingers == gestureSettings.fingers;
  } else if (TapFrame(&tap, &gestureSettings, data, nFingers, timestamp)) {
    CGEventRef ourEvent = CGEventCreate(NULL);
    CGPoint ourLoc = CGEventGetLocation(ourEvent);
    CFRelease(ourEvent);
    
    postMouseEvent(kCGEventOtherMouseDown, kCGMouseButtonCenter, ourLoc);
    postMouseEvent(kCGEventOtherMouseUp, kCGMouseButtonCenter, ourLoc);
  }
  
  return 0;
}

/// Restart the listeners when devices are connected/invalidated.
- (void)restartListeners
{
  NSLog(@"Restarting app functionality...");
  unregisterTouchCallback();
  unregisterMouseCallback();
  [self updateListeners];
}

/// Callback when a multitouch device is added.
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
    MTRegisterContactFrameCallback(device, callback); // assign callback for device
    MTDeviceStart(device, 0); // start sending events
}
static void unregisterMTDeviceCallback(MTDeviceRef device, MTContactCallbackFunction callback) {
    MTUnregisterContactFrameCallback(device, callback); // unassign callback for device
    MTDeviceStop(device); // stop sending events
}

static void postMouseEvent(CGEventType eventType, CGMouseButton buttonType, CGPoint ourLoc) {
    CGEventRef mouseEvent = CGEventCreateMouseEvent(NULL, eventType, ourLoc, buttonType);
    CGEventPost(kCGHIDEventTap, mouseEvent);
    CFRelease(mouseEvent);
}

/// Returns NO when the setting has never been written.
- (BOOL)getIsSystemTapToClickDisabled {
  Boolean isDefined = false;
  Boolean isEnabled = CFPreferencesGetAppBooleanValue(CFSTR("Clicking"), CFSTR("com.apple.driver.AppleBluetoothMultitouch.trackpad"), &isDefined);
  return isDefined && !isEnabled;
}

@end
