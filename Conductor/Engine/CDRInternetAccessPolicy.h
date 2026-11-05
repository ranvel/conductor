//
//  CDRInternetAccessPolicy.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One connection a developer declares: where, and why.
@interface CDRInternetAccessPolicyRow : NSObject
/// The remote end as the developer wrote it ("search.example.com",
/// "*.example.com, example.net"), or Conductor's wording for a bare
/// wildcard ("Any server").
@property (nonatomic, readonly, copy) NSString *subject;
/// Why, in the developer's words (localized when the bundle ships a
/// translation). Conductor's own "No purpose given." when there is none.
@property (nonatomic, readonly, copy) NSString *purpose;
@property (nonatomic, readonly) BOOL incoming;
/// "TCP 443", "TCP 80, 443" — protocol and ports as declared, for the
/// developer detail view. Nil when neither is given.
@property (nonatomic, readonly, copy, nullable) NSString *transport;
@end

/// A bundle's Internet Access Policy — Objective Development's format, the
/// file Little Snitch reads — reduced to what Conductor shows: the declared
/// connections and their purposes.
///
/// Read from inside a bundle's sealed resources. For a staged build that is
/// only ever done after Verify has passed, so the file is covered by the
/// signature that was just checked. It is display and consent data, never a
/// verification input: a malformed or absent policy means "no policy".
@interface CDRInternetAccessPolicy : NSObject

@property (nonatomic, readonly, copy) NSArray<CDRInternetAccessPolicyRow *> *rows;
/// What the developer says the app is, if given.
@property (nonatomic, readonly, copy, nullable) NSString *applicationDescription;
/// Parts of the file Conductor read but does not show, for the log.
@property (nonatomic, readonly, copy) NSArray<NSString *> *warnings;

/// At most this many connections are kept; the rest are counted in a warning.
extern const NSUInteger CDRInternetAccessPolicyMaxRows;

/// Looks, in order, for Contents/Resources/InternetAccessPolicy.plist,
/// …/Base.lproj/InternetAccessPolicy.plist and …/InternetAccessPolicy.json.
/// Nil when the bundle ships none, or the one it ships can't be parsed.
+ (nullable instancetype)policyForBundleAtURL:(NSURL *)bundleURL;

/// Pure: a parsed policy file (plist or JSON root) plus an optional
/// localization table → the policy. Nil when `root` isn't a dictionary.
+ (nullable instancetype)policyWithPropertyList:(nullable id)root
                                        strings:(nullable NSDictionary<NSString *, NSString *> *)strings;

@end

NS_ASSUME_NONNULL_END
