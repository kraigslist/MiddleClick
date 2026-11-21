#import <Cocoa/Cocoa.h>

@interface Controller : NSObject {
}

- (void)start;
- (void)setMode:(BOOL)click;
- (BOOL)getClickMode;
- (void)resetClickMode;
- (void)setAccessibilityTrusted:(BOOL)isTrusted;

@end
