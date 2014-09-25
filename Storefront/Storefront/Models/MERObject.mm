//
//  MERObject.m
//  Merchant
//
//  Created by Joshua Tessier on 2014-09-10.
//  Copyright (c) 2014 Shopify Inc. All rights reserved.
//

#import "MERObject.h"

//Runtime
#import <objc/runtime.h>
#import <objc/message.h>
#import "MERRuntime.h"

namespace shopify
{
	namespace merchant
	{
		/**
		 * Creates and returns a block that is used as the setter method for the persisted subclasses
		 * The method implementation calls through to its superclasses implementation and then marks
		 * the attribute as dirty.
		 */
		template <typename T>
		id attribute_setter(NSString *propertyName, SEL selector)
		{
			id setterBlock = ^ void (id _self, T value) {
				// we need to cast objc_msgSend so that the compiler inserts proper type information for the passed in value
				// not doing so results in strange behaviour (for example, floats never get set)
				void (*typed_objc_msgSend)(id, SEL, T) = (void (*)(id, SEL, T))objc_msgSend;
				typed_objc_msgSend(_self, selector, value);
				[_self markPropertyAsDirty:propertyName];
			};
			return setterBlock;
		}
	}
}

@implementation MERObject {
	NSMutableSet *_dirtyProperties;
}

- (instancetype)init
{
	return [self initWithDictionary:nil];
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary
{
	self = [super init];
	if (self) {
		_dirtyProperties = [[NSMutableSet alloc] init];
		[self updateWithDictionary:dictionary];
		[self markAsClean];
	}
	return self;
}

- (void)updateWithDictionary:(NSDictionary *)dictionary
{
	_identifier = dictionary[@"id"];
}

+ (NSArray *)convertJSONArray:(NSArray*)json block:(void (^)(id obj))createdBlock
{
	NSMutableArray *objects = [[NSMutableArray alloc] init];
	for (NSDictionary *jsonObject in json) {
		MERObject *obj = [[self alloc] initWithDictionary:jsonObject];
		[objects addObject:obj];
		if (createdBlock) {
			createdBlock(obj);
		}
	}
	return objects;
}

+ (NSArray *)convertJSONArray:(NSArray*)json
{
	return [self convertJSONArray:json block:nil];
}

+ (instancetype)convertObject:(id)object
{
	MERObject *convertedObject = nil;
	if (!(object == nil || [object isKindOfClass:[NSNull class]])) {
		convertedObject = [[self alloc] initWithDictionary:object];
	}
	return convertedObject;
}

#pragma mark - Dirty Property Tracking

- (BOOL)isDirty
{
	return [_dirtyProperties count] > 0;
}

- (NSSet *)dirtyProperties
{
	//TODO: This will probably be a source of concurrency problems, synchronize around this guy
	return [NSSet setWithSet:_dirtyProperties];
}

- (void)markPropertyAsDirty:(NSString *)property
{
	[_dirtyProperties addObject:property];
}

- (void)markAsClean
{
	[_dirtyProperties removeAllObjects];
}

+ (id)setterBlockForSelector:(SEL)selector property:(NSString *)property typeEncoding:(const char *)typeEncoding
{
	id setterBlock;
	switch (typeEncoding[0]) {
		case '@': // object
		{
			setterBlock = shopify::merchant::attribute_setter<id>(property, selector);
			break;
		}
		case 'B': // C++ style bool/_Bool
		{
			setterBlock = shopify::merchant::attribute_setter<bool>(property, selector);
			break;
		}
		case 'c': // char
		{
			setterBlock = shopify::merchant::attribute_setter<char>(property, selector);
			break;
		}
		case 'C': // unsigned char
		{
			setterBlock = shopify::merchant::attribute_setter<unsigned char>(property, selector);
			break;
		}
		case 'i': // int
		{
			setterBlock = shopify::merchant::attribute_setter<int>(property, selector);
			break;
		}
		case 'I': // unsigned int
		{
			setterBlock = shopify::merchant::attribute_setter<unsigned int>(property, selector);
			break;
		}
		case 's': // short
		{
			setterBlock = shopify::merchant::attribute_setter<short>(property, selector);
			break;
		}
		case 'S': // unsigned short
		{
			setterBlock = shopify::merchant::attribute_setter<unsigned short>(property, selector);
			break;
		}
		case 'l': // long
		{
			setterBlock = shopify::merchant::attribute_setter<long>(property, selector);
			break;
		}
		case 'L': // unsigned long
		{
			setterBlock = shopify::merchant::attribute_setter<unsigned long>(property, selector);
			break;
		}
		case 'q': // long long
		{
			setterBlock = shopify::merchant::attribute_setter<long long>(property, selector);
			break;
		}
		case 'Q': // unsigned long long
		{
			setterBlock = shopify::merchant::attribute_setter<unsigned long long>(property, selector);
			break;
		}
		case 'f': // float
		{
			setterBlock = shopify::merchant::attribute_setter<float>(property, selector);
			break;
		}
		case 'd': // double
		{
			setterBlock = shopify::merchant::attribute_setter<double>(property, selector);
			break;
		}
	}
	return setterBlock;
}

+ (void)wrapProperty:(NSString *)property
{
	SEL setter = NSSelectorFromString([NSString stringWithFormat:@"set%@:", [NSString stringWithFormat:@"%@%@",[[property substringToIndex:1] uppercaseString], [property substringFromIndex:1]]]);

	//Get the setter. don't worry about readonly properties as they're irrelevant for dirty tracking
	if (setter && [self instancesRespondToSelector:setter]) {
		Method setterMethod = class_getInstanceMethod(self, setter);
		IMP setterImpl = method_getImplementation(setterMethod);
		
		NSMethodSignature *methodSignature = [self instanceMethodSignatureForSelector:setter];
		if ([methodSignature numberOfArguments] == 3) {
			const char *typeEncoding = [methodSignature getArgumentTypeAtIndex:2];
			SEL newSetter = NSSelectorFromString([NSString stringWithFormat:@"mer_%@", NSStringFromSelector(setter)]);
			
			id setterBlock = [self setterBlockForSelector:newSetter property:property typeEncoding:typeEncoding];
			
			if (setterBlock) {
				//Create 'mer_setX:' that uses the existing implementation
				BOOL success = class_addMethod(self, newSetter, setterImpl, method_getTypeEncoding(setterMethod));
				
				//Create a new impmlementation
				IMP newImpl = imp_implementationWithBlock(setterBlock);
				
				//Then attach that implementation to 'setX:'. This way calling 'setX:' calls our implementation, and 'mer_setX:' calls the original implementation.
				success = class_replaceMethod(self, setter, newImpl, method_getTypeEncoding(setterMethod));
			}
		}
	}
}

+ (void)trackDirtyProperties
{
	NSSet *properties = class_getMERProperties(self);
	for (NSString *property in properties) {
		if ([property length] > 0) {
			[self wrapProperty:property];
		}
	}
}

@end