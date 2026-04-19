#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (BOOL)catchException:(void(^)(void))block {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"[NotchPal] Caught exception: %@ — %@", exception.name, exception.reason);
        return NO;
    }
}

@end
