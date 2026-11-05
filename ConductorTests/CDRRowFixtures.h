//
//  CDRRowFixtures.h
//  ConductorTests
//
//  Row models for every state the main window draws, including the ones no
//  manifest can produce until CND-5 / CND-7 land. The set mirrors
//  ref-assets/Main window so a render can be laid beside the design.
//

#import <Foundation/Foundation.h>
#import "CDRAppRowModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface CDRRowFixtures : NSObject

/// One row in `state`. `notes` is an array of @[typeKey, text] pairs for the
/// advertised version; `history` maps a skipped version to its own pairs.
+ (CDRAppRowModel *)rowNamed:(NSString *)name
                       state:(CDRAppRowState)state
                   installed:(NSString *)installed
                  advertised:(nullable NSString *)advertised
                       notes:(nullable NSArray<NSArray<NSString *> *> *)notes
                     history:(nullable NSDictionary<NSString *, NSArray<NSArray<NSString *> *> *> *)history;

/// The eight rows of the Main window design, in the design's order.
+ (NSArray<CDRAppRowModel *> *)designRows;

/// The row named `name` from -designRows.
+ (CDRAppRowModel *)designRowNamed:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
