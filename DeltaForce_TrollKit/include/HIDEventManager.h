#ifndef HID_EVENT_MANAGER_H
#define HID_EVENT_MANAGER_H

#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDEvent.h>

@interface HIDEventManager : NSObject

+ (instancetype)shared;
- (void)registerEventCallback;
- (void)enqueueEvent:(IOHIDEventRef)event;
- (IOHIDEventRef)getNextEvent;
- (void)sendTouchAtPoint:(CGPoint)point phase:(int)phase;
- (void)sendMouseButtonDown;
- (void)sendMouseButtonUp;

@end
#endif
