//
//  CDRVersion.m
//  Conductor
//

#import "CDRVersion.h"

@implementation CDRVersion

+ (NSComparisonResult)compare:(NSString *)a to:(NSString *)b {
    NSArray<NSString *> *ac = [a componentsSeparatedByString:@"."];
    NSArray<NSString *> *bc = [b componentsSeparatedByString:@"."];
    NSUInteger n = MAX(ac.count, bc.count);
    for (NSUInteger i = 0; i < n; i++) {
        NSString *x = i < ac.count ? ac[i] : @"0";
        NSString *y = i < bc.count ? bc[i] : @"0";

        NSScanner *sx = [NSScanner scannerWithString:x];
        NSScanner *sy = [NSScanner scannerWithString:y];
        long long nx, ny;
        BOOL xNumeric = [sx scanLongLong:&nx] && sx.atEnd;
        BOOL yNumeric = [sy scanLongLong:&ny] && sy.atEnd;

        if (xNumeric && yNumeric) {
            if (nx != ny) return nx < ny ? NSOrderedAscending : NSOrderedDescending;
        } else {
            NSComparisonResult r = [x compare:y];
            if (r != NSOrderedSame) return r;
        }
    }
    return NSOrderedSame;
}

+ (BOOL)isVersion:(NSString *)candidateShort
            build:(NSString *)candidateBuild
        newerThan:(NSString *)baselineShort
            build:(NSString *)baselineBuild {
    NSComparisonResult r = [self compare:candidateShort to:baselineShort];
    if (r != NSOrderedSame) return r == NSOrderedDescending;
    if (candidateBuild.length > 0 && baselineBuild.length > 0) {
        return [self compare:candidateBuild to:baselineBuild] == NSOrderedDescending;
    }
    return NO;
}

@end
