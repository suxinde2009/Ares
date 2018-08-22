//
//  PeerTalkManager.m
//  iOSTabletEmulator
//
//  Created by Switt Kongdachalert on 30/1/18.
//  Copyright © 2018 Switt's Software. All rights reserved.
//

#import "PeerTalkManager.h"
#import "PTChannel.h"
#import "PTProtocol.h"
#import "PTUSBHub.h"

@interface NSData (PeerTalkExtension)

/** Unarchive data into an object. It will be returned as type `Any` but you can cast it into the correct type. */
-(id)convert;
/** Converts an object into Data using the NSKeyedArchiver */
+(NSData *)toData:(id)object;
@end
@implementation NSData (PeerTalkExtension)
-(id)convert { return [NSKeyedUnarchiver unarchiveObjectWithData:self]; }
+(NSData *)toData:(id)object { return [NSKeyedArchiver archivedDataWithRootObject:object]; }
@end

#if TARGET_OS_IPHONE
@interface PTManagerMobile () <PTChannelDelegate>

@end
@implementation PTManagerMobile
@synthesize portNumber = _portNumber;
@synthesize serverChannel = _serverChannel;
@synthesize debugMode = _debugMode;
@synthesize delegate = _delegate;
@synthesize peerChannel = _peerChannel;
static PTManagerMobile *instance = nil;

+(id <PTManager>)sharedManager {
    if(!instance) {
        instance = [PTManagerMobile new];
    }
    return instance;
}

-(id)init {
    self = [super init];
    if(!self) return nil;
    
    return self;
}


-(void)printDebug:(NSString *)string
{
    if(_debugMode)
    {
        NSLog(@"%@", string);
    }
}
/** Begins to look for a device and connects when it finds one */
-(void)connect:(int)portNumber {
    if(!self.isConnected) {
        self.portNumber = portNumber;
        PTChannel *channel = [PTChannel channelWithDelegate:self];
        [channel listenOnPort:portNumber IPv4Address:INADDR_LOOPBACK callback:^(NSError *error) {
            if(!error) {
                self.serverChannel = channel;
            }
        }];
    }
}


/** Whether or not the device is connected */
-(BOOL)isConnected {
    return _peerChannel != nil;
}

/** Closes the USB connection */
-(void)disconnect {
    [_serverChannel close];
    [_peerChannel close];
    _peerChannel = nil;
    _serverChannel = nil;
}

/** Sends data to the connected device
 * Uses NSKeyedArchiver to convert the object to data
 */
-(void)sendObject:(id)object type:(UInt32)type completion:(void (^)(BOOL))completion {
    NSData *data = [NSData toData:object];
    if(_peerChannel != nil) {
        [_peerChannel sendFrameOfType:type
                                  tag:PTFrameNoTag
                          withPayload:[data createReferencingDispatchData]
                             callback:^(NSError *error) {
                                 completion(YES);
                             }];
    }
    else {
        completion(NO);
    }
}

/** Sends data to the connected device */
-(void)sendData:(NSData *)data type:(UInt32)type completion:(void (^)(BOOL))completion {
    if(_peerChannel != nil) {
        [_peerChannel sendFrameOfType:type tag:PTFrameNoTag withPayload:[data createReferencingDispatchData] callback:^(NSError *error) {
            completion(YES);
        }];
    } else {
        completion(false);
    }
}

/** Sends data to the connected device */
-(void)sendDispatchData:(dispatch_data_t)dispatchData type:(UInt32)type completion:(void (^)(BOOL))completion {
    if(_peerChannel != nil) {
        [_peerChannel sendFrameOfType:type tag:PTFrameNoTag withPayload:dispatchData callback:^(NSError *error) {
            completion(YES);
        }];
    } else {
        completion(false);
    }
}

#pragma mark - PTChannelDelegate

-(BOOL)ioFrameChannel:(PTChannel *)channel shouldAcceptFrameOfType:(uint32_t)type tag:(uint32_t)tag payloadSize:(uint32_t)payloadSize {
    // Check if the channel is our connected channel; otherwise ignore it
    if(channel != _peerChannel) {
        return NO;
    } else {
        return [self.delegate peertalkShouldAcceptDataOfType:type];
    }
}

-(void)ioFrameChannel:(PTChannel *)channel didReceiveFrameOfType:(uint32_t)type tag:(uint32_t)tag payload:(PTData *)payload {
    // Creates the data
    NSData *data = [NSData dataWithContentsOfDispatchData:payload.dispatchData];
    [self.delegate peertalkDidReceiveData:data ofType:type];
}

-(void)ioFrameChannel:(PTChannel *)channel didEndWithError:(NSError *)error {
    [self printDebug:[NSString stringWithFormat:@"ERROR (Connection ended): %@", error.description]];
    _peerChannel = nil;
    _serverChannel = nil;
    [self.delegate peertalkDidChangeConnection:NO];
}

-(void)ioFrameChannel:(PTChannel *)channel didAcceptConnection:(PTChannel *)otherChannel fromAddress:(PTAddress *)address {
    // Cancel any existing connections
    if (_peerChannel != nil) {
        [_peerChannel cancel];
    }
    
    // Update the peer channel and information
    _peerChannel = otherChannel;
    _peerChannel.userInfo = address;
    [self printDebug:@"SUCCESS (Connected to channel)"];
    [self.delegate peertalkDidChangeConnection:YES];
}


@end

#endif



@interface PTManagerDesktop () <PTChannelDelegate>
{
    dispatch_queue_t notConnectedQueue;
}
@property (assign) int portNumber;
@property (assign, nonatomic) BOOL notConnectedQueueSuspended;
@property (retain, nonatomic) PTChannel *connectedChannel;
@end
static PTManagerDesktop *dinstance = nil;
@implementation PTManagerDesktop {
    
}
@synthesize connectedChannel = _connectedChannel;
@synthesize delegate;
@synthesize debugMode;
+(id <PTManager>)sharedManager {
    if(!dinstance) {
        dinstance = [PTManagerDesktop new];
    }
    return dinstance;
}

-(id)init {
    notConnectedQueue = dispatch_queue_create("PTManagerDesktop.notConnectedQueue", NULL);
    _reconnectDelay = 1.0;
    self.debugMode = YES;
    return self;
}
-(void)setConnectedChannel:(PTChannel *)connectedChannel {
    _connectedChannel = connectedChannel;
    // Toggle the notConnectedQueue depending on if we are connected or not
    if(_connectedChannel == nil && _notConnectedQueueSuspended) {
        dispatch_resume(notConnectedQueue);
        _notConnectedQueueSuspended = NO;
    } else if (_connectedChannel != nil && !_notConnectedQueueSuspended) {
        dispatch_suspend(notConnectedQueue);
        _notConnectedQueueSuspended = YES;
    }
    
    // Reconnect to the device if we were originally connecting to one
    if(_connectedChannel == nil && _connectingToDeviceID != nil) {
        [self enqueueConnectToUSBDevice];
    }
}

-(void)connect:(int)portNumber {
    if(!self.isConnected) {
        self.portNumber = portNumber;
        [self startListeningForDevices];
        [self enqueueConnectToLocalIPv4Port];
    }
}
/** Whether or not the device is connected */
-(BOOL)isConnected {
    return _connectedChannel != nil;
}

-(void)disconnect {
    if(self.connectedDeviceID != nil && self.connectedChannel != nil) {
        [self.connectedChannel close];
        self.connectedChannel = nil;
    }
}

-(void)sendObject:(id)object type:(UInt32)type completion:(void (^)(BOOL))completion {
    NSData *data = [NSData toData:object];
    if(self.connectedChannel != nil) {
        [self.connectedChannel sendFrameOfType:type tag:PTFrameNoTag withPayload:[data createReferencingDispatchData] callback:^(NSError *error) {
            completion(true);
        }];
    } else {
        completion(false);
    }
}
-(void)sendData:(NSData *)data type:(UInt32)type completion:(void (^)(BOOL))completion {
    if(self.connectedChannel != nil) {
        [self.connectedChannel sendFrameOfType:type tag:PTFrameNoTag withPayload:[data createReferencingDispatchData] callback:^(NSError *error) {
            completion(true);
        }];
    } else {
        completion(false);
    }
}
-(void)sendDispatchData:(dispatch_data_t)dispatchData type:(UInt32)type completion:(void (^)(BOOL))completion {
    if(self.connectedChannel != nil) {
        [self.connectedChannel sendFrameOfType:type tag:PTFrameNoTag withPayload:dispatchData callback:^(NSError *error) {
            completion(true);
        }];
    } else {
        completion(false);
    }
}


-(void)startListeningForDevices {
    
    // Grab the notification center instance
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    
    // Add an observer for when the device attaches
    [nc addObserverForName:PTUSBDeviceDidAttachNotification object:[PTUSBHub sharedHub] queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        // Grab the device ID from the user info
        NSNumber *deviceID = note.userInfo[@"DeviceID"];
        [self printDebug:[NSString stringWithFormat:@"Attached to device %@", deviceID]];
        
        // Update our properties on our thread
        dispatch_async(notConnectedQueue, ^{
            if(self.connectingToDeviceID == nil || ![deviceID isEqual:self.connectingToDeviceID]) {
                [self disconnect];
                self.connectingToDeviceID = deviceID;
                self.connectedDeviceProperties = note.userInfo[@"Properties"];
                [self enqueueConnectToUSBDevice];
            }
        });
    }];
    
    
    // Add an observer for when the device detaches
    [nc addObserverForName:PTUSBDeviceDidDetachNotification object:[PTUSBHub sharedHub] queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        // Grab the device ID from the user info
        NSNumber *deviceID = note.userInfo[@"DeviceID"];
        [self printDebug:[NSString stringWithFormat:@"Detached from device: %@", deviceID]];
        
        // Update our properties on our thread
        if([self.connectingToDeviceID isEqual:deviceID]) {
            self.connectedDeviceProperties = nil;
            self.connectingToDeviceID = nil;
            if (self.connectedChannel != nil) {
                [self.connectedChannel close];
            }
        }
    }];
    
}


-(void)enqueueConnectToUSBDevice {
    dispatch_async(notConnectedQueue, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self connectToUsbDevice];
        });
    });
}
-(void)connectToUsbDevice {
    // Create the new channel
    PTChannel *channel = [PTChannel channelWithDelegate:self];
    channel.userInfo = _connectingToDeviceID;
    channel.delegate = self;
    
    [channel connectToPort:self.portNumber overUSBHub:[PTUSBHub sharedHub] deviceID:_connectingToDeviceID callback:^(NSError *error) {
        if(error) {
            [self printDebug:[NSString stringWithFormat:@"connectToUSBDevice : %@", [error description]]];
            // Reconnect to the device
            if(channel.userInfo != nil && [(NSNumber *)channel.userInfo isEqual:self.connectingToDeviceID])
            {
                [self performSelector:@selector(enqueueConnectToUSBDevice) withObject:nil afterDelay:self.reconnectDelay];
            }
        }
        else {
            self.connectedDeviceID = self.connectingToDeviceID;
            self.connectedChannel = channel;
            [self.delegate peertalkDidChangeConnection:YES];
            // Check the device properties
            [self printDebug:self.connectedDeviceProperties.description];
        }
    }];
}

-(void)connectToLocalIPv4Port {
    PTChannel *channel = [PTChannel channelWithDelegate:self];
    channel.userInfo = [NSString stringWithFormat:@"127.0.0.1:%d",self.portNumber];
    
    [channel connectToPort:self.portNumber IPv4Address:INADDR_LOOPBACK callback:^(NSError *error, PTAddress *address) {
        if(!error) {
            [self disconnect];
            self.connectedChannel = channel;
            channel.userInfo = address;
        }
        else {
            [self printDebug:[NSString stringWithFormat:@"connectToLocalIPv4Port : %@", [error description]]];
        }
        
        [self performSelector:@selector(enqueueConnectToLocalIPv4Port) withObject:nil afterDelay:self.reconnectDelay];
    }];
}

-(void)enqueueConnectToLocalIPv4Port {
    dispatch_async(notConnectedQueue, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self connectToLocalIPv4Port];
        });
    });
}

-(void)didDisconnectFromDevice:(NSNumber *)deviceID {
    [self printDebug:@"Disconnected from device"];
    [self.delegate peertalkDidChangeConnection:NO];
    
    // Notify the class that the device has changed
    if([self.connectedDeviceID isEqual:deviceID]) {
        [self willChangeValueForKey:@"connectedDeviceID"];
        self.connectedDeviceID = nil;
        [self didChangeValueForKey:@"connectedDeviceID"];
    }
}


-(void)printDebug:(NSString *)string
{
    if(self.debugMode)
    {
        NSLog(@"%@", string);
    }
}

#pragma mark - PTChannelDelegate
-(BOOL)ioFrameChannel:(PTChannel *)channel shouldAcceptFrameOfType:(uint32_t)type tag:(uint32_t)tag payloadSize:(uint32_t)payloadSize {
    return [self.delegate peertalkShouldAcceptDataOfType:type];
}
-(void)ioFrameChannel:(PTChannel *)channel didReceiveFrameOfType:(uint32_t)type tag:(uint32_t)tag payload:(PTData *)payload {
    NSData *data = [NSData dataWithContentsOfDispatchData:payload.dispatchData];
    [delegate peertalkDidReceiveData:data ofType:type];
}
-(void)ioFrameChannel:(PTChannel *)channel didEndWithError:(NSError *)error {
    // Check that the disconnected device is the current device
    if(self.connectedDeviceID != nil && [self.connectedDeviceID isEqual:channel.userInfo]) {
        [self didDisconnectFromDevice:self.connectedDeviceID];
    }
    
    // Check that the disconnected channel is the current one
    if (self.connectedChannel == channel) {
        [self printDebug:[NSString stringWithFormat:@"Disconnected from %@", channel.userInfo]];
        self.connectedChannel = nil;
    }
}

@end



