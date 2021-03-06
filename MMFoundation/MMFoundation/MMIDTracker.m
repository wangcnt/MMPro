//
//  MMIDTracker.m
//  MMFoundation
//
//  Created by Mark on 15/6/23.
//  Copyright (c) 2015年 Mark. All rights reserved.
//

#import "MMIDTracker.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

#define AssertProperQueue() NSAssert(dispatch_get_specific(queueTag), @"Invoked on incorrect queue")

const NSTimeInterval MMIDTrackerTimeoutNone = -1;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface MMIDTracker ()
@property (nonatomic) void *queueTag;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSMutableDictionary *dict;
@end

@implementation MMIDTracker
@synthesize queueTag, queue, dict;

- (id)init
{
	// You must use initWithDispatchQueue or initWithStream:dispatchQueue:
	return nil;
}

- (id)initWithDispatchQueue:(dispatch_queue_t)aQueue
{
    NSParameterAssert(aQueue != NULL);
	if ((self = [super init]))
	{
		queue = aQueue;
		
		queueTag = &queueTag;
		dispatch_queue_set_specific(queue, queueTag, queueTag, NULL);
		
#if !OS_OBJECT_USE_OBJC
		dispatch_retain(queue);
#endif
		
		dict = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	// We don't call [self removeAllIDs] because dealloc might not be invoked on queue
	
	for (id <MMTrackingInfo> info in [dict objectEnumerator])
	{
		[info cancelTimer];
	}
	[dict removeAllObjects];
	
	#if !OS_OBJECT_USE_OBJC
	dispatch_release(queue);
	#endif
}

- (void)addID:(NSString *)identifier target:(id)target selector:(SEL)selector timeout:(NSTimeInterval)timeout
{
	AssertProperQueue();
	
	MMBasicTrackingInfo *trackingInfo;
	trackingInfo = [[MMBasicTrackingInfo alloc] initWithTarget:target selector:selector timeout:timeout];
	
	[self addID:identifier trackingInfo:trackingInfo];
}

- (void)addID:(NSString *)identifier
        block:(void (^)(id obj, id <MMTrackingInfo> info))block
      timeout:(NSTimeInterval)timeout
{
	AssertProperQueue();
	
	MMBasicTrackingInfo *trackingInfo;
	trackingInfo = [[MMBasicTrackingInfo alloc] initWithBlock:block timeout:timeout];
	
	[self addID:identifier trackingInfo:trackingInfo];
}

- (void)addID:(NSString *)identifier trackingInfo:(id <MMTrackingInfo>)trackingInfo
{
	AssertProperQueue();
	
	dict[identifier] = trackingInfo;
	
    trackingInfo.identifier = identifier;
	[trackingInfo createTimerWithDispatchQueue:queue];
}

- (BOOL)invokeForID:(NSString *)identifier withObject:(id)obj
{
	AssertProperQueue();
    
    if([identifier length] == 0) return NO;
	
	id <MMTrackingInfo> info = dict[identifier];
    
	if (info)
	{
		[info invokeWithObject:obj];
		[info cancelTimer];
		[dict removeObjectForKey:identifier];
		
		return YES;
	}
	
	return NO;
}

- (NSUInteger)numberOfIDs
{
    AssertProperQueue();
	
	return [[dict allKeys] count];
}

- (void)removeID:(NSString *)identifier
{
	AssertProperQueue();
	
	id <MMTrackingInfo> info = dict[identifier];
	if (info)
	{
		[info cancelTimer];
		[dict removeObjectForKey:identifier];
	}
}

- (void)removeAllIDs
{
	AssertProperQueue();
	
	for (id <MMTrackingInfo> info in [dict objectEnumerator])
	{
		[info cancelTimer];
	}
	[dict removeAllObjects];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface MMBasicTrackingInfo()
@property (nonatomic, strong) id target;
@property (nonatomic) SEL selector;

@property (nonatomic, copy) void (^block)(id obj, id <MMTrackingInfo> info);

@property (nonatomic) NSTimeInterval timeout;

@property (nonatomic, strong) dispatch_source_t timer;
@end

@implementation MMBasicTrackingInfo

@synthesize timeout;
@synthesize identifier;
@synthesize target, selector, timer, block;

- (id)init
{
	// Use initWithTarget:selector:timeout: or initWithBlock:timeout:
	
	return nil;
}

- (id)initWithTarget:(id)aTarget selector:(SEL)aSelector timeout:(NSTimeInterval)aTimeout
{
    if(target || selector)
    {
        NSParameterAssert(aTarget);
        NSParameterAssert(aSelector);
    }
	
	if ((self = [super init]))
	{
		target = aTarget;
		selector = aSelector;
		timeout = aTimeout;
	}
	return self;
}

- (id)initWithBlock:(void (^)(id obj, id <MMTrackingInfo> info))aBlock timeout:(NSTimeInterval)aTimeout
{
	NSParameterAssert(aBlock);
	
	if ((self = [super init]))
	{
		block = [aBlock copy];
		timeout = aTimeout;
	}
	return self;
}

- (void)dealloc
{
	[self cancelTimer];
	
	target = nil;
	selector = NULL;
}

- (void)createTimerWithDispatchQueue:(dispatch_queue_t)queue
{
	NSAssert(queue != NULL, @"Method invoked with NULL queue");
	NSAssert(timer == NULL, @"Method invoked multiple times");
	
	if (timeout > 0.0)
	{
		timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
		
		dispatch_source_set_event_handler(timer, ^{ @autoreleasepool {
			
			[self invokeWithObject:nil];
            [self cancelTimer];
            
		}});
		
		dispatch_time_t tt = dispatch_time(DISPATCH_TIME_NOW, (timeout * NSEC_PER_SEC));
		
		dispatch_source_set_timer(timer, tt, DISPATCH_TIME_FOREVER, 0);
		dispatch_resume(timer);
	}
}

- (void)cancelTimer
{
	if (timer)
	{
		dispatch_source_cancel(timer);
		#if !OS_OBJECT_USE_OBJC
		dispatch_release(timer);
		#endif
		timer = NULL;
	}
}

- (void)invokeWithObject:(id)obj
{
	if (block)
    {
		block(obj, self);
	}
    else if(target && selector)
	{
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		[target performSelector:selector withObject:obj withObject:self];
		#pragma clang diagnostic pop
	}
}

@end
