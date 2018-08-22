//
//  ViewController.m
//  AresiOS
//
//  Created by SuXinDe on 2018/8/22.
//  Copyright © 2018年 su xinde. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

#import "PTUSBHub.h"
#import "PTChannel.h"
#import "PTProtocol.h"
#import "USBProtocol.h"


@interface ViewController () <PTChannelDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, strong) PTChannel *peerChannel;
@property (nonatomic, strong) PTChannel *serverChannel;

@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) AVCaptureDevice *captureDevice;

@property (nonatomic, strong) dispatch_queue_t bufferQueue;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self prepare];

}

- (void)prepare {
    self.captureSession = [[AVCaptureSession alloc] init];
    self.bufferQueue = dispatch_queue_create("buffer", NULL);
    
    PTChannel *c = [PTChannel channelWithDelegate:self];
    [c listenOnPort:2345 IPv4Address:INADDR_LOOPBACK callback:^(NSError *error) {
        if (error) {
            NSLog(@"%@", error.localizedDescription);
        } else {
            self.serverChannel = c;
        }
    }];
    
    self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    NSArray *devices = [AVCaptureDevice devices];
    for (AVCaptureDevice *device in devices) {
        if ([device hasMediaType:AVMediaTypeVideo]) {
            if (device.position == AVCaptureDevicePositionBack) {
                self.captureDevice = device;
                [self beginSession];
                //break;
            }
        }
    }
    
    AVCaptureVideoDataOutput *videoDataOutput = [AVCaptureVideoDataOutput new];
    NSString *CVPixelBufferPixelFormatTypeKey = (__bridge id)kCVPixelBufferPixelFormatTypeKey;
    videoDataOutput.videoSettings = @{
                                      CVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)
                                      };
    [videoDataOutput setSampleBufferDelegate:self
                                       queue:self.bufferQueue];
    [self.captureSession addOutput:videoDataOutput];
}

- (void)beginSession {
    [self.captureSession addInput:[AVCaptureDeviceInput deviceInputWithDevice:self.captureDevice error:nil]];
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    
    if (self.previewLayer) {
        [self.view.layer addSublayer:self.previewLayer];
        self.previewLayer.frame = self.view.layer.frame;
    }
    [self.captureSession startRunning];
}


#pragma mark -
- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (imageBuffer) {
        CIImage *ciImage = [[CIImage alloc] initWithCVPixelBuffer:imageBuffer];
        
        CIContext *context = [CIContext new];
        CGImageRef cgImage = [context createCGImage:ciImage fromRect:ciImage.extent];
        if (cgImage) {
            UIImage *uiImage = [UIImage imageWithCGImage:cgImage];
            NSData *data = UIImageJPEGRepresentation(uiImage, 0.5);
            if (data) {
                [self.peerChannel sendFrameOfType:USBProtocolData
                                              tag:self.peerChannel.protocol.newTag?:0
                                      withPayload:[data createReferencingDispatchData]
                                         callback:nil];
            }
        }
    }
}

#pragma mark -
// Invoked when a new frame has arrived on a channel.
- (void)ioFrameChannel:(PTChannel*)channel
 didReceiveFrameOfType:(uint32_t)type
                   tag:(uint32_t)tag
               payload:(PTData*)payload {
    
    if (type == USBProtocolPing) {
        [self.peerChannel sendFrameOfType:USBProtocolPong
                                      tag:tag
                              withPayload:nil
                                 callback:nil];
    }
}

// Invoked to accept an incoming frame on a channel. Reply NO ignore the
// incoming frame. If not implemented by the delegate, all frames are accepted.
- (BOOL)ioFrameChannel:(PTChannel*)channel
shouldAcceptFrameOfType:(uint32_t)type
                   tag:(uint32_t)tag
           payloadSize:(uint32_t)payloadSize {
    
    if (channel != self.peerChannel) {
        return FALSE;
    }
    if (type != USBProtocolPing) {
        [channel close];
        return FALSE;
    }
    return YES;
}

// Invoked when the channel closed. If it closed because of an error, *error* is
// a non-nil NSError object.
- (void)ioFrameChannel:(PTChannel*)channel
       didEndWithError:(NSError*)error {
    
    if (error) {
        NSLog(@"%@", error.localizedDescription);
    } else {
        NSLog(@"Disconnected");
    }
    
    
}

// For listening channels, this method is invoked when a new connection has been
// accepted.
- (void)ioFrameChannel:(PTChannel*)channel
   didAcceptConnection:(PTChannel*)otherChannel
           fromAddress:(PTAddress*)address {
    if (self.peerChannel) {
        [self.peerChannel cancel];
    }
    self.peerChannel = otherChannel;
    self.peerChannel.userInfo = address;
}


@end
