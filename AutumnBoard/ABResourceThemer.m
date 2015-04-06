//
//  ABResourceThemer.c
//  AutumnBoard
//
//  Created by Alexander Zielenski on 4/4/15.
//  Copyright (c) 2015 Alex Zielenski. All rights reserved.
//

#import "ABResourceThemer.h"
#import <Opee/Opee.h>
#import "ABLogging.h"

static NSURL *ThemePath;
static NSString *nameOfIconForBundle(NSBundle *bundle);
static NSURL *URLForBundle(NSBundle *bundle);
static NSURL *URLForOSType(NSString *type);
static NSURL *URLForUTIFile(NSString *name);
static NSDictionary *typeIndexForBundle(NSBundle *bundle);

static NSString *const ABTypeIndexUTIsKey = @"utis";
static NSString *const ABTypeIndexExtensionsKey = @"extenions";
static NSString *const ABTypeIndexMIMEsKey = @"mimes";
static NSString *const ABTypeIndexOSTypesKey = @"ostypes";
static NSString *const ABTypeIndexRoleKey = @"role";

OPInitialize {
    ThemePath = [NSURL fileURLWithPath:@"/Library/AutumnBoard/Themes/Fladder2"];
}

#pragma mark - URL Generation

static NSURL *URLForBundle(NSBundle *bundle) {
    if (!bundle || ![bundle isKindOfClass:[NSBundle class]])
        return nil;
    
    NSDictionary *info = [bundle infoDictionary];
    if (!info)
        return nil;
    
    NSString *identifier = info[(__bridge NSString *)kCFBundleIdentifierKey];
    
    if (!identifier) {
        return nil;
    }
    return [[ThemePath URLByAppendingPathComponent:@"Bundles"] URLByAppendingPathComponent:identifier];
}

NSURL *URLForOSType(NSString *type) {
    return [[[ThemePath URLByAppendingPathComponent:@"OSTypes"] URLByAppendingPathComponent:type] URLByAppendingPathExtension:@"icns"];
}

NSURL *URLForUTIFile(NSString *name) {
    return [[[ThemePath URLByAppendingPathComponent:@"UTIs"] URLByAppendingPathComponent:name] URLByAppendingPathExtension:@"icns"];
}

#pragma mark - Bundle Helpers
//!TODO: see if we should actually set up a daemon for this since it is quite expensive to do for every single application
static NSDictionary *typeIndexForBundle(NSBundle *bundle) {
    static NSMutableDictionary *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    
    if (!bundle.bundleIdentifier)
        return nil;
    
    NSDictionary *cached = [cache objectForKey:bundle.bundleIdentifier];
    if (cached)
        return cached;
    
    NSDictionary *info = bundle.infoDictionary;
    NSMutableDictionary *index = [NSMutableDictionary dictionary];
    NSDictionary *types = info[@"CFBundleDocumentTypes"];
    
    for (NSDictionary *type in types) {
        NSString *icon = type[@"CFBundleTypeIconFile"];
        if (!icon)
            continue;
        
        NSMutableDictionary *entry = (NSMutableDictionary *)index[icon];
        if (!entry) {
            entry = [NSMutableDictionary dictionary];
            entry[ABTypeIndexUTIsKey] = [NSMutableArray array];
            entry[ABTypeIndexExtensionsKey] = [NSMutableArray array];
            entry[ABTypeIndexMIMEsKey] = [NSMutableArray array];
            entry[ABTypeIndexOSTypesKey] = [NSMutableArray array];
            
            index[icon] = entry;
        }
        
        [(NSMutableArray *)entry[ABTypeIndexUTIsKey] addObjectsFromArray:type[@"LSItemContentTypes"]];
        [(NSMutableArray *)entry[ABTypeIndexExtensionsKey] addObjectsFromArray:type[@"CFBundleTypeExtensions"]];
        [(NSMutableArray *)entry[ABTypeIndexMIMEsKey] addObjectsFromArray:type[@"CFBundleTypeMIMETypes"]];
        [(NSMutableArray *)entry[ABTypeIndexOSTypesKey] addObjectsFromArray:type[@"CFBundleTypeOSTypes"]];
    }
    
    cache[bundle.bundleIdentifier] = index;
    return index;
}

static NSString *nameOfIconForBundle(NSBundle *bundle) {
    NSDictionary *info = [bundle infoDictionary];
    if (!info)
        return nil;
    
    NSString *iconName = info[@"CFBundleIconFile"];
    if (iconName)
        return iconName;
    
    iconName = info[@"NSPrefPaneIconFile"];
    return iconName;
}

NSURL *iconForBundle(NSBundle *bundle) {
    // Shortcut so you dont have to make a folder for each app to change its icon
    NSURL *bndlURL = [URLForBundle(bundle) URLByAppendingPathExtension:@"icns"];
    if (bndlURL && [[NSFileManager defaultManager] fileExistsAtPath:bndlURL.path]) {
        return bndlURL;
    }
    
    NSString *iconName = nameOfIconForBundle(bundle);
    // This bundle has no icon, return our generic one
    if (!iconName || iconName.length == 0) {
        //!TODO: Even if there is an icon name, check to see if it exists
        if (bundle.infoDictionary.count && bundle.bundlePath.pathExtension.length)
            return customIconForExtension(bundle.bundlePath.pathExtension);
        return nil;
    }
    
    return ([bundle URLForResource:iconName.stringByDeletingPathExtension withExtension:@"icns"]);
}

#pragma mark - Absolute Path Helpers

NSURL *replacementURLForURLRelativeToBundle(NSURL *url, NSBundle *bndl) {
    if (!url || !url.isFileURL || !bndl.bundleIdentifier)
        return nil;
    
    // Step 1, check absolute paths
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *testURL = customIconForURL(url);
    if (testURL)
        return testURL;

    NSArray *urlComponents = [url.path stringByReplacingOccurrencesOfString:bndl.bundlePath withString:@""].pathComponents;
    NSUInteger rsrcIdx = [urlComponents indexOfObject:@"Resources"];
    if (rsrcIdx == NSNotFound)
        return nil;
    
    // Add support for the shorthand of calling the icon by the bundleidentifier.icns
    NSString *iconName = nameOfIconForBundle(bndl);
    NSString *lastObject = urlComponents.lastObject;
    if ((([iconName.stringByDeletingPathExtension isEqualToString:lastObject.stringByDeletingPathExtension] &&
        [lastObject.pathExtension.lowercaseString isEqualToString:@"icns"]) ||
        [iconName isEqualToString:lastObject]) &&
        rsrcIdx == urlComponents.count - 2) {
        
        NSURL *iconURL = [URLForBundle(bndl) URLByAppendingPathExtension:@"icns"];
        if ([manager fileExistsAtPath:iconURL.path]) {
            return iconURL;
        }
    }
    
    // Search the bundle's declared types to see if the resource we are looking for
    // is actually an app icon
    NSDictionary *index = typeIndexForBundle(bndl);
    if (index.count) {
        NSDictionary *entry = index[lastObject] ?: index[lastObject.stringByDeletingPathExtension];
        
        if (entry) {
            NSArray *utis = entry[ABTypeIndexUTIsKey];
            for (NSString *uti in utis) {
                NSURL *url = customIconForUTI(uti);
                if (url)
                    return url;
            }
            
            NSArray *extensions = entry[ABTypeIndexExtensionsKey];
            for (NSString *ext in extensions) {
                NSURL *url = customIconForExtension(ext);
                if (url)
                    return url;
            }
            
            NSArray *ostypes = entry[ABTypeIndexOSTypesKey];
            for (NSString *ostype in ostypes) {
                NSURL *url = customIconForOSType(ostype);
                if (url)
                    return url;
            }
        }
    }

    
    testURL = URLForBundle(bndl);
    for (NSUInteger x =  rsrcIdx + 1; x < urlComponents.count; x++) {
        testURL = [testURL URLByAppendingPathComponent:urlComponents[x]];
    }
    
    if ([manager fileExistsAtPath:testURL.path])
        return testURL;
    
    return nil;
}

NSURL *replacementURLForURL(NSURL *url) {
    if (!url || !url.isFileURL)
        return nil;
    // traverse down path until we get a bundle with an identifier
    BOOL foundBundle = NO;
    NSBundle *bndl = nil;
    NSURL *testURL = [url URLByDeletingLastPathComponent];
    NSUInteger cnt = 0;
    
    // reasonably limit the deep search to 10
    while (![testURL.path isEqualToString:@"/.."] &&
           !foundBundle &&
           cnt++ <= 10) {
        bndl = [NSBundle bundleWithURL:testURL];
        if (bndl.bundleIdentifier) {
            foundBundle = YES;
            break;
        }
        
        testURL = [testURL URLByDeletingLastPathComponent];
    }
    
    return replacementURLForURLRelativeToBundle(url, bndl);
}

NSURL *customIconForURL(NSURL *url) {
    if (!url)
        return nil;

    // Step 1, check if our theme structure has a custom icon for this hardcoded
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDir = NO;
    NSURL *testURL = [[ThemePath URLByAppendingPathComponent:[url.path stringByAbbreviatingWithTildeInPath]] URLByAppendingPathExtension:@"icns"];
    if ([manager fileExistsAtPath:testURL.path isDirectory:&isDir] && !isDir) {
        return testURL;
    }
    

    return nil;
}

#pragma mark - UTI Helpers

NSURL *customIconForOSType(NSString *type) {
    if (!type || type.length != 4 || [type isEqualToString:@"????"]) {
        return nil;
    }
    
    // step 1, check if we have the actual type.icns
    NSURL *tentativeURL = URLForOSType(type);
    NSFileManager *manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:tentativeURL.path]) {
        return tentativeURL;
    }
    
    // step 2, convert to uti and go ham
    // step 2: get all of the utis for this extension and check against that
    NSArray *utis = (__bridge_transfer NSArray *)UTTypeCreateAllIdentifiersForTag(kUTTagClassOSType, (__bridge CFStringRef)type, NULL);
    for (NSString *uti in utis) {
        // Use this so it also checks other variants of this extension
        // such as jpeg vs jpg in addition to public.jpeg
        tentativeURL = customIconForUTI(uti);
        if (tentativeURL)
            return tentativeURL;
    }
    
    return nil;
}

NSURL *customIconForUTI(NSString *uti) {
    if (!uti || UTTypeIsDynamic((__bridge CFStringRef)(uti)))
        return nil;
    
    // step 1, check if we have the actual uti.icns
    NSURL *tentativeURL = URLForUTIFile(uti);
    NSFileManager *manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:tentativeURL.path]) {
        return tentativeURL;
    }
    
    // step 2: get all of the extensions for this uti and check against that
    NSArray *extensions = (__bridge_transfer NSArray *)(UTTypeCopyAllTagsWithClass((__bridge CFStringRef)(uti), kUTTagClassFilenameExtension));
    for (NSString *extension in extensions) {
        tentativeURL = URLForUTIFile(extension);
        if ([manager fileExistsAtPath: tentativeURL.path]) {
            return tentativeURL;
        }
    }
    
    // step 3: get all of the ostypes for this uti and check that too
    NSArray *ostypes = (__bridge_transfer NSArray *)UTTypeCopyAllTagsWithClass((__bridge CFStringRef)(uti), kUTTagClassOSType);
    for (NSString *ostype in ostypes) {
        tentativeURL = URLForOSType(ostype);
        if ([manager fileExistsAtPath:tentativeURL.path]) {
            return tentativeURL;
        }
    }
    
    return nil;
}

NSURL *customIconForExtension(NSString *extension) {
    if (!extension)
        return nil;
    
    // step 1, check if we have the actual extension.icns
    NSURL *tentativeURL = URLForUTIFile(extension);
    NSFileManager *manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:tentativeURL.path]) {
        return tentativeURL;
    }
    
    // step 2: get all of the utis for this extension and check against that
    NSArray *utis = (__bridge_transfer NSArray *)UTTypeCreateAllIdentifiersForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)extension, NULL);
    for (NSString *uti in utis) {
        // Use this so it also checks other variants of this extension
        // such as jpeg vs jpg in addition to public.jpeg
        tentativeURL = customIconForUTI(uti);
        if (tentativeURL)
            return tentativeURL;
    }
    
    return nil;
}

BOOL ABIsInQuicklook() {
    NSString *name = [[NSProcessInfo processInfo] processName];
    return [name isEqualToString:@"quicklookd"] || [name isEqualToString:@"QuickLookSatellite"];
}
