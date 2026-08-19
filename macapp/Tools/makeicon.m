// Renders the 1024pt app icon: a dark squircle with a minimal calendar page.
#import <AppKit/AppKit.h>

static const CGFloat S = 1024.0;

static NSImage *DrawIcon(void) {
    return [NSImage imageWithSize:NSMakeSize(S, S)
                          flipped:NO
                   drawingHandler:^BOOL(NSRect dirty) {
        CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];

        // The rounded square every macOS icon sits in.
        CGFloat inset = 100.0;
        NSBezierPath *body = [NSBezierPath
            bezierPathWithRoundedRect:NSMakeRect(inset, inset, S - inset * 2, S - inset * 2)
                              xRadius:185
                              yRadius:185];

        CGContextSaveGState(ctx);
        [body addClip];

        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat locs[2] = {0.0, 1.0};

        NSArray *bgColors = @[
            (id)[NSColor colorWithSRGBRed:0.10 green:0.12 blue:0.16 alpha:1].CGColor,
            (id)[NSColor colorWithSRGBRed:0.035 green:0.04 blue:0.055 alpha:1].CGColor,
        ];
        CGGradientRef bg = CGGradientCreateWithColors(space, (__bridge CFArrayRef)bgColors, locs);
        CGContextDrawLinearGradient(ctx, bg, CGPointMake(0, S), CGPointMake(0, inset), 0);
        CGGradientRelease(bg);

        // Accent bloom, echoing the app's own ambience.
        NSArray *glowColors = @[
            (id)[NSColor colorWithSRGBRed:0.54 green:0.71 blue:0.97 alpha:0.30].CGColor,
            (id)[NSColor colorWithSRGBRed:0.54 green:0.71 blue:0.97 alpha:0.0].CGColor,
        ];
        CGGradientRef glow =
            CGGradientCreateWithColors(space, (__bridge CFArrayRef)glowColors, locs);
        CGContextDrawRadialGradient(ctx, glow, CGPointMake(300, 780), 0, CGPointMake(300, 780),
                                    460, 0);
        CGGradientRelease(glow);
        CGColorSpaceRelease(space);
        CGContextRestoreGState(ctx);

        // Hairline edge.
        [[NSColor colorWithWhite:1 alpha:0.10] setStroke];
        body.lineWidth = 3;
        [body stroke];

        // The calendar page.
        NSRect card = NSMakeRect(292, 286, 440, 430);
        NSBezierPath *cardPath = [NSBezierPath bezierPathWithRoundedRect:card
                                                                xRadius:58
                                                                yRadius:58];
        [[NSColor colorWithWhite:0.96 alpha:1] setFill];
        [cardPath fill];

        // Header band, clipped so the card's top corners stay round.
        CGContextSaveGState(ctx);
        [cardPath addClip];
        [[NSColor colorWithSRGBRed:0.54 green:0.71 blue:0.97 alpha:1] setFill];
        NSRectFill(NSMakeRect(NSMinX(card), NSMaxY(card) - 112, card.size.width, 112));
        CGContextRestoreGState(ctx);

        // Binding rings.
        [[NSColor colorWithWhite:0.96 alpha:1] setFill];
        CGFloat ringX[2] = {NSMinX(card) + 122, NSMaxX(card) - 122};
        for (int i = 0; i < 2; i++) {
            [[NSBezierPath
                bezierPathWithRoundedRect:NSMakeRect(ringX[i] - 19, NSMaxY(card) - 46, 38, 92)
                                  xRadius:19
                                  yRadius:19] fill];
        }

        // Two rows of day cells; one of them is today.
        CGFloat cell = 62, gap = 26;
        CGFloat gridW = cell * 3 + gap * 2;
        CGFloat startX = NSMidX(card) - gridW / 2;
        for (int row = 0; row < 2; row++) {
            for (int col = 0; col < 3; col++) {
                NSRect r = NSMakeRect(startX + col * (cell + gap),
                                      NSMinY(card) + 78 + (1 - row) * (cell + gap), cell, cell);
                BOOL isToday = (row == 0 && col == 1);
                if (isToday) {
                    [[NSColor colorWithSRGBRed:0.54 green:0.71 blue:0.97 alpha:1] setFill];
                } else {
                    [[NSColor colorWithSRGBRed:0.055 green:0.065 blue:0.09 alpha:0.88] setFill];
                }
                [[NSBezierPath bezierPathWithRoundedRect:r xRadius:18 yRadius:18] fill];
            }
        }

        return YES;
    }];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *out = argc > 1 ? @(argv[1]) : @"icon-1024.png";
        NSImage *image = DrawIcon();
        NSBitmapImageRep *rep =
            [[NSBitmapImageRep alloc] initWithData:[image TIFFRepresentation]];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (![png writeToFile:out atomically:YES]) {
            fprintf(stderr, "failed to write %s\n", out.UTF8String);
            return 1;
        }
        printf("wrote %s\n", out.UTF8String);
    }
    return 0;
}
