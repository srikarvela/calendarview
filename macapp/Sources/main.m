//
//  CalendarView — a standalone macOS menu bar app.
//
//  Launch → sign in with Google → your calendar, fullscreen.
//  There is no server: the app runs the OAuth flow itself, keeps the refresh
//  token in the Keychain, talks to the Google Calendar API directly, and
//  renders the result with a bundled React UI inside a WKWebView.
//
//  Plain AppKit + WebKit so it builds with nothing but the Command Line
//  Tools, for both Apple Silicon and Intel.
//

#import <AppKit/AppKit.h>
#import <AuthenticationServices/AuthenticationServices.h>
#import <CommonCrypto/CommonDigest.h>
#import <ServiceManagement/ServiceManagement.h>
#import <WebKit/WebKit.h>

#pragma mark - Small helpers

static NSString *const kKeychainService = @"com.calendarview.app";
static NSString *const kRefreshTokenAccount = @"google-refresh-token";
static NSString *const kAccountEmailKey = @"accountEmail";
static NSString *const kFullscreenKey = @"openFullscreen";

static const NSTimeInterval kSyncInterval = 300.0;  // 5 minutes

static NSColor *VoidColor(void) {
    return [NSColor colorWithSRGBRed:0.024 green:0.027 blue:0.039 alpha:1.0];
}

static NSString *const kClientIDOverrideKey = @"googleClientID";

/// The OAuth client. Normally baked in at build time (see macapp/build.sh) so
/// nobody is ever asked to paste anything; a build without one falls back to
/// asking once and remembering the answer.
static NSString *GoogleClientID(void) {
    NSString *baked = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"GoogleClientID"];
    if (baked.length > 0) return baked;
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kClientIDOverrideKey];
    return saved.length > 0 ? saved : nil;
}

/// Google's convention for installed apps: the client ID, reversed.
/// 123-abc.apps.googleusercontent.com → com.googleusercontent.apps.123-abc
static NSString *RedirectScheme(NSString *clientID) {
    NSString *suffix = @".apps.googleusercontent.com";
    if (![clientID hasSuffix:suffix]) return nil;
    NSString *stem = [clientID substringToIndex:clientID.length - suffix.length];
    return [NSString stringWithFormat:@"com.googleusercontent.apps.%@", stem];
}

static NSString *Base64URL(NSData *data) {
    NSString *s = [data base64EncodedStringWithOptions:0];
    s = [s stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    s = [s stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return [s stringByReplacingOccurrencesOfString:@"=" withString:@""];
}

static NSString *RandomVerifier(void) {
    uint8_t bytes[32];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) {
        for (size_t i = 0; i < sizeof(bytes); i++) bytes[i] = (uint8_t)arc4random_uniform(256);
    }
    return Base64URL([NSData dataWithBytes:bytes length:sizeof(bytes)]);
}

static NSString *S256Challenge(NSString *verifier) {
    NSData *data = [verifier dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return Base64URL([NSData dataWithBytes:digest length:sizeof(digest)]);
}

static NSString *FormEncode(NSDictionary<NSString *, NSString *> *params) {
    NSMutableArray *parts = [NSMutableArray array];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                               @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    [params enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        [parts addObject:[NSString stringWithFormat:@"%@=%@",
                          [k stringByAddingPercentEncodingWithAllowedCharacters:allowed],
                          [v stringByAddingPercentEncodingWithAllowedCharacters:allowed]]];
    }];
    return [parts componentsJoinedByString:@"&"];
}

#pragma mark - Keychain

static void KeychainSet(NSString *account, NSString *value) {
    NSDictionary *query = @{
        (id)kSecClass : (id)kSecClassGenericPassword,
        (id)kSecAttrService : kKeychainService,
        (id)kSecAttrAccount : account,
    };
    SecItemDelete((__bridge CFDictionaryRef)query);
    if (value.length == 0) return;

    NSMutableDictionary *item = [query mutableCopy];
    item[(id)kSecValueData] = [value dataUsingEncoding:NSUTF8StringEncoding];
    item[(id)kSecAttrAccessible] = (id)kSecAttrAccessibleAfterFirstUnlock;
    SecItemAdd((__bridge CFDictionaryRef)item, NULL);
}

static NSString *KeychainGet(NSString *account) {
    NSDictionary *query = @{
        (id)kSecClass : (id)kSecClassGenericPassword,
        (id)kSecAttrService : kKeychainService,
        (id)kSecAttrAccount : account,
        (id)kSecReturnData : @YES,
        (id)kSecMatchLimit : (id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess) return nil;
    NSData *data = CFBridgingRelease(result);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

#pragma mark - Google Calendar

/// Google's palette, tuned for a dark display. Mirrors src/app/api/events.
static NSDictionary<NSString *, NSString *> *ColorMap(void) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"1" : @"#8ab4f8", @"2" : @"#7ddba3", @"3" : @"#c58af9", @"4" : @"#ff8a80",
            @"5" : @"#fdd663", @"6" : @"#ffa76a", @"7" : @"#78d9ec", @"8" : @"#9aa0a6",
            @"9" : @"#7a9dfb", @"10" : @"#81c995", @"11" : @"#f28b82",
        };
    });
    return map;
}

@interface CalendarSync : NSObject
@end

@implementation CalendarSync

+ (void)requestJSON:(NSURL *)url
              token:(NSString *)token
         completion:(void (^)(id json, NSInteger status, NSError *error))completion {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    req.timeoutInterval = 30;

    [[[NSURLSession sharedSession]
        dataTaskWithRequest:req
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
              NSInteger status = [(NSHTTPURLResponse *)response statusCode];
              if (error) {
                  completion(nil, status, error);
                  return;
              }
              id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
              completion(json, status, nil);
          }] resume];
}

/// Every event, from every selected calendar, between now-12h and now+8d.
+ (void)fetchEventsWithToken:(NSString *)token
                  completion:(void (^)(NSArray *events, NSInteger status, NSError *error))completion {
    NSURL *listURL = [NSURL URLWithString:@"https://www.googleapis.com/calendar/v3/users/me/calendarList"];

    [self requestJSON:listURL
                token:token
           completion:^(id json, NSInteger status, NSError *error) {
        if (error || status != 200) {
            completion(nil, status, error);
            return;
        }

        NSArray *items = json[@"items"];
        if (![items isKindOfClass:NSArray.class]) items = @[];

        NSDateFormatter *iso = [[NSDateFormatter alloc] init];
        iso.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        iso.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        iso.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        NSString *timeMin = [iso stringFromDate:[NSDate dateWithTimeIntervalSinceNow:-12 * 3600]];
        NSString *timeMax = [iso stringFromDate:[NSDate dateWithTimeIntervalSinceNow:8 * 24 * 3600]];

        NSMutableArray *collected = [NSMutableArray array];
        NSLock *lock = [[NSLock alloc] init];
        dispatch_group_t group = dispatch_group_create();
        __block NSInteger worstStatus = 200;

        for (NSDictionary *cal in items) {
            if (![cal isKindOfClass:NSDictionary.class]) continue;
            if ([cal[@"selected"] isKindOfClass:NSNumber.class] && ![cal[@"selected"] boolValue]) {
                continue;  // Unchecked in Google Calendar — respect that here too.
            }

            NSString *calID = cal[@"id"];
            if (calID.length == 0) continue;

            NSString *calColor = ColorMap()[cal[@"colorId"] ?: @""] ?: cal[@"backgroundColor"] ?: @"#8ab4f8";
            NSString *calName = cal[@"summary"] ?: calID;

            dispatch_group_enter(group);
            [self fetchPageForCalendar:calID
                                 token:token
                               timeMin:timeMin
                               timeMax:timeMax
                             pageToken:nil
                              accumulated:[NSMutableArray array]
                            completion:^(NSArray *raw, NSInteger pageStatus) {
                if (pageStatus != 200) worstStatus = MAX(worstStatus, pageStatus);

                NSMutableArray *mapped = [NSMutableArray array];
                for (NSDictionary *e in raw) {
                    NSDictionary *normalized = [self normalize:e
                                                     calendar:calName
                                                        calID:calID
                                                        color:calColor];
                    if (normalized) [mapped addObject:normalized];
                }
                [lock lock];
                [collected addObjectsFromArray:mapped];
                [lock unlock];
                dispatch_group_leave(group);
            }];
        }

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            [collected sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                return [a[@"start"] compare:b[@"start"]];
            }];
            completion(collected, 200, nil);
        });
    }];
}

/// Pages through one calendar so a busy week is never silently truncated.
+ (void)fetchPageForCalendar:(NSString *)calID
                       token:(NSString *)token
                     timeMin:(NSString *)timeMin
                     timeMax:(NSString *)timeMax
                   pageToken:(NSString *)pageToken
                 accumulated:(NSMutableArray *)accumulated
                  completion:(void (^)(NSArray *items, NSInteger status))completion {
    NSMutableDictionary *params = [@{
        @"timeMin" : timeMin,
        @"timeMax" : timeMax,
        @"singleEvents" : @"true",   // expand recurring events
        @"orderBy" : @"startTime",
        @"maxResults" : @"250",
    } mutableCopy];
    if (pageToken) params[@"pageToken"] = pageToken;

    NSCharacterSet *pathAllowed = [NSCharacterSet URLPathAllowedCharacterSet];
    NSString *encodedID = [calID stringByAddingPercentEncodingWithAllowedCharacters:pathAllowed];
    encodedID = [encodedID stringByReplacingOccurrencesOfString:@"/" withString:@"%2F"];

    NSString *urlString =
        [NSString stringWithFormat:@"https://www.googleapis.com/calendar/v3/calendars/%@/events?%@",
                                   encodedID, FormEncode(params)];

    [self requestJSON:[NSURL URLWithString:urlString]
                token:token
           completion:^(id json, NSInteger status, NSError *error) {
        if (error || status != 200) {
            completion(accumulated, status ?: 500);
            return;
        }
        NSArray *items = json[@"items"];
        if ([items isKindOfClass:NSArray.class]) [accumulated addObjectsFromArray:items];

        NSString *next = json[@"nextPageToken"];
        if ([next isKindOfClass:NSString.class] && next.length > 0 && accumulated.count < 1000) {
            [self fetchPageForCalendar:calID
                                 token:token
                               timeMin:timeMin
                               timeMax:timeMax
                             pageToken:next
                           accumulated:accumulated
                            completion:completion];
        } else {
            completion(accumulated, 200);
        }
    }];
}

/// Google's event shape → the shape the UI expects (src/lib/types.ts).
+ (NSDictionary *)normalize:(NSDictionary *)e
                   calendar:(NSString *)calendarName
                      calID:(NSString *)calID
                      color:(NSString *)calColor {
    if (![e isKindOfClass:NSDictionary.class]) return nil;
    if ([e[@"status"] isEqual:@"cancelled"]) return nil;

    NSDictionary *start = e[@"start"], *end = e[@"end"];
    NSString *startStr = start[@"dateTime"] ?: start[@"date"];
    NSString *endStr = end[@"dateTime"] ?: end[@"date"];
    if (startStr.length == 0 || endStr.length == 0) return nil;

    BOOL allDay = start[@"dateTime"] == nil;

    NSArray *attendees = [e[@"attendees"] isKindOfClass:NSArray.class] ? e[@"attendees"] : @[];
    BOOL declined = NO;
    for (NSDictionary *a in attendees) {
        if ([a[@"self"] boolValue] && [a[@"responseStatus"] isEqual:@"declined"]) declined = YES;
    }
    if (declined) return nil;

    NSString *color = ColorMap()[e[@"colorId"] ?: @""] ?: calColor;
    NSString *title = [e[@"summary"] isKindOfClass:NSString.class]
                          ? [e[@"summary"] stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceAndNewlineCharacterSet]]
                          : @"";

    NSMutableDictionary *out = [@{
        @"id" : [NSString stringWithFormat:@"%@:%@", calID, e[@"id"] ?: @""],
        @"title" : title.length > 0 ? title : @"(no title)",
        @"start" : startStr,
        @"end" : endStr,
        @"allDay" : @(allDay),
        @"attendees" : @(attendees.count),
        @"color" : color,
        @"calendar" : calendarName,
        @"declined" : @NO,
    } mutableCopy];

    if ([e[@"location"] isKindOfClass:NSString.class]) out[@"location"] = e[@"location"];
    if ([e[@"hangoutLink"] isKindOfClass:NSString.class]) out[@"meetLink"] = e[@"hangoutLink"];
    return out;
}

@end

#pragma mark - App

@interface AppDelegate : NSObject <NSApplicationDelegate, WKScriptMessageHandler, NSWindowDelegate,
                                   ASWebAuthenticationPresentationContextProviding>
@end

@implementation AppDelegate {
    NSStatusItem *_statusItem;
    NSWindow *_window;
    WKWebView *_webView;
    ASWebAuthenticationSession *_authSession;

    NSTimer *_dayTimer;
    NSTimer *_syncTimer;
    NSInteger _shownDay;

    NSString *_accessToken;
    NSDate *_accessTokenExpiry;
    NSString *_codeVerifier;

    NSArray *_events;
    NSString *_phase;   // loading | signedOut | ready | error
    NSString *_error;
    BOOL _stale;
    BOOL _webReady;
}

#pragma mark Lifecycle

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    _shownDay = -1;
    _events = @[];
    _phase = @"loading";

    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.toolTip = @"CalendarView";
    [self refreshStatusIcon];
    _statusItem.menu = [self buildMenu];

    _dayTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
                                                repeats:YES
                                                  block:^(NSTimer *t) { [self refreshStatusIcon]; }];

    [self buildWebView];
    [self showWindow];

    // Signed in last time? Pick up where we left off, no prompting.
    if (KeychainGet(kRefreshTokenAccount).length > 0) {
        [self syncNow];
    } else {
        [self setPhase:@"signedOut" error:nil];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;  // It lives in the menu bar.
}

#pragma mark Menu bar

/// A small calendar page showing today's date, as a template image so macOS
/// tints it for light and dark menu bars.
- (NSImage *)statusImageForDay:(NSInteger)day {
    NSSize size = NSMakeSize(19, 17);
    NSImage *image = [NSImage imageWithSize:size
                                    flipped:NO
                             drawingHandler:^BOOL(NSRect rect) {
        NSBezierPath *body =
            [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1.25, 0.75, 16.5, 15.0)
                                            xRadius:3.2
                                            yRadius:3.2];
        body.lineWidth = 1.3;
        [[NSColor blackColor] setStroke];
        [body stroke];

        [[NSColor blackColor] setFill];
        for (CGFloat x = 6.0; x <= 13.0; x += 7.0) NSRectFill(NSMakeRect(x - 0.65, 14.6, 1.3, 2.0));

        NSString *text = [NSString stringWithFormat:@"%ld", (long)day];
        NSDictionary *attrs = @{
            NSFontAttributeName : [NSFont systemFontOfSize:(day > 9 ? 8.5 : 9.5)
                                                    weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName : [NSColor blackColor],
        };
        NSSize bounds = [text sizeWithAttributes:attrs];
        [text drawAtPoint:NSMakePoint((size.width - bounds.width) / 2.0, 3.0) withAttributes:attrs];
        return YES;
    }];
    image.template = YES;
    return image;
}

- (void)refreshStatusIcon {
    NSInteger day = [[NSCalendar currentCalendar] component:NSCalendarUnitDay fromDate:[NSDate date]];
    if (day == _shownDay) return;
    _shownDay = day;
    _statusItem.button.image = [self statusImageForDay:day];
}

- (NSMenu *)buildMenu {
    NSMenu *menu = [[NSMenu alloc] init];

    [[menu addItemWithTitle:@"Open CalendarView" action:@selector(showWindow) keyEquivalent:@"o"]
        setTarget:self];
    [[menu addItemWithTitle:@"Sync Now" action:@selector(syncNow) keyEquivalent:@"r"] setTarget:self];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *fs = [menu addItemWithTitle:@"Open in Fullscreen"
                                     action:@selector(toggleFullscreenPref:)
                              keyEquivalent:@""];
    fs.target = self;
    fs.state = [self openFullscreen] ? NSControlStateValueOn : NSControlStateValueOff;

    if (@available(macOS 13.0, *)) {
        NSMenuItem *login = [menu addItemWithTitle:@"Launch at Login"
                                            action:@selector(toggleLaunchAtLogin:)
                                     keyEquivalent:@""];
        login.target = self;
        login.state = SMAppService.mainAppService.status == SMAppServiceStatusEnabled
                          ? NSControlStateValueOn
                          : NSControlStateValueOff;
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *account = [menu addItemWithTitle:@"Sign Out"
                                          action:@selector(signOut)
                                   keyEquivalent:@""];
    account.target = self;

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit CalendarView" action:@selector(terminate:) keyEquivalent:@"q"];

    return menu;
}

- (BOOL)openFullscreen {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d objectForKey:kFullscreenKey] == nil) return YES;
    return [d boolForKey:kFullscreenKey];
}

- (void)toggleFullscreenPref:(NSMenuItem *)sender {
    BOOL next = ![self openFullscreen];
    [[NSUserDefaults standardUserDefaults] setBool:next forKey:kFullscreenKey];
    sender.state = next ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)toggleLaunchAtLogin:(NSMenuItem *)sender {
    if (@available(macOS 13.0, *)) {
        NSError *error = nil;
        BOOL enabled = SMAppService.mainAppService.status == SMAppServiceStatusEnabled;
        BOOL ok = enabled ? [SMAppService.mainAppService unregisterAndReturnError:&error]
                          : [SMAppService.mainAppService registerAndReturnError:&error];
        if (ok) {
            sender.state = enabled ? NSControlStateValueOff : NSControlStateValueOn;
        } else {
            NSBeep();
        }
    }
}

#pragma mark Window and web view

- (void)buildWebView {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *content = [[WKUserContentController alloc] init];
    [content addScriptMessageHandler:self name:@"calendarview"];
    config.userContentController = content;

    _webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:config];
    _webView.allowsBackForwardNavigationGestures = NO;
    if (@available(macOS 12.0, *)) _webView.underPageBackgroundColor = VoidColor();

    NSURL *index = [[NSBundle mainBundle] URLForResource:@"index"
                                           withExtension:@"html"
                                            subdirectory:@"web"];
    if (index) {
        [_webView loadFileURL:index allowingReadAccessToURL:[index URLByDeletingLastPathComponent]];
    }
}

- (void)showWindow {
    if (!_window) {
        NSRect frame = [NSScreen mainScreen] ? [NSScreen mainScreen].visibleFrame
                                            : NSMakeRect(0, 0, 1440, 900);
        _window = [[NSWindow alloc]
            initWithContentRect:frame
                      styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                 NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
                                 NSWindowStyleMaskFullSizeContentView)
                        backing:NSBackingStoreBuffered
                          defer:NO];
        _window.title = @"CalendarView";
        _window.titleVisibility = NSWindowTitleHidden;
        _window.titlebarAppearsTransparent = YES;
        _window.backgroundColor = VoidColor();
        _window.movableByWindowBackground = YES;
        _window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
        _window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        _window.delegate = self;
        _window.releasedWhenClosed = NO;

        _webView.frame = _window.contentLayoutRect;
        _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _window.contentView = _webView;
    }

    [NSApp activateIgnoringOtherApps:YES];
    [_window makeKeyAndOrderFront:nil];

    if ([self openFullscreen] && !(_window.styleMask & NSWindowStyleMaskFullScreen)) {
        [_window toggleFullScreen:nil];
    }
}

- (void)windowWillClose:(NSNotification *)note {
    _window = nil;
}

#pragma mark Bridge

- (void)userContentController:(WKUserContentController *)controller
      didReceiveScriptMessage:(WKScriptMessage *)message {
    NSString *type = [message.body isKindOfClass:NSDictionary.class] ? message.body[@"type"] : nil;

    if ([type isEqualToString:@"ready"]) {
        _webReady = YES;
        [self pushSnapshot];
    } else if ([type isEqualToString:@"signIn"]) {
        [self signIn];
    } else if ([type isEqualToString:@"signOut"]) {
        [self signOut];
    } else if ([type isEqualToString:@"refresh"]) {
        [self syncNow];
    }
}

- (void)setPhase:(NSString *)phase error:(NSString *)error {
    _phase = phase;
    _error = error;
    [self pushSnapshot];
}

- (void)pushSnapshot {
    if (!_webReady) return;

    NSMutableDictionary *snapshot = [@{
        @"phase" : _phase ?: @"loading",
        @"events" : _events ?: @[],
        @"stale" : @(_stale),
    } mutableCopy];

    NSString *email = [[NSUserDefaults standardUserDefaults] stringForKey:kAccountEmailKey];
    if (email) snapshot[@"account"] = email;
    if (_error) snapshot[@"error"] = _error;

    NSData *json = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
    if (!json) return;
    NSString *literal = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];

    NSString *script =
        [NSString stringWithFormat:@"window.__calendarview_push && window.__calendarview_push(%@);",
                                   literal];
    [_webView evaluateJavaScript:script completionHandler:nil];
}

#pragma mark Sign in

- (NSWindow *)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
    return _window ?: NSApp.windows.firstObject;
}

- (void)signIn {
    NSString *clientID = GoogleClientID();
    NSString *scheme = RedirectScheme(clientID);

    if (!clientID || !scheme) {
        clientID = [self askForClientID];
        scheme = RedirectScheme(clientID);
        if (!clientID || !scheme) {
            [self setPhase:@"signedOut" error:nil];
            return;
        }
        [[NSUserDefaults standardUserDefaults] setObject:clientID forKey:kClientIDOverrideKey];
    }

    _codeVerifier = RandomVerifier();
    NSString *redirect = [NSString stringWithFormat:@"%@:/oauth2redirect", scheme];

    NSString *query = FormEncode(@{
        @"client_id" : clientID,
        @"redirect_uri" : redirect,
        @"response_type" : @"code",
        @"scope" : @"openid email https://www.googleapis.com/auth/calendar.readonly",
        @"code_challenge" : S256Challenge(_codeVerifier),
        @"code_challenge_method" : @"S256",
        @"prompt" : @"consent",
    });
    NSURL *authURL = [NSURL URLWithString:
        [NSString stringWithFormat:@"https://accounts.google.com/o/oauth2/v2/auth?%@", query]];

    [self setPhase:@"loading" error:nil];

    __weak typeof(self) weakSelf = self;
    _authSession = [[ASWebAuthenticationSession alloc]
             initWithURL:authURL
       callbackURLScheme:scheme
       completionHandler:^(NSURL *callbackURL, NSError *error) {
           typeof(self) self_ = weakSelf;
           if (!self_) return;

           if (error || !callbackURL) {
               BOOL cancelled = error.code == ASWebAuthenticationSessionErrorCodeCanceledLogin;
               [self_ setPhase:@"signedOut"
                         error:cancelled ? nil : error.localizedDescription];
               return;
           }

           NSURLComponents *comps = [NSURLComponents componentsWithURL:callbackURL
                                               resolvingAgainstBaseURL:NO];
           NSString *code = nil;
           for (NSURLQueryItem *item in comps.queryItems) {
               if ([item.name isEqualToString:@"code"]) code = item.value;
           }
           if (code.length == 0) {
               [self_ setPhase:@"error" error:@"Google did not return an authorization code."];
               return;
           }
           [self_ exchangeCode:code redirect:redirect clientID:clientID];
       }];

    // Reuse the Safari session so an already signed-in Google account is one click.
    _authSession.prefersEphemeralWebBrowserSession = NO;
    _authSession.presentationContextProvider = self;

    if (![_authSession start]) {
        [self setPhase:@"error" error:@"Could not open the Google sign-in window."];
    }
}

/// Only reached by a build with no client ID compiled in.
- (NSString *)askForClientID {
    [NSApp activateIgnoringOtherApps:YES];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"One-time setup";
    alert.informativeText =
        @"This copy of CalendarView was built without a Google OAuth client, so it needs "
        @"yours once. Create an iOS-type OAuth client in the Google Cloud Console and paste "
        @"the client ID here — CalendarView will remember it.";

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 360, 24)];
    field.placeholderString = @"…apps.googleusercontent.com";
    alert.accessoryView = field;
    [alert addButtonWithTitle:@"Continue"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Open Instructions"];
    alert.window.initialFirstResponder = field;

    NSModalResponse response = [alert runModal];
    if (response == NSAlertThirdButtonReturn) {
        [[NSWorkspace sharedWorkspace]
            openURL:[NSURL URLWithString:
                @"https://github.com/srikarvela/calendarview#set-up-google-sign-in-once"]];
        return nil;
    }
    if (response != NSAlertFirstButtonReturn) return nil;

    NSString *value = [field.stringValue
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return value.length > 0 ? value : nil;
}

- (void)exchangeCode:(NSString *)code redirect:(NSString *)redirect clientID:(NSString *)clientID {
    NSDictionary *body = @{
        @"client_id" : clientID,
        @"code" : code,
        @"code_verifier" : _codeVerifier ?: @"",
        @"grant_type" : @"authorization_code",
        @"redirect_uri" : redirect,
    };

    [self postToken:body completion:^(NSDictionary *json, NSString *error) {
        if (error) {
            [self setPhase:@"error" error:error];
            return;
        }
        NSString *refresh = json[@"refresh_token"];
        if (refresh.length > 0) KeychainSet(kRefreshTokenAccount, refresh);
        [self adoptAccessToken:json];
        [self fetchAccountEmail];
        [self syncNow];
    }];
}

- (void)signOut {
    KeychainSet(kRefreshTokenAccount, nil);
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kAccountEmailKey];
    _accessToken = nil;
    _accessTokenExpiry = nil;
    _events = @[];
    _stale = NO;
    [self setPhase:@"signedOut" error:nil];
}

- (void)adoptAccessToken:(NSDictionary *)json {
    _accessToken = json[@"access_token"];
    NSNumber *expiresIn = json[@"expires_in"];
    _accessTokenExpiry = [NSDate dateWithTimeIntervalSinceNow:expiresIn.doubleValue ?: 3600];
}

- (void)postToken:(NSDictionary *)body
       completion:(void (^)(NSDictionary *json, NSString *error))completion {
    NSMutableURLRequest *req =
        [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://oauth2.googleapis.com/token"]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [FormEncode(body) dataUsingEncoding:NSUTF8StringEncoding];
    req.timeoutInterval = 30;

    [[[NSURLSession sharedSession]
        dataTaskWithRequest:req
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
              dispatch_async(dispatch_get_main_queue(), ^{
                  if (error) {
                      completion(nil, error.localizedDescription);
                      return;
                  }
                  NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data
                                                                              options:0
                                                                                error:nil]
                                            : nil;
                  if (![json isKindOfClass:NSDictionary.class]) {
                      completion(nil, @"Google returned an unreadable response.");
                      return;
                  }
                  if (json[@"error"]) {
                      NSString *detail = json[@"error_description"] ?: json[@"error"];
                      completion(nil, detail);
                      return;
                  }
                  completion(json, nil);
              });
          }] resume];
}

/// Whose calendar this is — shown nowhere prominent, but useful in the menu.
- (void)fetchAccountEmail {
    if (_accessToken.length == 0) return;
    [CalendarSync requestJSON:[NSURL URLWithString:@"https://www.googleapis.com/oauth2/v3/userinfo"]
                        token:_accessToken
                   completion:^(id json, NSInteger status, NSError *error) {
        NSString *email = [json isKindOfClass:NSDictionary.class] ? json[@"email"] : nil;
        if (email.length == 0) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSUserDefaults standardUserDefaults] setObject:email forKey:kAccountEmailKey];
            [self pushSnapshot];
        });
    }];
}

#pragma mark Sync

/// Runs the access token forward if needed, then hands it to `block`.
- (void)withFreshToken:(void (^)(NSString *token, NSString *error))block {
    if (_accessToken.length > 0 && _accessTokenExpiry &&
        [_accessTokenExpiry timeIntervalSinceNow] > 60) {
        block(_accessToken, nil);
        return;
    }

    NSString *refresh = KeychainGet(kRefreshTokenAccount);
    NSString *clientID = GoogleClientID();
    if (refresh.length == 0 || clientID.length == 0) {
        block(nil, @"signedOut");
        return;
    }

    [self postToken:@{
        @"client_id" : clientID,
        @"refresh_token" : refresh,
        @"grant_type" : @"refresh_token",
    }
         completion:^(NSDictionary *json, NSString *error) {
        if (error) {
            // A revoked or expired grant means the session is genuinely gone.
            block(nil, @"signedOut");
            return;
        }
        [self adoptAccessToken:json];
        block(self->_accessToken, nil);
    }];
}

- (void)syncNow {
    [self scheduleSyncTimer];

    if (KeychainGet(kRefreshTokenAccount).length == 0) {
        [self setPhase:@"signedOut" error:nil];
        return;
    }

    if (_events.count == 0) [self setPhase:@"loading" error:nil];

    [self withFreshToken:^(NSString *token, NSString *error) {
        if (!token) {
            if ([error isEqualToString:@"signedOut"]) {
                [self signOut];
            } else {
                [self setPhase:@"error" error:error];
            }
            return;
        }

        [CalendarSync fetchEventsWithToken:token
                                completion:^(NSArray *events, NSInteger status, NSError *fetchError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (fetchError || !events) {
                    // Keep showing what we have; just flag it as not fresh.
                    self->_stale = YES;
                    if (self->_events.count == 0) {
                        [self setPhase:@"error"
                                 error:fetchError.localizedDescription
                                           ?: @"Could not reach Google Calendar."];
                    } else {
                        [self pushSnapshot];
                    }
                    return;
                }
                self->_events = events;
                self->_stale = NO;
                [self setPhase:@"ready" error:nil];
            });
        }];
    }];
}

- (void)scheduleSyncTimer {
    [_syncTimer invalidate];
    _syncTimer = [NSTimer scheduledTimerWithTimeInterval:kSyncInterval
                                                 repeats:YES
                                                   block:^(NSTimer *t) { [self syncNow]; }];
}

@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
