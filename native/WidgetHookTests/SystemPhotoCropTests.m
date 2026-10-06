#import "SystemPhotoCrop.h"
#import <math.h>

@interface CropFixture : NSObject
@property CGSize receivedSize;
- (CGRect)suggestedCropForTargetSize:(CGSize)size;
@end
@implementation CropFixture
- (CGRect)suggestedCropForTargetSize:(CGSize)size {
    self.receivedSize = size;
    return CGRectMake(80, 40, 200, 120);
}
@end
@interface WrongResultFixture : NSObject
- (CGPoint)suggestedCropForTargetSize:(CGSize)size;
@end
@implementation WrongResultFixture
- (CGPoint)suggestedCropForTargetSize:(CGSize)size { abort(); }
@end
@interface WrongArgumentFixture : NSObject
- (CGRect)suggestedCropForTargetSize:(double)size;
@end
@implementation WrongArgumentFixture
- (CGRect)suggestedCropForTargetSize:(double)size { abort(); }
@end
@interface ThrowingFixture : NSObject
- (CGRect)suggestedCropForTargetSize:(CGSize)size;
@end
@implementation ThrowingFixture
- (CGRect)suggestedCropForTargetSize:(CGSize)size {
    [NSException raise:@"ChangedPrivateAPI" format:@"Test exception"];
    return CGRectZero;
}
@end
@interface InvalidFixture : NSObject
- (CGRect)suggestedCropForTargetSize:(CGSize)size;
@end
@implementation InvalidFixture
- (CGRect)suggestedCropForTargetSize:(CGSize)size { return CGRectMake(NAN, 0, 1, 1); }
@end

static void require(BOOL success, NSString *name) {
    if (!success) { NSLog(@"FAIL: %@", name); exit(1); }
    NSLog(@"PASS: %@", name);
}
int main(void) {
    @autoreleasepool {
        CGSize target = CGSizeMake(510, 480);
        CropFixture *fixture = [CropFixture new];
        require(CGRectEqualToRect(SCSuggestedPhotoCrop(fixture, target), CGRectMake(80, 40, 200, 120)), @"Structure result preserved");
        require(CGSizeEqualToSize(fixture.receivedSize, target), @"Structure argument preserved");
        require(CGRectIsNull(SCSuggestedPhotoCrop([NSObject new], target)), @"Missing selector falls back");
        require(CGRectIsNull(SCSuggestedPhotoCrop([WrongResultFixture new], target)), @"Incompatible result is never called");
        require(CGRectIsNull(SCSuggestedPhotoCrop([WrongArgumentFixture new], target)), @"Incompatible argument is never called");
        require(CGRectIsNull(SCSuggestedPhotoCrop([ThrowingFixture new], target)), @"Private exception falls back");
        require(CGRectIsNull(SCSuggestedPhotoCrop([InvalidFixture new], target)), @"Nonfinite result falls back");
        require(CGRectIsNull(SCSuggestedPhotoCrop(fixture, CGSizeZero)), @"Empty target rejected");
        require(CGRectIsNull(SCSuggestedPhotoCrop(fixture, CGSizeMake(INFINITY, 1))), @"Nonfinite target rejected");
    }
    return 0;
}
