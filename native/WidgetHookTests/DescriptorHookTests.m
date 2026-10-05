#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "WidgetBackgroundHook.h"

// Fake secure-coding counterparts exercise the production hook on macOS.
// They test reply mutation and fallback, not SpringBoard rendering on iOS.
@interface CHSBaseDescriptor : NSObject <NSSecureCoding>
@property(nonatomic, copy) NSString *kind;
@end
@implementation CHSBaseDescriptor
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) _kind = [coder decodeObjectOfClass:NSString.class forKey:@"kind"];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:self.kind forKey:@"kind"]; }
@end

@interface CHSControlDescriptor : CHSBaseDescriptor
@end
@implementation CHSControlDescriptor
@end

@interface CHSWidgetDescriptor : CHSBaseDescriptor <NSMutableCopying>
@property(nonatomic) BOOL backgroundRemovable;
@property(nonatomic) BOOL transparent;
@property(nonatomic) NSUInteger preferredBackgroundStyle;
@property(nonatomic) BOOL supportsVibrantContent;
@property(nonatomic) BOOL throwOnCopy;
@end
@implementation CHSWidgetDescriptor
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        _backgroundRemovable = [coder decodeBoolForKey:@"removable"];
        _transparent = [coder decodeBoolForKey:@"transparent"];
        _preferredBackgroundStyle = [coder decodeIntegerForKey:@"style"];
        _supportsVibrantContent = [coder decodeBoolForKey:@"vibrant"];
        _throwOnCopy = [coder decodeBoolForKey:@"throwOnCopy"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder {
    [super encodeWithCoder:coder];
    [coder encodeBool:self.backgroundRemovable forKey:@"removable"];
    [coder encodeBool:self.transparent forKey:@"transparent"];
    [coder encodeInteger:self.preferredBackgroundStyle forKey:@"style"];
    [coder encodeBool:self.supportsVibrantContent forKey:@"vibrant"];
    [coder encodeBool:self.throwOnCopy forKey:@"throwOnCopy"];
}
- (id)mutableCopyWithZone:(NSZone *)zone {
    if (self.throwOnCopy) [NSException raise:@"CopyUnavailable" format:@"Test fallback"];
    CHSWidgetDescriptor *copy = [[[self class] allocWithZone:zone] init];
    copy.kind = self.kind;
    copy.backgroundRemovable = self.backgroundRemovable;
    copy.transparent = self.transparent;
    copy.preferredBackgroundStyle = self.preferredBackgroundStyle;
    copy.supportsVibrantContent = self.supportsVibrantContent;
    return copy;
}
@end

@interface FakeFetchResult : NSObject <NSSecureCoding>
@property(nonatomic, copy) NSArray *activities;
@property(nonatomic, copy) NSArray *controls;
@property(nonatomic, copy) NSArray *widgets;
@property(nonatomic) BOOL omitWidgets;
@end
@implementation FakeFetchResult
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _activities = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSArray.class, CHSBaseDescriptor.class, nil] forKey:@"activityDescriptors"];
        _controls = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSArray.class, CHSControlDescriptor.class, nil] forKey:@"controlDescriptors"];
        _widgets = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSArray.class, CHSWidgetDescriptor.class, nil] forKey:@"widgetDescriptors"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.activities forKey:@"activityDescriptors"];
    [coder encodeObject:self.controls forKey:@"controlDescriptors"];
    if (!self.omitWidgets) [coder encodeObject:self.widgets forKey:@"widgetDescriptors"];
}
@end

@interface FakeExportedObject : NSObject
@property(nonatomic, strong) id result;
@property(nonatomic) NSUInteger calls;
- (void)getAllCurrentDescriptorsWithCompletion:(void (^)(id))completion;
@end
@implementation FakeExportedObject
- (void)getAllCurrentDescriptorsWithCompletion:(void (^)(id))completion {
    self.calls += 1;
    if (completion) completion(self.result);
}
@end

static NSUInteger checks;
static void Check(BOOL condition, NSString *name) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", name.UTF8String); exit(1); }
    checks += 1;
    printf("PASS: %s\n", name.UTF8String);
}
static Class Register(Class parent, const char *name) {
    Class subclass = objc_allocateClassPair(parent, name, 0);
    if (!subclass) abort();
    objc_registerClassPair(subclass);
    return subclass;
}
static CHSWidgetDescriptor *Widget(NSString *kind) {
    CHSWidgetDescriptor *widget = [CHSWidgetDescriptor new];
    widget.kind = kind;
    return widget;
}
static FakeFetchResult *Packet(NSArray *widgets) {
    CHSBaseDescriptor *activity = [CHSBaseDescriptor new]; activity.kind = @"activity";
    CHSControlDescriptor *control = [CHSControlDescriptor new]; control.kind = @"control";
    FakeFetchResult *packet = [FakeFetchResult new];
    packet.activities = @[activity]; packet.controls = @[control]; packet.widgets = widgets;
    return packet;
}
static id Fetch(FakeExportedObject *server, id result) {
    server.result = result;
    NSUInteger before = server.calls;
    __block NSUInteger callbacks = 0;
    __block id reply;
    [server getAllCurrentDescriptorsWithCompletion:^(id value) { callbacks += 1; reply = value; }];
    if (callbacks != 1 || server.calls != before + 1) abort();
    return reply;
}
static BOOL WrongSetter(id self, SEL selector, NSUInteger value) {
    (void)self; (void)selector; (void)value;
    return NO;
}

int main(void) {
    @autoreleasepool {
        Check(!SCInstallWidgetBackgroundHook(), @"missing export class falls back");
        Class exported = Register(FakeExportedObject.class, "_TtCC9WidgetKit24WidgetExtensionXPCServer14ExportedObject");
        Check(SCInstallWidgetBackgroundHook() && SCInstallWidgetBackgroundHook(), @"late installation is idempotent");
        FakeExportedObject *server = [exported new];
        FakeFetchResult *input = Packet(@[Widget(@"SessionCamera.Clear"), Widget(@"SessionCamera.Blank"), Widget(@"SessionCamera.Blur"), Widget(@"SessionCamera.Standard")]);
        Check(Fetch(server, input) == input, @"missing result class preserves original reply");
        Class resultClass = Register(FakeFetchResult.class, "_TtC9WidgetKit21DescriptorFetchResult");
        FakeFetchResult *output = Fetch(server, input);
        Check([output isMemberOfClass:resultClass], @"result rebuilt with original runtime class");
        CHSWidgetDescriptor *clear = output.widgets[0], *blank = output.widgets[1], *blur = output.widgets[2], *standard = output.widgets[3];
        Check(clear.transparent && clear.backgroundRemovable && clear.preferredBackgroundStyle == 1, @"clear background descriptor");
        Check(blank.transparent && blank.preferredBackgroundStyle == 1, @"blank background descriptor");
        Check(blur.transparent && blur.preferredBackgroundStyle == 2 && blur.supportsVibrantContent, @"blur and vibrancy descriptor");
        Check(!standard.transparent && standard.preferredBackgroundStyle == 0, @"ordinary widget is not patched");
        Check([[(CHSBaseDescriptor *)output.activities[0] kind] isEqual:@"activity"] && [[(CHSControlDescriptor *)output.controls[0] kind] isEqual:@"control"], @"activity and control arrays preserved");
        Check(![(CHSWidgetDescriptor *)input.widgets[0] transparent], @"input descriptor stays immutable");
        FakeFetchResult *unknown = Packet(@[Widget(@"AnotherApp.Clear")]);
        Check(Fetch(server, unknown) == unknown, @"unrelated kinds preserve reply identity");
        FakeFetchResult *malformed = Packet(@[Widget(@"SessionCamera.Clear")]); malformed.omitWidgets = YES;
        Check(Fetch(server, malformed) == malformed, @"missing collection preserves original reply");
        CHSWidgetDescriptor *throwing = Widget(@"SessionCamera.Clear"); throwing.throwOnCopy = YES;
        FakeFetchResult *exception = Packet(@[throwing]);
        Check(Fetch(server, exception) == exception, @"Objective-C exception preserves original reply");
        Class wrong = objc_allocateClassPair(CHSWidgetDescriptor.class, "WrongSetterDescriptor", 0);
        class_addMethod(wrong, @selector(setPreferredBackgroundStyle:), (IMP)WrongSetter, "B@:Q");
        objc_registerClassPair(wrong);
        CHSWidgetDescriptor *badSignature = [wrong new]; badSignature.kind = @"SessionCamera.Clear";
        FakeFetchResult *unsupported = Packet(@[badSignature]);
        Check(Fetch(server, unsupported) == unsupported, @"incompatible setter type preserves original reply");
        NSObject *uncodable = [NSObject new];
        Check(Fetch(server, uncodable) == uncodable && Fetch(server, nil) == nil, @"non-codable and nil replies preserved");
        FakeExportedObject *parent = [FakeExportedObject new]; parent.result = input;
        __block id parentReply;
        [parent getAllCurrentDescriptorsWithCompletion:^(id value) { parentReply = value; }];
        Check(parentReply == input, @"inherited hook does not change parent method");
        NSUInteger before = server.calls;
        [server getAllCurrentDescriptorsWithCompletion:nil];
        Check(server.calls == before + 1, @"nil completion forwards to original method");
        printf("Widget descriptor hook: %lu checks passed; every fetch completion called once.\n", (unsigned long)checks);
    }
    return 0;
}
