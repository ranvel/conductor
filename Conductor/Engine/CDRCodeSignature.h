//
//  CDRCodeSignature.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The security core: Team ID capture from the installed copy, and pinned
/// validation of the staged copy (replace-flow.md §0 and §3.3). The installed
/// copy's Team ID is the trust anchor for the entire replacement flow.
@interface CDRCodeSignature : NSObject

/// Reads the Team ID from the bundle's code signature.
/// Errors: CDRErrorInstalledUnsigned (no signature at all) vs
/// CDRErrorInstalledAdHoc (signed, but no team — ad-hoc or non-Developer-ID).
+ (nullable NSString *)teamIdentifierForBundleAtURL:(NSURL *)url error:(NSError **)error;

/// Validates the bundle's signature against a requirement pinning the given
/// Team ID: `anchor apple generic and certificate leaf[subject.OU] = "<TEAM>"`,
/// with kSecCSCheckAllArchitectures | kSecCSStrictValidate.
/// Errors: CDRErrorTeamIDMismatch (valid signature, wrong team) vs
/// CDRErrorSignatureInvalid (anything else).
+ (BOOL)validateBundleAtURL:(NSURL *)url
               pinnedTeamID:(NSString *)teamID
                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
