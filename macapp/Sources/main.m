//
//  CalendarView — a menu bar wrapper around the CalendarView web display.
//
//  Deliberately plain AppKit + WebKit so it builds with nothing but the
//  Command Line Tools, for both Apple Silicon and Intel.
//

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <ServiceManagement/ServiceManagement.h>

static NSString *const kServerURLKey = @"serverURL";
static NSString *const kFullscreenKey = @"openFullscreen";

static NSColor *VoidColor(void) {
    return [NSColor colorWithSRGBRed:0.024 green:0.027 blue:0.039 alpha:1.0];
}

static NSString *ServerURL(void) {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kServerURLKey] ?: @"";
}

static void SetServerURL(NSString *value) {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:kServerURLKey];
}

static BOOL OpenFullscreen(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d objectForKey:kFullscreenKey] == nil) return YES;  // fullscreen by default
    return [d boolForKey:kFullscreenKey];
}

static void SetOpenFullscreen(BOOL value) {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:kFullscreenKey];
}

/// A small calendar page showing today's date, drawn as a template image so
/// macOS tints it for light and dark menu bars.
static NSImage *StatusImage(NSInteger day) {
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
        for (CGFloat x = 6.0; x <= 13.0; x += 7.0) {
            NSRectFill(NSMakeRect(x - 0.65, 14.6, 1.3, 2.0));
        }

        NSString *text = [NSString stringWithFormat:@"%ld", (long)day];
        NSDictionary *attrs = @{
            NSFontAttributeName : [NSFont systemFontOfSize:(day > 9 ? 8.5 : 9.5)
                                                    weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName : [NSColor blackColor],
        };
        NSSize bounds = [text sizeWithAttributes:attrs];
        [text drawAtPoint:NSMakePoint((size.width - bounds.width) / 2.0, 3.0)
           withAttributes:attrs];
        return YES;
    }];
    image.template = YES;
    return image;
}

#pragma mark -

@interface AppDelegate : NSObject <NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate,
                                   NSWindowDelegate>
@end

@implementation AppDelegate {
    NSStatusItem *_statusItem;
    NSWindow *_window;
    WKWebView *_webView;
    NSTimer *_dayTimer;
    NSInteger _shownDay;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    _shownDay = -1;

    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.toolTip = @"CalendarView";
    [self refreshStatusIcon];
    _statusItem.menu = [self buildMenu];

    // Keep the menu bar date honest across midnight.
    _dayTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
                                                repeats:YES
                                                  block:^(NSTimer *t) {
                                                      [self refreshStatusIcon];
                                                  }];

    [self buildWebView];

    if (ServerURL().length == 0) {
        [self promptForURLFirstRun:YES];
    } else {
        [self showWindow];
    }
}

- (void)refreshStatusIcon {
    NSInteger day = [[NSCalendar currentCalendar] component:NSCalendarUnitDay fromDate:[NSDate date]];
    if (day == _shownDay) return;
    _shownDay = day;
    _statusItem.button.image = StatusImage(day);
}

- (NSMenu *)buildMenu {
    NSMenu *menu = [[NSMenu alloc] init];

    [[menu addItemWithTitle:@"Open CalendarView" action:@selector(showWindow) keyEquivalent:@"o"]
        setTarget:self];
    [[menu addItemWithTitle:@"Reload" action:@selector(reload) keyEquivalent:@"r"] setTarget:self];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *fs = [menu addItemWithTitle:@"Open in Fullscreen"
                                     action:@selector(toggleFullscreenPref:)
                              keyEquivalent:@""];
    fs.target = self;
    fs.state = OpenFullscreen() ? NSControlStateValueOn : NSControlStateValueOff;

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

    [[menu addItemWithTitle:@"Set Server URL…" action:@selector(editURL) keyEquivalent:@","]
        setTarget:self];
    [[menu addItemWithTitle:@"Open in Browser" action:@selector(openInBrowser) keyEquivalent:@""]
        setTarget:self];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit CalendarView" action:@selector(terminate:) keyEquivalent:@"q"];

    return menu;
}

#pragma mark - Web view

- (void)buildWebView {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    // The default store persists cookies, so the Google session survives relaunch.
    config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];

    _webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:config];
    _webView.navigationDelegate = self;
    _webView.UIDelegate = self;
    _webView.allowsBackForwardNavigationGestures = NO;
    // Google refuses OAuth from anything that identifies as an embedded webview.
    _webView.customUserAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                               @"AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 "
                               @"Safari/605.1.15";

    if (@available(macOS 12.0, *)) {
        _webView.underPageBackgroundColor = VoidColor();
    }
}

- (NSWindow *)makeWindow {
    NSRect frame = [NSScreen mainScreen] ? [NSScreen mainScreen].visibleFrame
                                        : NSMakeRect(0, 0, 1440, 900);

    NSWindow *win = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
                             NSWindowStyleMaskFullSizeContentView)
                    backing:NSBackingStoreBuffered
                      defer:NO];

    win.title = @"CalendarView";
    win.titleVisibility = NSWindowTitleHidden;
    win.titlebarAppearsTransparent = YES;
    win.backgroundColor = VoidColor();
    win.movableByWindowBackground = YES;
    win.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
    win.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    win.delegate = self;
    win.releasedWhenClosed = NO;

    _webView.frame = win.contentLayoutRect;
    _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    win.contentView = _webView;

    return win;
}

#pragma mark - Actions

- (void)showWindow {
    if (ServerURL().length == 0) {
        [self promptForURLFirstRun:YES];
        return;
    }

    if (!_window) {
        _window = [self makeWindow];
        [self load];
    }

    [NSApp activateIgnoringOtherApps:YES];
    [_window makeKeyAndOrderFront:nil];

    if (OpenFullscreen() && !(_window.styleMask & NSWindowStyleMaskFullScreen)) {
        [_window toggleFullScreen:nil];
    }
}

- (void)load {
    NSURL *url = [NSURL URLWithString:ServerURL()];
    if (url) [_webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)reload {
    if (_webView.URL == nil) {
        [self load];
    } else {
        [_webView reload];
    }
}

- (void)toggleFullscreenPref:(NSMenuItem *)sender {
    BOOL next = !OpenFullscreen();
    SetOpenFullscreen(next);
    sender.state = next ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)openInBrowser {
    NSURL *url = [NSURL URLWithString:ServerURL()];
    if (url) [[NSWorkspace sharedWorkspace] openURL:url];
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

- (void)editURL {
    [self promptForURLFirstRun:NO];
}

- (void)promptForURLFirstRun:(BOOL)firstRun {
    [NSApp activateIgnoringOtherApps:YES];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = firstRun ? @"Where is your calendar hosted?" : @"Server URL";
    alert.informativeText = @"Paste the address of your CalendarView deployment — the Vercel "
                            @"URL, or http://localhost:3000 while developing.";

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 24)];
    field.placeholderString = @"https://your-app.vercel.app";
    field.stringValue = ServerURL();
    alert.accessoryView = field;
    [alert addButtonWithTitle:@"Open"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.window.initialFirstResponder = field;

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSString *text = [field.stringValue
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) return;
    if (![text hasPrefix:@"http://"] && ![text hasPrefix:@"https://"]) {
        text = [@"https://" stringByAppendingString:text];
    }
    if (![NSURL URLWithString:text]) {
        NSBeep();
        return;
    }

    SetServerURL(text);
    if (_window) [self load];
    [self showWindow];
}

#pragma mark - Delegates

/// Meet links and anything with target=_blank belong in the real browser.
- (WKWebView *)webView:(WKWebView *)webView
    createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
               forNavigationAction:(WKNavigationAction *)navigationAction
                    windowFeatures:(WKWindowFeatures *)windowFeatures {
    if (navigationAction.request.URL) {
        [[NSWorkspace sharedWorkspace] openURL:navigationAction.request.URL];
    }
    return nil;
}

- (void)webView:(WKWebView *)webView
    didFailNavigation:(WKNavigation *)navigation
            withError:(NSError *)error {
    [self showError:error];
}

- (void)webView:(WKWebView *)webView
    didFailProvisionalNavigation:(WKNavigation *)navigation
                       withError:(NSError *)error {
    [self showError:error];
}

- (void)showError:(NSError *)error {
    // WebKit reports a cancel for ordinary redirects; that isn't a failure.
    if (error.code == NSURLErrorCancelled) return;

    NSString *html = [NSString
        stringWithFormat:
            @"<html><body style=\"margin:0;height:100vh;display:flex;align-items:center;"
            @"justify-content:center;background:#06070a;color:#8b8f98;"
            @"font:300 15px -apple-system,BlinkMacSystemFont,sans-serif;text-align:center\">"
            @"<div><div style=\"color:#e8eaed;font-size:19px;margin-bottom:10px\">"
            @"Can’t reach the calendar</div>%@<br><br>"
            @"<span style=\"opacity:.5\">Menu bar → Reload, or Set Server URL…</span></div>"
            @"</body></html>",
            error.localizedDescription];
    [_webView loadHTMLString:html baseURL:nil];
}

- (void)windowWillClose:(NSNotification *)note {
    _window = nil;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;  // It lives in the menu bar.
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
