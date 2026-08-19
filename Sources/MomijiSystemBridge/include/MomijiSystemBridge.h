#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL MJCursorBridgeIsAvailable(void);
FOUNDATION_EXPORT NSString *MJCursorBridgeUnavailableReason(void);

FOUNDATION_EXPORT BOOL MJCursorBridgeBeginTheme(NSError **error);
FOUNDATION_EXPORT BOOL MJCursorBridgeRegister(
    NSString *identifier,
    NSArray *images,
    CGSize cursorSize,
    CGPoint hotspot,
    NSUInteger frameCount,
    NSTimeInterval frameDuration,
    NSError **error
);
FOUNDATION_EXPORT void MJCursorBridgeFinishTheme(void);
FOUNDATION_EXPORT BOOL MJCursorBridgeRestoreDefaults(NSError **error);

NS_ASSUME_NONNULL_END
