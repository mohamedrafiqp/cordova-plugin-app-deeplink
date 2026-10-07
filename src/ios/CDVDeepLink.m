#import "CDVDeepLink.h"

#import <Cordova/CDVPluginNotifications.h>
#import <Cordova/CDVSceneDelegate.h>
#import <objc/runtime.h>

static NSString *const kDeepLinkHostPreference = @"DeepLinkHost";
static NSString *const kDeepLinkPathPrefixPreference = @"DeepLinkPathPrefix";

static CDVDeepLink *gDeepLinkPlugin = nil;
static NSString *gPendingURLString = nil;

@interface CDVDeepLink ()

@property (nonatomic, copy) NSString *subscriptionCallbackId;

@end

@implementation CDVDeepLink

#pragma mark - Static pending URL

+ (void)capturePendingURLString:(NSString *)urlString {
    if (urlString.length == 0) {
        return;
    }
    if (gDeepLinkPlugin != nil) {
        [gDeepLinkPlugin deliverURLString:urlString];
    } else {
        gPendingURLString = [urlString copy];
    }
}

#pragma mark - Lifecycle

- (void)pluginInitialize {
    gDeepLinkPlugin = self;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleContinueUserActivity:)
                                                 name:CDVPluginContinueUserActivityNotification
                                               object:nil];
}

- (void)onReset {
    self.subscriptionCallbackId = nil;
}

- (void)dispose {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:CDVPluginContinueUserActivityNotification
                                                  object:nil];
    if (gDeepLinkPlugin == self) {
        gDeepLinkPlugin = nil;
    }
    [super dispose];
}

#pragma mark - Cordova JS interface

- (void)subscribe:(CDVInvokedUrlCommand *)command {
    self.subscriptionCallbackId = command.callbackId;
    if (gPendingURLString != nil) {
        NSString *urlString = gPendingURLString;
        gPendingURLString = nil;
        [self deliverURLString:urlString];
    }
}

#pragma mark - URL delivery

- (void)handleContinueUserActivity:(NSNotification *)notification {
    NSUserActivity *activity = (NSUserActivity *)notification.object;
    if (![activity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
        return;
    }
    [CDVDeepLink capturePendingURLString:activity.webpageURL.absoluteString];
}

- (void)deliverURLString:(NSString *)urlString {
    if (urlString.length == 0 || ![self matchesConfiguredFilter:urlString]) {
        return;
    }
    if (self.subscriptionCallbackId == nil) {
        gPendingURLString = [urlString copy];
        return;
    }
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                messageAsString:urlString];
    result.keepCallback = @YES;
    [self.commandDelegate sendPluginResult:result callbackId:self.subscriptionCallbackId];
}

/**
 * Applies DeepLinkHost / DeepLinkPathPrefix from the app config.xml, so iOS
 * forwards exactly the URLs the Android intent filter would open.
 * A missing host preference disables the host check.
 */
- (BOOL)matchesConfiguredFilter:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        return NO;
    }

    NSDictionary *settings = [self.commandDelegate settings];
    NSString *host = settings[kDeepLinkHostPreference];
    NSString *pathPrefix = settings[kDeepLinkPathPrefixPreference];
    if (pathPrefix.length == 0) {
        pathPrefix = @"/";
    }

    NSString *urlHost = url.host;
    if (host.length > 0 && (urlHost == nil || [host caseInsensitiveCompare:urlHost] != NSOrderedSame)) {
        return NO;
    }

    NSString *path = url.path;
    return path != nil && [path hasPrefix:pathPrefix];
}

@end

#pragma mark - Cold start capture

/**
 * cordova-ios only forwards URL-scheme launches from
 * `scene:willConnectToSession:options:` (via connectionOptions.URLContexts).
 * Universal Links arrive cold start inside connectionOptions.userActivities and
 * are never forwarded by CordovaLib, so the call is intercepted here and the
 * webpage URL is stored until the plugin/JavaScript is ready.
 */
@implementation CDVSceneDelegate (DeepLink)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SEL originalSelector = @selector(scene:willConnectToSession:options:);
        SEL replacementSelector = @selector(deepLink_willConnectToSession:options:);

        Method originalMethod = class_getInstanceMethod(self, originalSelector);
        Method replacementMethod = class_getInstanceMethod(self, replacementSelector);
        if (originalMethod != NULL && replacementMethod != NULL) {
            method_exchangeImplementations(originalMethod, replacementMethod);
        }
    });
}

- (void)deepLink_willConnectToSession:(UIScene *)scene
                               options:(UISceneConnectionOptions *)connectionOptions {
    for (NSUserActivity *activity in connectionOptions.userActivities) {
        if ([activity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] &&
            activity.webpageURL != nil) {
            [CDVDeepLink capturePendingURLString:activity.webpageURL.absoluteString];
        }
    }
    // After the exchange this invokes the original CordovaLib implementation.
    [self deepLink_willConnectToSession:scene options:connectionOptions];
}

@end
