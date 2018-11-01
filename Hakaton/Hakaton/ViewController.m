//
//  ViewController.m
//  Hakaton
//
//  Created by Anton Zvonaryov on 31/10/2018.
//  Copyright © 2018 Sberbank. All rights reserved.
//

#import "ViewController.h"
#import <Vision/Vision.h>
#import <CoreML/CoreML.h>
#import "ObjectDetector.h"


@interface ViewController () <ARSCNViewDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, ARSessionDelegate>

@property (nonatomic, strong) IBOutlet ARSCNView *sceneView;

@property (nonatomic, strong) IBOutlet UIView *previewView;

@property (nonatomic, assign) CGSize bufferSize;
@property (nonatomic, strong) CALayer *rootLayer;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic, strong) dispatch_queue_t videoDataOutputQueue;

@property (nonatomic, strong) NSArray<VNRequest*> *requests;
@property (nonatomic, strong) CALayer *detectionOverlay;

@property (nonatomic, assign) int frameCounter;

@end

    
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupQuery];
    
//    self.session = [AVCaptureSession new];
//    self.videoDataOutput = [AVCaptureVideoDataOutput new];
    
    
    // Set the view's delegate
    self.sceneView.delegate = self;
    
    // Show statistics such as fps and timing information
    self.sceneView.showsStatistics = YES;
    
    // Create a new scene
    SCNScene *scene = [SCNScene sceneNamed:@"art.scnassets/ship.scn"];
    
    // Set the scene to the view
    self.sceneView.scene = scene;
   [self setupVision];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Create a session configuration
    ARWorldTrackingConfiguration *configuration = [ARWorldTrackingConfiguration new];

    // Run the view's session
    [self.sceneView.session runWithConfiguration:configuration];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // Pause the view's session
    [self.sceneView.session pause];
}


- (void)setupQuery {
    dispatch_queue_attr_t qosAttribute = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_USER_INITIATED, 0);
    self.videoDataOutputQueue = dispatch_queue_create("cameraQueue", qosAttribute);
}


- (NSError*)setupVision {
    NSError *error = nil;
    NSURL *modelUrl = [[NSBundle mainBundle] URLForResource:@"ObjectDetector" withExtension:@"mlmodelc"];
    MLModel *model = [[[ObjectDetector alloc] initWithContentsOfURL:modelUrl error:&error] model];
    VNCoreMLModel *visionModel = [VNCoreMLModel modelForMLModel:model error:nil];
    VNCoreMLRequest *objectRecognition = [[VNCoreMLRequest alloc] initWithModel:visionModel completionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray *resArray = request.results;
            [self drawVisionRequestResults:resArray];
        });
    }];
    self.requests = @[objectRecognition];
    return error;
}

- (void)drawVisionRequestResults:(NSArray*)results {
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    self.detectionOverlay.sublayers = nil;
    for (VNRecognizedObjectObservation *observation in results) {
        CGRect objectBounds = VNImageRectForNormalizedRect(observation.boundingBox, self.bufferSize.width, self.bufferSize.height);
        NSLog(@"%@",NSStringFromCGRect(objectBounds));
    }
    [CATransaction commit];
}


- (CGImagePropertyOrientation)exifOrientationFromDeviceOrientation {
    UIDeviceOrientation curDeviceOrientation = [[UIDevice currentDevice] orientation];
    CGImagePropertyOrientation exifOrientation;
    switch (curDeviceOrientation) {
        case UIDeviceOrientationPortraitUpsideDown:
            exifOrientation = kCGImagePropertyOrientationLeft;
            break;
        case UIDeviceOrientationLandscapeLeft:
            exifOrientation = kCGImagePropertyOrientationUpMirrored;
            break;
        case UIDeviceOrientationLandscapeRight:
            exifOrientation = kCGImagePropertyOrientationDown;
            break;
        case UIDeviceOrientationPortrait:
            exifOrientation = kCGImagePropertyOrientationRightMirrored;
            break;
        default:
            exifOrientation = kCGImagePropertyOrientationRightMirrored;
            break;
    }
    return exifOrientation;
}

#pragma mark - ARSessionDelegate


- (void)session:(ARSession *)session didUpdateFrame:(ARFrame *)frame {
    
    if (self.frameCounter == 60 || self.frameCounter == 0) {
        [self pixelBufferFromFrame:frame];
        self.frameCounter = 1;
    } else {
        self.frameCounter++;
    }
}

- (void)pixelBufferFromFrame:(ARFrame *)frame {
    CVImageBufferRef pixelBuffer = frame.capturedImage;
    CGImagePropertyOrientation exifOrientation = [self exifOrientationFromDeviceOrientation];
    VNImageRequestHandler *imageRequestHandler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer orientation:exifOrientation options:@{}];
    [imageRequestHandler performRequests:self.requests error:nil];
    
    NSLog(@"pixelBufferFromFrame");
}

@end
