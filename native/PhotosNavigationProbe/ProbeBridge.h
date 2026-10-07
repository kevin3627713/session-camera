#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
NSDictionary *PNInspectURL(NSURL *url);
NSDictionary *PNWorkspaceDispatch(NSURL *url, BOOL sensitive);
void PNDispatchThroughShare(NSURL *url, BOOL sensitive, void (^completion)(NSDictionary *result));
void PNFrontBoardDispatch(NSURL *url, NSString *callerContext, void (^completion)(NSDictionary *result));
void PNDispatchFrontBoardThroughShare(NSURL *url, void (^completion)(NSDictionary *result));
void PNShortcutRunnerDispatch(NSURL *url, NSString *shortcutName, NSString *callerContext, void (^completion)(NSDictionary *result));
void PNDispatchShortcutRunnerThroughShare(NSURL *url, NSString *shortcutName, void (^completion)(NSDictionary *result));
NS_ASSUME_NONNULL_END
