#import "TrayMenu.h"
#import "PreferenceKeys.h"
#import "Controller.h"
#import <Cocoa/Cocoa.h>

@implementation TrayMenu

- (id)initWithController:(Controller*)ctrl
{
  if ((self = [super init])) {
    myController = ctrl;
    [self setChecks];
  }
  return self;
}

- (void)initAccessibilityPermissionStatus:(NSMenu*)menu
{
  BOOL hasAccessibilityPermission = AXIsProcessTrusted();

  [self updateAccessibilityPermissionStatus:menu
                 hasAccessibilityPermission:hasAccessibilityPermission];
  [myController setAccessibilityTrusted:hasAccessibilityPermission];

  if (!hasAccessibilityPermission) {
    [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:NO block:^(NSTimer* timer) {
      [self initAccessibilityPermissionStatus:menu];
    }];
  }
}
- (void)updateAccessibilityPermissionStatus:(NSMenu*)menu
                 hasAccessibilityPermission:(BOOL)isTrusted
{
  _statusItem.button.appearsDisabled = !isTrusted;
  if (!isTrusted) {
    _statusItem.visible = YES;
  }
  accessibilityPermissionStatusItem.hidden = isTrusted;
  accessibilityPermissionActionItem.hidden = isTrusted;
}

- (void)openWebsite:(id)sender
{
  NSURL* url = [NSURL
                URLWithString:@"https://github.com/kraigslist/MiddleClick"];
  [[NSWorkspace sharedWorkspace] openURL:url];
}
- (void)openAccessibilitySettings:(id)sender
{
  BOOL isPreCatalina = (floor(NSAppKitVersionNumber) < NSAppKitVersionNumber10_15);
  if (isPreCatalina) {
    NSAppleScript *a = [[NSAppleScript alloc] initWithSource:
                        @"tell application \"System Preferences\"\n"
                        "activate\n"
                        "reveal anchor \"Privacy_Accessibility\" of pane \"com.apple.preference.security\"\n"
                        "end tell"];
    [a executeAndReturnError:nil];
    [a release];
  } else {
    NSURL* url = [NSURL
                  URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    [[NSWorkspace sharedWorkspace] openURL:url];
  }
}

- (void)toggleTapToClick:(id)sender
{
  [myController setMode:[sender state] == NSControlStateValueOn];
  [self setChecks];
}

- (void)resetTapToClick:(id)sender
{
  [myController resetClickMode];
  [self setChecks];
}

- (void)toggleFillTap:(id)sender
{
  [[NSUserDefaults standardUserDefaults] setBool:[sender state] != NSControlStateValueOn forKey:kFillTap];
  [self setChecks];
}

- (void)toggleFullscreenTap:(id)sender
{
  [[NSUserDefaults standardUserDefaults] setBool:[sender state] != NSControlStateValueOn forKey:kFullscreenTap];
  [self setChecks];
}

- (void)setTapItem:(NSMenuItem*)item
             title:(NSString*)format
           fingers:(int)fingers
           enabled:(BOOL)isEnabled
           clashes:(BOOL)clashes
{
  [item setTitle:[NSString stringWithFormat:format, fingers]];
  [item setState:isEnabled ? NSControlStateValueOn : NSControlStateValueOff];
  item.hidden = fingers <= 0 || clashes;
}

- (void)setChecks
{
  bool clickMode = [myController getClickMode];
  NSString* clickModeInfo = clickMode ? @"Click" : @"Click or Tap";
  
  NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
  int fingersQua = (int)[defaults integerForKey:kFingersNum];
  int fillFingers = (int)[defaults integerForKey:kFillFingers];
  int fullscreenFingers = (int)[defaults integerForKey:kFullscreenFingers];
  BOOL isFillEnabled = [defaults boolForKey:kFillTap];
  BOOL fillClashes = fillFingers == fingersQua;
  
  [infoItem setTitle:[clickModeInfo stringByAppendingFormat: @" with %d Fingers", fingersQua]];
  [tapToClickItem setState:clickMode ? NSControlStateValueOff : NSControlStateValueOn];
  
  [self setTapItem:fillTapItem
             title:@"Tap %d Fingers to Fill"
           fingers:fillFingers
           enabled:isFillEnabled
           clashes:fillClashes];
  [self setTapItem:fullscreenTapItem
             title:@"Tap %d Fingers for Full Screen"
           fingers:fullscreenFingers
           enabled:[defaults boolForKey:kFullscreenTap]
           clashes:fullscreenFingers == fingersQua ||
                   (isFillEnabled && !fillClashes && fullscreenFingers == fillFingers)];
}

- (void)actionQuit:(id)sender
{
  [NSApp terminate:sender];
}

- (NSMenu*)createMenu
{
  NSMenu* menu = [NSMenu new];
  NSMenuItem* menuItem;
  
  
  
  [self createMenuAccessibilityPermissionItems:menu];
  
  menuItem = [menu addItemWithTitle:[NSString stringWithFormat:@"About %@...", getAppName()]
                             action:@selector(openWebsite:)
                      keyEquivalent:@""];
  [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  infoItem = [menu addItemWithTitle:@""
                             action:nil
                      keyEquivalent:@""];
  [infoItem setTarget:self];
  
  tapToClickItem = [menu addItemWithTitle:@"Tap to click"
                                   action:@selector(toggleTapToClick:)
                            keyEquivalent:@""];
  [tapToClickItem setTarget:self];
  
  NSMenuItem* resetItem = [menu addItemWithTitle:@"Reset to System Settings"
                                          action:@selector(resetTapToClick:)
                                   keyEquivalent:@""];
  resetItem.alternate = YES;
  resetItem.keyEquivalentModifierMask = NSEventModifierFlagOption;
  [resetItem setTarget:self];
  
  fillTapItem = [menu addItemWithTitle:@""
                                action:@selector(toggleFillTap:)
                         keyEquivalent:@""];
  [fillTapItem setTarget:self];
  
  fullscreenTapItem = [menu addItemWithTitle:@""
                                      action:@selector(toggleFullscreenTap:)
                               keyEquivalent:@""];
  [fullscreenTapItem setTarget:self];
  
  [self setChecks];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:@"Quit"
                             action:@selector(actionQuit:)
                      keyEquivalent:@"q"];
  [menuItem setTarget:self];
  
  return menu;
}

- (void)createMenuAccessibilityPermissionItems:(NSMenu *)menu
{
  accessibilityPermissionStatusItem = [menu addItemWithTitle:@"Missing Accessibility permission" action:nil keyEquivalent:@""];
  accessibilityPermissionActionItem = [menu addItemWithTitle:@"Open Privacy Preferences" action:@selector(openAccessibilitySettings:) keyEquivalent:@","];

  [menu addItem:[NSMenuItem separatorItem]];
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification
{
  NSMenu* menu = [self createMenu];
  
  NSImage* icon = [NSImage imageNamed:(@"StatusIcon")];
  [icon setSize:CGSizeMake(24, 24)];
  [icon setTemplate:YES];
  
  _statusItem = [[[NSStatusBar systemStatusBar]
                  statusItemWithLength:24] retain];
  _statusItem.behavior = NSStatusItemBehaviorRemovalAllowed;
  _statusItem.menu = menu;
  _statusItem.button.toolTip = getAppName();
  _statusItem.button.image = icon;

  [self initAccessibilityPermissionStatus:menu];
  
  [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                      selector:@selector(receiveAccessibilityNote:)
                                                          name:@"com.apple.accessibility.api"
                                                        object:nil
                                            suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
  
  [menu release];
}

/// Posted whenever any app's Accessibility permission changes. `AXIsProcessTrusted` lags behind it, hence the delay.
- (void)receiveAccessibilityNote:(NSNotification*)note
{
  BOOL isAlreadyPolling = !accessibilityPermissionStatusItem.hidden;
  if (isAlreadyPolling) {
    return;
  }
  [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer* timer) {
    [self initAccessibilityPermissionStatus:self->_statusItem.menu];
  }];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender
                    hasVisibleWindows:(BOOL)flag
{
  _statusItem.visible = true;
  return 1;
}

NSString* getAppName(void) {
    return [[NSProcessInfo processInfo] processName];
}

@end
