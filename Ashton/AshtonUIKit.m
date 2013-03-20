#import "AshtonUIKit.h"
#import "AshtonIntermediate.h"
#import <CoreText/CoreText.h>

@interface AshtonUIKit ()
@property (nonatomic, readonly) NSArray *attributesToPreserve;
@end

@implementation AshtonUIKit

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static AshtonUIKit *sharedInstance;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[AshtonUIKit alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    if (self = [super init]) {
        _attributesToPreserve = @[ AshtonAttrLink, @"strikthroughColor", AshtonAttrUnderlineColor, AshtonAttrVerticalAlign ];
    }
    return self;
}

- (NSAttributedString *)intermediateRepresentationWithTargetRepresentation:(NSAttributedString *)input {
    NSMutableAttributedString *output = [input mutableCopy];
    NSRange totalRange = NSMakeRange (0, input.length);
    [input enumerateAttributesInRange:totalRange options:0 usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
        NSMutableDictionary *newAttrs = [NSMutableDictionary dictionaryWithCapacity:[attrs count]];
        for (id attrName in attrs) {
            id attr = attrs[attrName];
            if ([attrName isEqual:NSParagraphStyleAttributeName]) {
                // produces: paragraph
                NSParagraphStyle *paragraphStyle = attr;
                NSMutableDictionary *attrDict = [NSMutableDictionary dictionary];

                if (paragraphStyle.alignment == NSTextAlignmentLeft) attrDict[AshtonParagraphAttrTextAlignment] = @"left";
                if (paragraphStyle.alignment == NSTextAlignmentRight) attrDict[AshtonParagraphAttrTextAlignment] = @"right";
                if (paragraphStyle.alignment == NSTextAlignmentCenter) attrDict[AshtonParagraphAttrTextAlignment] = @"center";
                newAttrs[AshtonAttrParagraph] = attrDict;
            }
            if ([attrName isEqual:NSFontAttributeName]) {
                // produces: font
                UIFont *font = attr;
                NSMutableDictionary *attrDict = [NSMutableDictionary dictionary];

                CTFontRef ctFont = CTFontCreateWithName((__bridge CFStringRef)font.fontName, font.pointSize, NULL);
                CTFontSymbolicTraits symbolicTraits = CTFontGetSymbolicTraits(ctFont);
                if ((symbolicTraits & kCTFontTraitBold) == kCTFontTraitBold) attrDict[AshtonFontAttrTraitBold] = @(YES);
                if ((symbolicTraits & kCTFontTraitItalic) == kCTFontTraitItalic) attrDict[AshtonFontAttrTraitItalic] = @(YES);

                attrDict[AshtonFontAttrPointSize] = @(font.pointSize);
                attrDict[AshtonFontAttrFamilyName] = CFBridgingRelease(CTFontCopyName(ctFont, kCTFontFamilyNameKey));
                CFRelease(ctFont);
                newAttrs[AshtonAttrFont] = attrDict;
            }
            if ([attrName isEqual:NSUnderlineStyleAttributeName]) {
                // produces: underline
                if ([attr isEqual:@(NSUnderlineStyleSingle)]) newAttrs[AshtonAttrUnderline] = AshtonUnderlineStyleSingle;
            }
            if ([attrName isEqual:NSStrikethroughStyleAttributeName]) {
                // produces: strikthrough
                if ([attr isEqual:@(NSUnderlineStyleSingle)]) newAttrs[AshtonAttrStrikethrough] = AshtonStrikethroughStyleSingle;
            }
            if ([attrName isEqual:NSForegroundColorAttributeName]) {
                // produces: color
                newAttrs[AshtonAttrColor] = [self arrayForColor:attr];
            }
        }
        // after going through all UIKit attributes copy back the preserved attributes, but only if they don't exist already
        // we don't want to overwrite settings that were assigned by UIKit with our preserved attributes
        for (id attrName in attrs) {
            id attr = attrs[attrName];
            if ([self.attributesToPreserve containsObject:attrName]) {
                if(!newAttrs[attrName]) newAttrs[attrName] = attr;
            }
        }
        [output setAttributes:newAttrs range:range];
    }];

    return output;
}

- (NSAttributedString *)targetRepresentationWithIntermediateRepresentation:(NSAttributedString *)input {
    NSMutableAttributedString *output = [input mutableCopy];
    NSRange totalRange = NSMakeRange (0, input.length);
    [input enumerateAttributesInRange:totalRange options:0 usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
        NSMutableDictionary *newAttrs = [NSMutableDictionary dictionaryWithCapacity:[attrs count]];
        for (NSString *attrName in attrs) {
            id attr = attrs[attrName];
            if ([attrName isEqualToString:AshtonAttrParagraph]) {
                // consumes: paragraph
                NSDictionary *attrDict = attr;
                NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];

                if ([attrDict[AshtonParagraphAttrTextAlignment] isEqualToString:@"left"])  paragraphStyle.alignment = NSTextAlignmentLeft;
                if ([attrDict[AshtonParagraphAttrTextAlignment] isEqualToString:@"right"]) paragraphStyle.alignment = NSTextAlignmentRight;
                if ([attrDict[AshtonParagraphAttrTextAlignment] isEqualToString:@"center"]) paragraphStyle.alignment = NSTextAlignmentCenter;

                newAttrs[NSParagraphStyleAttributeName] = paragraphStyle;
            }
            if ([attrName isEqualToString:AshtonAttrFont]) {
                // consumes: font
                NSDictionary *attrDict = attr;

                NSDictionary *descriptorAttributes = @{ (id)kCTFontNameAttribute: attrDict[AshtonFontAttrFamilyName] };
                CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)(descriptorAttributes));
                CTFontRef ctFont = CTFontCreateWithFontDescriptor(descriptor, [attrDict[AshtonFontAttrPointSize] doubleValue], NULL);
                CFRelease(descriptor);

                CTFontSymbolicTraits symbolicTraits = 0; // using CTFontGetSymbolicTraits also makes CTFontCreateCopyWithSymbolicTraits fail
                if ([attrDict[AshtonFontAttrTraitBold] isEqual:@(YES)]) symbolicTraits = symbolicTraits | kCTFontTraitBold;
                if ([attrDict[AshtonFontAttrTraitItalic] isEqual:@(YES)]) symbolicTraits = symbolicTraits | kCTFontTraitItalic;
                if (symbolicTraits != 0) {
                    // Unfortunately CTFontCreateCopyWithSymbolicTraits returns NULL when there are no symbolicTraits (== 0)
                    // Is there a better way to detect "no" symbolic traits?
                    CTFontRef newCTFont = CTFontCreateCopyWithSymbolicTraits(ctFont, 0.0, NULL, symbolicTraits, symbolicTraits);
                    // And even worse, if a font is defined to be "only" bold (like Arial Rounded MT Bold is) then
                    // CTFontCreateCopyWithSymbolicTraits also returns NULL
                    if (newCTFont != NULL) {
                        CFRelease(ctFont);
                        ctFont = newCTFont;
                    }
                }

                // We need to construct a kCTFontPostScriptNameKey for the font with the given attributes
                NSString *fontName = CFBridgingRelease(CTFontCopyName(ctFont, kCTFontPostScriptNameKey));
                UIFont *font = [UIFont fontWithName:fontName size:[attrDict[AshtonFontAttrPointSize] doubleValue]];
                CFRelease(ctFont);

                newAttrs[NSFontAttributeName] = font;
            }
            if ([attrName isEqualToString:AshtonAttrUnderline]) {
                // consumes: underline
                if ([attr isEqualToString:AshtonUnderlineStyleSingle]) newAttrs[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
                if ([attr isEqualToString:AshtonUnderlineStyleDouble]) newAttrs[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
                if ([attr isEqualToString:AshtonUnderlineStyleThick]) newAttrs[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
            }
            if ([attrName isEqualToString:AshtonAttrStrikethrough]) {
                if ([attr isEqualToString:AshtonStrikethroughStyleSingle]) newAttrs[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
                if ([attr isEqualToString:AshtonStrikethroughStyleDouble]) newAttrs[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
                if ([attr isEqualToString:AshtonStrikethroughStyleThick]) newAttrs[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
            }
            if ([attrName isEqualToString:AshtonAttrColor]) {
                // consumes: color
                newAttrs[NSForegroundColorAttributeName] = [self colorForArray:attr];
            }
            if ([self.attributesToPreserve containsObject:attrName]) {
                newAttrs[attrName] = attr;
            }
        }
        [output setAttributes:newAttrs range:range];
    }];

    return output;
}

- (NSArray *)arrayForColor:(UIColor *)color {
    CGFloat red, green, blue, alpha;
    [color getRed:&red green:&green blue:&blue alpha:&alpha];
    return @[ @(red), @(green), @(blue), @(alpha) ];
}

- (UIColor *)colorForArray:(NSArray *)input {
    CGFloat red = [input[0] doubleValue], green = [input[1] doubleValue], blue = [input[2] doubleValue], alpha = [input[3] doubleValue];
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

@end