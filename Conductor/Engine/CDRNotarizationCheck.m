//
//  CDRNotarizationCheck.m
//  Conductor
//

#import "CDRNotarizationCheck.h"
#import "CDRErrors.h"

@implementation CDRNotarizationCheck

+ (BOOL)assessBundleAtURL:(NSURL *)url error:(NSError **)error {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/spctl"];
    task.arguments = @[@"--assess", @"--type", @"execute", url.path];

    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardError = stderrPipe;
    task.standardOutput = [NSPipe pipe];

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (error) *error = CDRError(CDRErrorNotarizationRejected, nil, launchError, nil);
        return NO;
    }
    [task waitUntilExit];

    if (task.terminationStatus == 0) return YES;

    NSData *stderrData = [stderrPipe.fileHandleForReading readDataToEndOfFile];
    NSString *stderrText = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding];
    NSDictionary *extra = stderrText.length > 0 ? @{@"CDRSpctlOutput": stderrText} : nil;
    if (error) *error = CDRError(CDRErrorNotarizationRejected, nil, nil, extra);
    return NO;
}

@end
