//
//  CDRAppRowModel_Private.h
//  Conductor
//
//  Read-write view of the row model for its own implementation and for
//  fixtures (tests that render the window in states no manifest can produce
//  yet). Production code outside CDRAppRowModel.m never imports this.
//

#import "CDRAppRowModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface CDRAppRowModel ()
@property (nonatomic, readwrite) NSString *bundleID;
@property (nonatomic, readwrite) NSString *appName;
@property (nonatomic, readwrite) NSURL *appURL;
@property (nonatomic, readwrite) NSString *installedVersionDisplay;
@property (nonatomic, readwrite) NSString *installedVersion;
@property (nonatomic, readwrite) CDRAppRowState state;
@property (nonatomic, readwrite) NSString *stateLine;
@property (nonatomic, readwrite) CDRAppRowActions actions;
@property (nonatomic, readwrite) BOOL contributesToBadge;
@property (nonatomic, readwrite, nullable) NSURL *vendorURL;
@property (nonatomic, readwrite, nullable) NSString *availableVersion;
@property (nonatomic, readwrite, nullable) NSString *advertisedVersion;
@property (nonatomic, readwrite) NSArray<CDRRelease *> *releases;
@property (nonatomic, readwrite) CDRReleaseNoteTypeSet noteTypes;
@property (nonatomic, readwrite, nullable) NSDate *releaseDate;
@property (nonatomic, readwrite, nullable) NSNumber *artifactSize;
@property (nonatomic, readwrite, nullable) NSURL *changelogURL;
@property (nonatomic, readwrite) CDRUrgency urgency;
@property (nonatomic, readwrite, nullable) NSDate *deferredUntil;
@property (nonatomic, readwrite, nullable) NSString *retractedVersion;
@property (nonatomic, readwrite, nullable) NSDate *retractionAdvertisedDate;
@property (nonatomic, readwrite, nullable) NSDate *retractionPulledDate;
@property (nonatomic, readwrite) CDRReleaseNoteTypeSet heldTypes;
@property (nonatomic, readwrite) CDRUpdatePhase operationPhase;
@property (nonatomic, readwrite, nullable) NSString *errorDescription;
@property (nonatomic, readwrite, nullable) NSString *developerName;
@property (nonatomic, readwrite) CDRReleaseNoteTypeSet shownTypes;
@property (nonatomic, readwrite) BOOL exposesDeveloperDetail;
@property (nonatomic, readwrite, nullable) NSString *deferralDurationName;
@end

NS_ASSUME_NONNULL_END
