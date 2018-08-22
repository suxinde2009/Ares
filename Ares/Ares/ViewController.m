//
//  ViewController.m
//  Ares
//
//  Created by SuXinDe on 2018/8/22.
//  Copyright © 2018年 su xinde. All rights reserved.
//

#import "ViewController.h"

#import "PTChannel.h"
#import "PTProtocol.h"
#import "PTUSBHub.h"
#import "USBProtocol.h"

@interface ViewController () <PTChannelDelegate>
@property (nonatomic, strong) dispatch_queue_t notConnetedQueue;

@property (nonatomic, strong) NSNumber *connectingToDeviceID;
@property (nonatomic, strong) NSNumber *connectedDeviceID;
@property (nonatomic, assign) BOOL notConnectedChannel;
@property (nonatomic, assign) PTChannel *connectedChannel;

@property (nonatomic, weak) IBOutlet NSImageView *imageView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.notConnetedQueue = dispatch_queue_create("notConnectedQueue", NULL);
    self.notConnectedChannel = FALSE;
    [self startListeningForDevices];
    [self ping];
    
}

- (void)connectToUSBDevice {
    PTChannel *channel = [PTChannel channelWithDelegate:self];
    channel.userInfo = self.connectingToDeviceID;
    [channel connectToPort:2345
                overUSBHub:[PTUSBHub sharedHub]
                  deviceID:self.connectingToDeviceID
                  callback:^(NSError *error) {
                      if (!error) {
                          self.connectedDeviceID = self.connectingToDeviceID;
                          self.connectedChannel = channel;
                      } else {
                          // TODO: 错误处理
                          
                          if ([error.domain isEqualToString:PTUSBHubErrorDomain] &&
                              error.code == PTUSBHubErrorConnectionRefused) {
                              NSLog(@"Failed to connect to device");
                          } else {
                              NSLog(@"Failed to connect to 127.0.0.1:2345: %@", error.localizedDescription);
                          }
                          
                          NSNumber *deviceID = channel.userInfo;
                          if (deviceID.integerValue == self.connectingToDeviceID.integerValue) {
                              [self performSelector:@selector(enqueueConnectToUSBDevice)
                                         withObject:nil
                                         afterDelay:1.0f];
                          }
                          
                      }
                  }];
}

- (void)disconnectFromCurrentChannel {
    [self.connectedChannel close];
    self.connectedChannel = nil;
    self.connectedDeviceID = nil;
}

- (void)enqueueConnectToUSBDevice {
    dispatch_async(self.notConnetedQueue, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self connectToUSBDevice];
        });
    });
}

- (void)startListeningForDevices {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:PTUSBDeviceDidAttachNotification
                    object:[PTUSBHub sharedHub]
                     queue:nil
                usingBlock:^(NSNotification * _Nonnull note) {
                    NSNumber *deviceID = note.userInfo[@"DeviceID"];
                    
                    dispatch_async(self.notConnetedQueue, ^{
                        BOOL flag = self.connectedDeviceID == nil;
                        if (self.connectedDeviceID) {
                            flag = flag || [deviceID isEqual:self.connectedDeviceID];
                            
                            if (flag) {
                                [self disconnectFromCurrentChannel];
                                self.connectingToDeviceID = deviceID;
                                [self enqueueConnectToUSBDevice];
                            }
                        }
                    });
                }];
    
    [nc addObserverForName:PTUSBDeviceDidAttachNotification
                    object:[PTUSBHub sharedHub]
                     queue:nil
                usingBlock:^(NSNotification * _Nonnull note) {
                    NSNumber *deviceID = note.userInfo[@"DeviceID"];
                    if (self.connectingToDeviceID && [self.connectingToDeviceID isEqual:deviceID]) {
                        self.connectingToDeviceID = nil;
                        if (self.connectedChannel != nil) {
                            [self.connectedChannel close];
                            self.connectedChannel = nil;
                        }
                    }
                }];
    
    
}

- (void)ping {
    if (_connectedChannel && _connectedChannel.protocol) {
        [_connectedChannel sendFrameOfType:USBProtocolPing tag:_connectedChannel.protocol.newTag withPayload:nil callback:^(NSError *error) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1000 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self ping];
            });
            NSLog(@"Send Ping");
        }];
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1000 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self ping];
        });
    }
}

- (void)pong {
    NSLog(@"Received Pong");
}


- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
}

#pragma mark -
// Invoked when a new frame has arrived on a channel.
- (void)ioFrameChannel:(PTChannel*)channel
 didReceiveFrameOfType:(uint32_t)type
                   tag:(uint32_t)tag
               payload:(PTData*)payload {
    
    if (type == USBProtocolPong) {
        [self pong];
    } else if (type == USBProtocolData) {
        NSData *data = [NSData dataWithContentsOfDispatchData:payload.dispatchData];
        NSImage *image = [[NSImage alloc] initWithData:data];
        if (image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.imageView.image = image;
            });
        }
    }
}

// Invoked to accept an incoming frame on a channel. Reply NO ignore the
// incoming frame. If not implemented by the delegate, all frames are accepted.
- (BOOL)ioFrameChannel:(PTChannel*)channel
shouldAcceptFrameOfType:(uint32_t)type
                   tag:(uint32_t)tag
           payloadSize:(uint32_t)payloadSize {
    return YES;
}

// Invoked when the channel closed. If it closed because of an error, *error* is
// a non-nil NSError object.
- (void)ioFrameChannel:(PTChannel*)channel
       didEndWithError:(NSError*)error {
    
}

// For listening channels, this method is invoked when a new connection has been
// accepted.
- (void)ioFrameChannel:(PTChannel*)channel
   didAcceptConnection:(PTChannel*)otherChannel
           fromAddress:(PTAddress*)address {
    
}

@end
