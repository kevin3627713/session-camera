#import "WidgetBackgroundHook.h"
#import <TargetConditionals.h>
#import <objc/message.h>
#import <objc/runtime.h>

// Independent ARC implementation of the descriptor technique documented by
// pookjw/ClearAndBlurredWidgets and its hook-safety discussion (PR #6).
// No code is injected into SpringBoard; only our own extension reply is changed.

static NSString *const SCClearKind = @"SessionCamera.Clear";
static NSString *const SCBlankKind = @"SessionCamera.Blank";
static NSString *const SCBlurKind = @"SessionCamera.Blur";
static void (*SCOriginalFetch)(id, SEL, void (^)(id));

static BOOL SCSetterAvailable(id object, SEL selector, BOOL booleanArgument) {
    Method method = class_getInstanceMethod([object class], selector);
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    char result[16] = {0}, argument[16] = {0};
    method_getReturnType(method, result, sizeof(result));
    method_getArgumentType(method, 2, argument, sizeof(argument));
    return result[0] == 'v' && (booleanArgument
        ? (argument[0] == 'B' || argument[0] == 'c')
        : (argument[0] == 'Q' || argument[0] == 'q' || argument[0] == 'L' || argument[0] == 'l'));
}

static id SCPatchDescriptor(id descriptor) {
    SEL kindSelector = NSSelectorFromString(@"kind");
    Method kindMethod = class_getInstanceMethod([descriptor class], kindSelector);
    char kindType[16] = {0};
    if (!kindMethod || method_getNumberOfArguments(kindMethod) != 2) return nil;
    method_getReturnType(kindMethod, kindType, sizeof(kindType));
    if (kindType[0] != '@') return nil;
    id kind = ((id (*)(id, SEL))objc_msgSend)(descriptor, kindSelector);
    if (![kind isKindOfClass:NSString.class]) return nil;
    BOOL clear = [kind isEqual:SCClearKind] || [kind isEqual:SCBlankKind];
    BOOL blur = [kind isEqual:SCBlurKind];
    if (!clear && !blur) return nil;
    if (![descriptor respondsToSelector:@selector(mutableCopyWithZone:)]) return nil;
    id mutable = [descriptor mutableCopy];
    SEL removable = NSSelectorFromString(@"setBackgroundRemovable:");
    SEL transparent = NSSelectorFromString(@"setTransparent:");
    SEL style = NSSelectorFromString(@"setPreferredBackgroundStyle:");
    SEL vibrant = NSSelectorFromString(@"setSupportsVibrantContent:");
    if (!SCSetterAvailable(mutable, removable, YES) ||
        !SCSetterAvailable(mutable, transparent, YES) ||
        !SCSetterAvailable(mutable, style, NO) ||
        (blur && !SCSetterAvailable(mutable, vibrant, YES))) return nil;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(mutable, removable, YES);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(mutable, transparent, YES);
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(mutable, style, blur ? 2 : 1);
    if (blur) ((void (*)(id, SEL, BOOL))objc_msgSend)(mutable, vibrant, YES);
    return mutable;
}

// Preserve the three descriptor collections used by the iOS 18 fetch result.
// A changed/unknown schema is rejected and the original result is returned.
@interface SCDescriptorPacket : NSObject <NSSecureCoding>
@property(nonatomic, copy) NSArray *activities;
@property(nonatomic, copy) NSArray *controls;
@property(nonatomic, copy) NSArray *widgets;
@property(nonatomic) BOOL changed;
@end

@implementation SCDescriptorPacket
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (!self) return nil;
    Class base = NSClassFromString(@"CHSBaseDescriptor");
    Class control = NSClassFromString(@"CHSControlDescriptor");
    Class widget = NSClassFromString(@"CHSWidgetDescriptor");
    if (!base || !control || !widget) return nil;
    _activities = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSArray.class, base, nil]
                                       forKey:@"activityDescriptors"];
    _controls = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSArray.class, control, nil]
                                     forKey:@"controlDescriptors"];
    NSArray *original = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSArray.class, widget, nil]
                                             forKey:@"widgetDescriptors"];
    if (coder.error || ![original isKindOfClass:NSArray.class]) return nil;
    NSMutableArray *replacement = [NSMutableArray arrayWithCapacity:original.count];
    for (id descriptor in original) {
        id patched = SCPatchDescriptor(descriptor);
        [replacement addObject:patched ?: descriptor];
        _changed |= patched != nil;
    }
    _widgets = [replacement copy];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.activities forKey:@"activityDescriptors"];
    [coder encodeObject:self.controls forKey:@"controlDescriptors"];
    [coder encodeObject:self.widgets forKey:@"widgetDescriptors"];
}
@end

static NSData *SCEncodeFields(id<NSCoding> value) {
    NSKeyedArchiver *coder = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
    [value encodeWithCoder:coder];
    [coder finishEncoding];
    return coder.error ? nil : coder.encodedData;
}

static NSKeyedUnarchiver *SCDecoder(NSData *data) {
    if (!data) return nil;
    NSError *error = nil;
    NSKeyedUnarchiver *coder = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
    coder.requiresSecureCoding = YES;
    coder.decodingFailurePolicy = NSDecodingFailurePolicySetErrorAndReturn;
    return error ? nil : coder;
}

static id SCTransformFetchResult(id original) {
    if (![original respondsToSelector:@selector(encodeWithCoder:)]) return original;
    @try {
        NSKeyedUnarchiver *input = SCDecoder(SCEncodeFields(original));
        if (!input) return original;
        SCDescriptorPacket *packet = [[SCDescriptorPacket alloc] initWithCoder:input];
        if (!packet || input.error || !packet.changed) return original;
        Class resultClass = NSClassFromString(@"_TtC9WidgetKit21DescriptorFetchResult");
        if (!resultClass || !class_getInstanceMethod(resultClass, @selector(initWithCoder:))) return original;
        NSKeyedUnarchiver *output = SCDecoder(SCEncodeFields(packet));
        if (!output) return original;
        // Normal Objective-C initializer dispatch preserves ARC ownership.
        id rebuilt = [[resultClass alloc] initWithCoder:output];
        if (!rebuilt || output.error) return original;
        NSLog(@"[SessionWidgetHook] patched descriptor result");
        return rebuilt;
    } @catch (NSException *exception) {
        NSLog(@"[SessionWidgetHook] retained original result (%@: %@)", exception.name, exception.reason);
        return original;
    }
}

static void SCFetchDescriptors(id receiver, SEL selector, void (^completion)(id)) {
    if (!completion) {
        SCOriginalFetch(receiver, selector, completion);
        return;
    }
    SCOriginalFetch(receiver, selector, ^(id original) {
        // Call the client's completion exactly once, outside the patch's catch.
        id result = SCTransformFetchResult(original);
        completion(result);
    });
}

@interface SCWidgetHookBootstrap : NSObject
@end
@implementation SCWidgetHookBootstrap
+ (void)load {
#if TARGET_OS_IOS
    SCInstallWidgetBackgroundHook();
    // WidgetKit's private export class can load after this object file.
    for (int attempt = 1; attempt <= 8; attempt++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, attempt * NSEC_PER_SEC / 4),
                       dispatch_get_main_queue(), ^{ SCInstallWidgetBackgroundHook(); });
    }
#endif
}
@end

BOOL SCInstallWidgetBackgroundHook(void) {
#if TARGET_OS_IOS
    // The three-field schema is researched for iOS 18; later systems fall back.
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 18) return NO;
#endif
    @synchronized(SCWidgetHookBootstrap.class) {
        if (SCOriginalFetch) return YES;
        Class exported = NSClassFromString(@"_TtCC9WidgetKit24WidgetExtensionXPCServer14ExportedObject");
        SEL selector = NSSelectorFromString(@"getAllCurrentDescriptorsWithCompletion:");
        Method method = exported ? class_getInstanceMethod(exported, selector) : NULL;
        if (!method || method_getNumberOfArguments(method) != 3) return NO;
        char result[16] = {0}, argument[16] = {0};
        method_getReturnType(method, result, sizeof(result));
        method_getArgumentType(method, 2, argument, sizeof(argument));
        if (result[0] != 'v' || argument[0] != '@') return NO;
        IMP implementation = method_getImplementation(method);
        if (!implementation) return NO;
        SCOriginalFetch = (void (*)(id, SEL, void (^)(id)))implementation;
        // If inherited, add on the export class instead of modifying its parent.
        if (!class_addMethod(exported, selector, (IMP)SCFetchDescriptors, method_getTypeEncoding(method))) {
            method_setImplementation(method, (IMP)SCFetchDescriptors);
        }
        NSLog(@"[SessionWidgetHook] installed iOS 18 descriptor hook");
        return YES;
    }
}
