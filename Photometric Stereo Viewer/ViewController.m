//
//  ViewController.m
//  RealtimeVideoFilter
//
//  Created by Altitude Labs on 23/12/15.
//  Copyright © 2015 Victor. All rights reserved.
//

#import "ViewController.h"
#import <GLKit/GLKit.h>
#import "AppDelegate.h"
#import <QuartzCore/QuartzCore.h>

@import GameController;



@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property GLKView *videoPreviewViewL;
@property GLKView *videoPreviewViewR;

@property CIContext *ciContext;
@property EAGLContext *eaglContext;
@property CGRect videoPreviewViewBounds;

@property AVCaptureDevice *videoDevice;
@property AVCaptureSession *captureSession;
@property dispatch_queue_t captureSessionQueue;
@property (nonatomic, strong) id connectObserver;
@property (nonatomic, strong) id disconnectObserver;

@property (nonatomic, strong) GCController *controller;

@end

@implementation ViewController


- (void)viewDidLoad {
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    [super viewDidLoad];
    NSLog(@"view did load called");
    
    // remove the view's background color; this allows us not to use the opaque property (self.view.opaque = NO) since we remove the background color drawing altogether
    self.view.backgroundColor = [UIColor clearColor];
    
    // setup the GLKView for video/image preview
    UIView *window = ((AppDelegate *)[UIApplication sharedApplication].delegate).window;
    _eaglContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    
    CGRect bounds = window.bounds;
    CGRect boundsL = bounds;
    boundsL.size.height = bounds.size.height/2;
    CGRect boundsR = bounds;
    boundsR.size.height = bounds.size.height/2;
    boundsR.origin.y = boundsR.size.height;
    
    _videoPreviewViewL = [[GLKView alloc] initWithFrame:boundsL context:_eaglContext];
    _videoPreviewViewR = [[GLKView alloc] initWithFrame:boundsR context:_eaglContext];
    
    _videoPreviewViewL.enableSetNeedsDisplay = NO;
    _videoPreviewViewR.enableSetNeedsDisplay = NO;
    
    _videoPreviewViewL.frame = boundsL;
    _videoPreviewViewR.frame = boundsR;
    
    [window addSubview:_videoPreviewViewL];
    [window addSubview:_videoPreviewViewR];
    
    // bind the frame buffer to get the frame buffer width and height;
    // the bounds used by CIContext when drawing to a GLKView are in pixels (not points),
    // hence the need to read from the frame buffer's width and height;
    // in addition, since we will be accessing the bounds in another queue (_captureSessionQueue),
    // we want to obtain this piece of information so that we won't be
    // accessing _videoPreviewView's properties from another thread/queue
    [_videoPreviewViewL bindDrawable];
    [_videoPreviewViewR bindDrawable];
    
    _videoPreviewViewBounds = CGRectZero;
    _videoPreviewViewBounds.size.width = _videoPreviewViewL.drawableWidth;
    _videoPreviewViewBounds.size.height = _videoPreviewViewL.drawableHeight;
    
    
    // create the CIContext instance, note that this must be done after _videoPreviewView is properly set up
    _ciContext = [CIContext contextWithEAGLContext:_eaglContext options:@{kCIContextWorkingColorSpace : [NSNull null]} ];
    
    
    // set perspective of right and left views
    CATransform3D rotationAndPerspectiveTransform = CATransform3DIdentity;
    rotationAndPerspectiveTransform.m34 = 1.0 / -500;
    rotationAndPerspectiveTransform = CATransform3DRotate(rotationAndPerspectiveTransform, -5.0f * M_PI / 180.0f, 1.0f, 0.0f, 0.0f);
    rotationAndPerspectiveTransform = CATransform3DRotate(rotationAndPerspectiveTransform, 90.0f * M_PI / 180.0f, 0.0f, 0.0f, 1.0f);
    _videoPreviewViewL.layer.transform = rotationAndPerspectiveTransform;
    
    rotationAndPerspectiveTransform = CATransform3DIdentity;
    rotationAndPerspectiveTransform.m34 = 1.0 / -500;
    rotationAndPerspectiveTransform = CATransform3DRotate(rotationAndPerspectiveTransform, 5.0f * M_PI / 180.0f, 1.0f, 0.0f, 0.0f);
    rotationAndPerspectiveTransform = CATransform3DRotate(rotationAndPerspectiveTransform, 90.0f * M_PI / 180.0f, 0.0f, 0.0f, 1.0f);
    _videoPreviewViewR.layer.transform = rotationAndPerspectiveTransform;
    
    
    // load png images to overlay on video
    NSString *path = [[NSBundle mainBundle] pathForResource:@"cat_l" ofType:@"png"];
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    self.overlayCI_L = [CIImage imageWithContentsOfURL:fileURL];
    
    path = [[NSBundle mainBundle] pathForResource:@"cat_r" ofType:@"png"];
    fileURL = [NSURL fileURLWithPath:path];
    self.overlayCI_R = [CIImage imageWithContentsOfURL:fileURL];
    
    
    if ([[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count] > 0)
    {
        [self _start];
    }
    else
    {
        NSLog(@"No device with AVMediaTypeVideo");
    }
}


-(void)viewWillDisappear:(BOOL)animated{
    NSLog(@"view will disappear");
    [_captureSession stopRunning];
    [_videoPreviewViewL removeFromSuperview];
    [_videoPreviewViewR removeFromSuperview];
    
    _videoPreviewViewL = nil;
    _videoPreviewViewR = nil;
    
    self.captureSession = nil;
    
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
}


- (void)_start
{
    // get the input device and also validate the settings
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    
    AVCaptureDevicePosition position = AVCaptureDevicePositionBack;
    
    for (AVCaptureDevice *device in videoDevices)
    {
        if (device.position == position) {
            _videoDevice = device;
            break;
        }
    }
    
    // obtain device input
    NSError *error = nil;
    AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:_videoDevice error:&error];
    if (!videoDeviceInput)
    {
        NSLog(@"%@", [NSString stringWithFormat:@"Unable to obtain video device input, error: %@", error]);
        return;
    }
    
    // obtain the preset and validate the preset
    NSString *preset = AVCaptureSessionPresetHigh;
    if (![_videoDevice supportsAVCaptureSessionPreset:preset])
    {
        NSLog(@"%@", [NSString stringWithFormat:@"Capture session preset not supported by video device: %@", preset]);
        return;
    }
    
    // create the capture session
    _captureSession = [[AVCaptureSession alloc] init];
    _captureSession.sessionPreset = preset;
    
    // CoreImage wants BGRA pixel format
    NSDictionary *outputSettings = @{ (id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInteger:kCVPixelFormatType_32BGRA]};
    // create and configure video data output
    AVCaptureVideoDataOutput *videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    videoDataOutput.videoSettings = outputSettings;
    
    // create the dispatch queue for handling capture session delegate method calls
    _captureSessionQueue = dispatch_queue_create("capture_session_queue", NULL);
    [videoDataOutput setSampleBufferDelegate:self queue:_captureSessionQueue];
    
    videoDataOutput.alwaysDiscardsLateVideoFrames = YES;
    
    // begin configure capture session
    [_captureSession beginConfiguration];
    
    if (![_captureSession canAddOutput:videoDataOutput])
    {
        NSLog(@"Cannot add video data output");
        _captureSession = nil;
        return;
    }
    
    // connect the video device input and video data and still image outputs
    [_captureSession addInput:videoDeviceInput];
    [_captureSession addOutput:videoDataOutput];
    
    [_captureSession commitConfiguration];
    
    // then start everything
    [_captureSession startRunning];
}


- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    // get current frame from camera
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CIImage *sourceImage = [CIImage imageWithCVPixelBuffer:(CVPixelBufferRef)imageBuffer options:nil];
    CGRect sourceExtent = sourceImage.extent;
    
    // set size or regions to display the images
    CGFloat previewAspect = _videoPreviewViewBounds.size.width  / _videoPreviewViewBounds.size.height;

    CGRect drawRect1 = sourceExtent;
    CGRect drawRect2 = sourceExtent;
    CGRect drawRect3 = self.overlayCI_L.extent;
    CGRect drawRect4 = self.overlayCI_R.extent;;

    drawRect1.origin.x += (drawRect1.size.width - drawRect1.size.height * previewAspect) / 2.0;
    drawRect1.size.width = drawRect1.size.height * previewAspect;
    
    drawRect2.origin.x += (drawRect2.size.width - drawRect2.size.height * previewAspect) / 2.0;
    drawRect2.size.width = drawRect2.size.height * previewAspect;
    
    drawRect3.origin.x = -1000;
    drawRect3.origin.y = -800;
    drawRect3.size.width = drawRect3.size.height * 5 * previewAspect;
    drawRect3.size.height = drawRect3.size.width / previewAspect;
    
    drawRect4.origin.x = -1000;
    drawRect4.origin.y = -800;
    drawRect4.size.width = drawRect4.size.height * 5 * previewAspect;
    drawRect4.size.height = drawRect4.size.width / previewAspect;

    // display image for left side
    [_videoPreviewViewL bindDrawable];
    
    if (_eaglContext != [EAGLContext currentContext])
        [EAGLContext setCurrentContext:_eaglContext];
    
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    
    // display frame from camera
    if (sourceImage)
        [_ciContext drawImage:sourceImage inRect:_videoPreviewViewBounds fromRect:drawRect1];
    // overlay png image
    if (self.overlayCI_L)
        [_ciContext drawImage:self.overlayCI_L inRect:_videoPreviewViewBounds fromRect:drawRect3];

    [_videoPreviewViewL display];
    
    
    // display image for right side
    [_videoPreviewViewR bindDrawable];
    
    if (_eaglContext != [EAGLContext currentContext])
        [EAGLContext setCurrentContext:_eaglContext];
    
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    
    // display frame from camera
    if (sourceImage)
        [_ciContext drawImage:sourceImage inRect:_videoPreviewViewBounds fromRect:drawRect2];
    // overlay png image
    if (self.overlayCI_R)
        [_ciContext drawImage:self.overlayCI_R inRect:_videoPreviewViewBounds fromRect:drawRect4];
    
    [_videoPreviewViewR display];
}


@end
