//
//  PeerTalkManager.h
//  iOSTabletEmulator
//
//  Created by Switt Kongdachalert on 30/1/18.
//  Copyright © 2018 Switt's Software. All rights reserved.
//

#import <Foundation/Foundation.h>
@class PTChannel;

@protocol PTManagerDelegate <NSObject>

/** Return whether or not you want to accept the specified data type */
-(BOOL)peertalkShouldAcceptDataOfType:(UInt32)type;

/** Runs when the device has received data */
-(void)peertalkDidReceiveData:(NSData *)data ofType:(UInt32)type;

/** Runs when the connection has changed */
-(void)peertalkDidChangeConnection:(BOOL)connected;
@end



@protocol PTManager <NSObject>

@property (assign) id <PTManagerDelegate> delegate;
@property (assign) BOOL debugMode;

/** Whether or not the device is connected */
@property (readonly) BOOL isConnected;

/** Begins to look for a device and connects when it finds one */
-(void)connect:(int)portNumber;

/** Closes the USB connection */
-(void)disconnect;

/** Sends data to the connected device
 * Uses NSKeyedArchiver to convert the object to data
 */
-(void)sendObject:(id)object type:(UInt32)type completion:(void (^)(BOOL success))completion;

/** Sends data to the connected device */
-(void)sendData:(NSData *)data type:(UInt32)type completion:(void (^)(BOOL success))completion;

/** Sends data to the connected device */
-(void)sendDispatchData:(dispatch_data_t)dispatchData type:(UInt32)type completion:(void (^)(BOOL success))completion;

+(id <PTManager>)sharedManager;
@end


#if TARGET_OS_IPHONE
@interface PTManagerMobile : NSObject <PTManager> {
}
@property (assign) int portNumber;
@property (assign) PTChannel *serverChannel;
@property (assign) PTChannel *peerChannel;
@end
#endif

#if TARGET_OS_MAC
@interface PTManagerDesktop : NSObject <PTManager> {
    
}
@property (retain, nonatomic) NSNumber *connectingToDeviceID;
@property (retain, nonatomic) NSNumber *connectedDeviceID;
@property (retain, nonatomic) NSDictionary *connectedDeviceProperties;

/** The interval for rechecking whether or not an iOS device is connected */
@property (assign, nonatomic) NSTimeInterval reconnectDelay;
@end
#endif