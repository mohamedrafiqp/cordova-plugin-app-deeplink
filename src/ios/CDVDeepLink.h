#import <Cordova/CDV.h>

@interface CDVDeepLink : CDVPlugin

/**
 * Stores the URL captured before the plugin (or JavaScript) was ready.
 * Delivered as soon as JS subscribes, and only if it matches the
 * DeepLinkHost / DeepLinkPathPrefix values from the app config.xml.
 */
+ (void)capturePendingURLString:(NSString *)urlString;

@end
