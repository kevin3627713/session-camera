#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
NSDictionary *PNInspectURL(NSURL *url);
NSDictionary *PNWorkspaceDispatch(NSURL *url, BOOL sensitive);
void PNDispatchThroughShare(NSURL *url, BOOL sensitive, void (^completion)(NSDictionary *result));
NS_ASSUME_NONNULL_END
