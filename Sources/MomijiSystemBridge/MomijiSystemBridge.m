#import "MomijiSystemBridge.h"
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>

typedef int32_t MJCGSConnectionID;
typedef MJCGSConnectionID (*MJMainConnectionFunction)(void);
typedef CGError (*MJRegisterFunction)(
    MJCGSConnectionID,
    char *,
    bool,
    bool,
    CGSize,
    CGPoint,
    NSUInteger,
    CGFloat,
    CFArrayRef,
    int *
);
typedef CGError (*MJSetRegisteredFunction)(MJCGSConnectionID, char *, int *);
typedef CGError (*MJUnregisterAllFunction)(MJCGSConnectionID);
typedef CGError (*MJCoreCursorSetFunction)(MJCGSConnectionID, int);
typedef CGError (*MJSetSystemCursorFunction)(MJCGSConnectionID, int);
typedef void (*MJSetDockOverrideFunction)(MJCGSConnectionID, bool);

static MJMainConnectionFunction MJMainConnection;
static MJRegisterFunction MJRegister;
static MJSetRegisteredFunction MJSetRegistered;
static MJUnregisterAllFunction MJUnregisterAll;
static MJCoreCursorSetFunction MJCoreCursorSet;
static MJSetSystemCursorFunction MJSetSystemCursor;
static MJSetDockOverrideFunction MJSetDockOverride;
static dispatch_once_t MJLoadOnce;

static void MJLoadSymbols(void) {
    dispatch_once(&MJLoadOnce, ^{
        dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW | RTLD_LOCAL);
        dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW | RTLD_LOCAL);
        MJMainConnection = (MJMainConnectionFunction)dlsym(RTLD_DEFAULT, "CGSMainConnectionID");
        MJRegister = (MJRegisterFunction)dlsym(RTLD_DEFAULT, "CGSRegisterCursorWithImages");
        MJSetRegistered = (MJSetRegisteredFunction)dlsym(RTLD_DEFAULT, "CGSSetRegisteredCursor");
        MJUnregisterAll = (MJUnregisterAllFunction)dlsym(RTLD_DEFAULT, "CoreCursorUnregisterAll");
        MJCoreCursorSet = (MJCoreCursorSetFunction)dlsym(RTLD_DEFAULT, "CoreCursorSet");
        MJSetSystemCursor = (MJSetSystemCursorFunction)dlsym(RTLD_DEFAULT, "CGSSetSystemDefinedCursor");
        MJSetDockOverride = (MJSetDockOverrideFunction)dlsym(RTLD_DEFAULT, "CGSSetDockCursorOverride");
    });
}

static NSError *MJError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"app.momiji.system-cursor"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

BOOL MJCursorBridgeIsAvailable(void) {
    MJLoadSymbols();
    return MJMainConnection && MJRegister && MJSetRegistered && MJUnregisterAll
        && MJCoreCursorSet && MJSetSystemCursor;
}

NSString *MJCursorBridgeUnavailableReason(void) {
    MJLoadSymbols();
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    if (!MJMainConnection) [missing addObject:@"CGSMainConnectionID"];
    if (!MJRegister) [missing addObject:@"CGSRegisterCursorWithImages"];
    if (!MJSetRegistered) [missing addObject:@"CGSSetRegisteredCursor"];
    if (!MJUnregisterAll) [missing addObject:@"CoreCursorUnregisterAll"];
    if (!MJCoreCursorSet) [missing addObject:@"CoreCursorSet"];
    if (!MJSetSystemCursor) [missing addObject:@"CGSSetSystemDefinedCursor"];
    return missing.count == 0 ? @"Available" : [NSString stringWithFormat:@"Missing runtime symbols: %@", [missing componentsJoinedByString:@", "]];
}

BOOL MJCursorBridgeBeginTheme(NSError **error) {
    if (!MJCursorBridgeIsAvailable()) {
        if (error) *error = MJError(1, MJCursorBridgeUnavailableReason());
        return NO;
    }
    MJCGSConnectionID connection = MJMainConnection();
    CGError result = MJUnregisterAll(connection);
    if (result != kCGErrorSuccess) {
        if (error) *error = MJError(result, [NSString stringWithFormat:@"Could not clear registered cursors (%d).", result]);
        return NO;
    }
    for (int cursor = 0; cursor <= 43; cursor++) {
        MJCoreCursorSet(connection, cursor);
    }
    return YES;
}

BOOL MJCursorBridgeRegister(
    NSString *identifier,
    NSArray *images,
    CGSize cursorSize,
    CGPoint hotspot,
    NSUInteger frameCount,
    NSTimeInterval frameDuration,
    NSError **error
) {
    if (!MJCursorBridgeIsAvailable()) {
        if (error) *error = MJError(1, MJCursorBridgeUnavailableReason());
        return NO;
    }
    if (identifier.length == 0 || images.count == 0 || frameCount == 0 || frameCount > 240) {
        if (error) *error = MJError(2, @"Invalid cursor registration arguments.");
        return NO;
    }
    MJCGSConnectionID connection = MJMainConnection();
    int seed = 0;
    CGError result = MJRegister(
        connection,
        (char *)identifier.UTF8String,
        true,
        true,
        cursorSize,
        hotspot,
        frameCount,
        (CGFloat)frameDuration,
        (__bridge CFArrayRef)images,
        &seed
    );
    if (result != kCGErrorSuccess) {
        if (error) *error = MJError(result, [NSString stringWithFormat:@"Could not register %@ (%d).", identifier, result]);
        return NO;
    }
    int activationSeed = 0;
    result = MJSetRegistered(connection, (char *)identifier.UTF8String, &activationSeed);
    if (result != kCGErrorSuccess) {
        if (error) *error = MJError(result, [NSString stringWithFormat:@"Could not activate %@ (%d).", identifier, result]);
        return NO;
    }
    return YES;
}

void MJCursorBridgeFinishTheme(void) {
    if (!MJCursorBridgeIsAvailable()) return;
    MJCGSConnectionID connection = MJMainConnection();
    if (MJSetDockOverride) MJSetDockOverride(connection, true);
    MJSetSystemCursor(connection, 0);
}

BOOL MJCursorBridgeRestoreDefaults(NSError **error) {
    if (!MJCursorBridgeBeginTheme(error)) return NO;
    MJCursorBridgeFinishTheme();
    return YES;
}
