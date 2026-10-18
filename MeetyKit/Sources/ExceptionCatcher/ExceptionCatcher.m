#import "ExceptionCatcher.h"

@implementation MTExceptionCatcher

+ (NSError *_Nullable)catching:(NS_NOESCAPE void (^)(void))block {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        if (exception.name) { info[@"ExceptionName"] = exception.name; }
        if (exception.reason) { info[NSLocalizedDescriptionKey] = exception.reason; }
        return [NSError errorWithDomain:@"MTExceptionCatcher" code:1 userInfo:info];
    }
}

@end
