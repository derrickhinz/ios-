//
//  BUYAddress+Additions.m
//  Mobile Buy SDK
//
//  Created by David Muzi on 2015-05-28.
//  Copyright (c) 2015 Shopify Inc. All rights reserved.
//

#import "BUYAddress+Additions.h"

NSString * const BUYPartialAddressPlaceholder = @"---";


@implementation BUYAddress (Additions)

- (BOOL)isPartialAddress
{
	if ([self.address1 isEqualToString:BUYPartialAddressPlaceholder] ||
		[self.firstName isEqualToString:BUYPartialAddressPlaceholder] ||
		[self.lastName isEqualToString:BUYPartialAddressPlaceholder]) {
		return YES;
	}
	
	return NO;
}

@end