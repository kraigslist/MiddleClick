#import "Controller.h"
#import "PreferenceKeys.h"
#import "TrayMenu.h"

int main(int argc, char* argv[])
{
  id keys[] = {
    kFingersNum,
    kFillFingers,
    kFillTap,
    kFullscreenFingers,
    kFullscreenTap,
    kMaxDistanceDelta,
    kMaxTimeDeltaMs,
  };
  id objects[] = {
    [NSNumber numberWithInt:kFingersNumDefault],
    [NSNumber numberWithInt:kFillFingersDefault],
    [NSNumber numberWithBool:kFillTapDefault],
    [NSNumber numberWithInt:kFullscreenFingersDefault],
    [NSNumber numberWithBool:kFullscreenTapDefault],
    [NSNumber numberWithFloat:kMaxDistanceDeltaDefault],
    [NSNumber numberWithInt:kMaxTimeDeltaMsDefault],
  };
  NSUInteger count = sizeof(objects) / sizeof(id);
  NSDictionary *appDefaults = [NSDictionary
                               dictionaryWithObjects:objects
                               forKeys:keys
                               count:count];
  
  [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];
  
  NSApplication* app = [NSApplication sharedApplication];
  
  Controller* con = [Controller new];
  @autoreleasepool {
    [con start];
  }
  
  TrayMenu* menu = [[TrayMenu alloc] initWithController:con];
  [app setDelegate:(id<NSApplicationDelegate>)menu];
  
  [app run];
  
  [con release];
  [menu release];
  
  return EXIT_SUCCESS;
}
