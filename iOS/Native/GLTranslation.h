#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface GLTranslation : NSObject
- (nullable instancetype)initWithModelPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error __attribute__((swift_error(none)));
- (nullable NSString *)translate:(NSString *)text error:(NSError * _Nullable * _Nullable)error __attribute__((swift_error(none)));
- (void)cancel;
- (void)resume;
@end
NSData * _Nullable GLCreateIdentityPKCS12(NSString *password, NSError * _Nullable * _Nullable error) __attribute__((swift_error(none)));
NS_ASSUME_NONNULL_END
