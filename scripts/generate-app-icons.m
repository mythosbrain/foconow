#import <AppKit/AppKit.h>

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc < 2) return 2;
    NSString *root = [NSString stringWithUTF8String:argv[1]];
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:1024 pixelsHigh:1024 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
    [[NSColor colorWithCalibratedWhite:0 alpha:1] setFill];
    [[NSBezierPath bezierPathWithRect:NSMakeRect(0, 0, 1024, 1024)] fill];
    [[NSColor colorWithCalibratedWhite:.055 alpha:1] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(90, 90, 844, 844) xRadius:185 yRadius:185] fill];
    [[NSColor colorWithCalibratedWhite:1 alpha:1] setStroke];
    NSBezierPath *p = [NSBezierPath bezierPath];
    p.lineWidth = 34; p.lineCapStyle = NSLineCapStyleRound; p.lineJoinStyle = NSLineJoinStyleRound;
    [p moveToPoint:NSMakePoint(512, 285)]; [p lineToPoint:NSMakePoint(512, 535)];
    [p moveToPoint:NSMakePoint(512, 435)];
    [p curveToPoint:NSMakePoint(286, 688) controlPoint1:NSMakePoint(334, 402) controlPoint2:NSMakePoint(267, 549)];
    [p curveToPoint:NSMakePoint(512, 435) controlPoint1:NSMakePoint(461, 704) controlPoint2:NSMakePoint(554, 601)];
    [p moveToPoint:NSMakePoint(512, 535)];
    [p curveToPoint:NSMakePoint(765, 765) controlPoint1:NSMakePoint(482, 723) controlPoint2:NSMakePoint(611, 786)];
    [p curveToPoint:NSMakePoint(512, 535) controlPoint1:NSMakePoint(788, 581) controlPoint2:NSMakePoint(653, 508)];
    [p stroke];
    [NSGraphicsContext restoreGraphicsState];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (!png) return 1;
    [png writeToFile:[root stringByAppendingPathComponent:@"Apple/AppIcon1024.png"] atomically:YES];
    [png writeToFile:[root stringByAppendingPathComponent:@"Apple/iOSAssets.xcassets/AppIcon.appiconset/AppIcon1024.png"] atomically:YES];
    return 0;
  }
}
