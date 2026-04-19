#import <Foundation/Foundation.h>

@interface ObjCExceptionCatcher : NSObject
+ (BOOL)catchException:(void(^)(void))block;
@end
