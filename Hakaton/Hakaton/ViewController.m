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


@interface ViewController () <ARSCNViewDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

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



@end

    
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Set the view's delegate
    self.sceneView.delegate = self;
    
    // Show statistics such as fps and timing information
    self.sceneView.showsStatistics = YES;
    
    // Create a new scene
    SCNScene *scene = [SCNScene sceneNamed:@"art.scnassets/ship.scn"];
    
    // Set the scene to the view
    self.sceneView.scene = scene;
    [self setupAVCapture];
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

- (void)updatePreviewLayer:(AVCaptureConnection*)layer orientation:(AVCaptureVideoOrientation)orientation {
    self.previewLayer.connection.videoOrientation = orientation;
    self.previewLayer.frame = self.view.bounds;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    AVCaptureConnection *connection = [self.previewLayer connection];
    switch ([self.previewLayer connection].videoOrientation) {
        case AVCaptureVideoOrientationPortrait:
            [self updatePreviewLayer:connection orientation:AVCaptureVideoOrientationPortrait];
            break;
        case AVCaptureVideoOrientationLandscapeLeft:
            [self updatePreviewLayer:connection orientation:AVCaptureVideoOrientationLandscapeLeft];
            break;
        case AVCaptureVideoOrientationLandscapeRight:
            [self updatePreviewLayer:connection orientation:AVCaptureVideoOrientationLandscapeRight];
            break;
        case AVCaptureVideoOrientationPortraitUpsideDown:
            [self updatePreviewLayer:connection orientation:AVCaptureVideoOrientationPortraitUpsideDown];
            break;
            
        default:
            [self updatePreviewLayer:connection orientation:AVCaptureVideoOrientationPortrait];
            break;
    }
    self.previewLayer.frame = self.rootLayer.bounds;
}

- (void)setupQuery {
    dispatch_queue_attr_t qosAttribute = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_USER_INITIATED, 0);
    self.videoDataOutputQueue = dispatch_queue_create("cameraQueue", qosAttribute);
}

- (void)setupAVCapture {
    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
    [self.session beginConfiguration];
    self.session.sessionPreset = AVCaptureSessionPreset640x480;
    if ([self.session canAddInput:deviceInput]) {
        [self.session addInput:deviceInput];
    }
    if ([self.session canAddOutput:self.videoDataOutput]) {
        [self.session addOutput:self.videoDataOutput];
        self.videoDataOutput.alwaysDiscardsLateVideoFrames = YES;
        NSNumber* value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];
        NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
        NSDictionary* videoSettings = [NSDictionary dictionaryWithObject:value forKey:key];
        self.videoDataOutput.videoSettings = videoSettings;
        [self.videoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];
        AVCaptureConnection *captureConnection = [_videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
        captureConnection.enabled = true;
        [videoDevice lockForConfiguration:nil];
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions([[videoDevice activeFormat] formatDescription]);
        self.bufferSize = CGSizeMake(dimensions.width, dimensions.height);
        [videoDevice unlockForConfiguration];
    }
    [self.session commitConfiguration];
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    self.previewLayer.videoGravity = kCAGravityResizeAspectFill;
    self.rootLayer = self.previewView.layer;
    self.previewView.frame = self.rootLayer.bounds;
    [self.rootLayer addSublayer:self.previewLayer];
    
    [self setupLayers];
    [self updateLayerGeometry];
    [self setupVision];
    
    [self startCaptureSession];
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
    [CATransaction setValue:kCFBooleanTrue forKey:kCATransactionDisableActions];
    self.detectionOverlay.sublayers = nil;
    for (VNRecognizedObjectObservation *observation in results) {
        VNClassificationObservation *topLabelObservation = observation.labels[0];
        CGRect objectBounds = VNImageRectForNormalizedRect(observation.boundingBox, self.bufferSize.width, self.bufferSize.height);
        CALayer *shapeLayer = [self createRoundedRectLayerWithBounds:objectBounds];
        CATextLayer *textLayer = [self createTextSubLayerInBounds:objectBounds identifier:topLabelObservation.identifier confidence:topLabelObservation.confidence];
        [shapeLayer addSublayer:textLayer];
        [self.detectionOverlay addSublayer:shapeLayer];
    }
    [self updateLayerGeometry];
    [CATransaction commit];
}

- (void)captureOutput:(AVCaptureOutput *)output didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CGImagePropertyOrientation exifOrientation = [self exifOrientationFromDeviceOrientation];
    VNImageRequestHandler *imageRequestHandler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer orientation:exifOrientation options:@{}];
    [imageRequestHandler performRequests:self.requests error:nil];
}

- (void)setupLayers {
    self.detectionOverlay = [CALayer new];
    
    self.detectionOverlay.name = @"DetectionOverlay";
    
    self.detectionOverlay.bounds = CGRectMake(0, 0, self.bufferSize.width, self.bufferSize.height);
    self.detectionOverlay.position = CGPointMake(CGRectGetMidX(self.rootLayer.bounds), CGRectGetMidY(self.rootLayer.bounds));
    [self.rootLayer addSublayer:self.detectionOverlay];
    
}

- (void)updateLayerGeometry {
    
    CGRect bounds = self.rootLayer.bounds;
    CGFloat scale;
    
    CGFloat xScale = bounds.size.width / self.bufferSize.height;
    CGFloat yScale = bounds.size.height / self.bufferSize.width;
    
    scale = MIN(xScale, yScale);
    if (CGFLOAT_MAX == scale) {
        scale = 1.0;
    }
    [CATransaction begin];
    [CATransaction setValue:kCFBooleanTrue forKey:kCATransactionDisableActions];
    
    [self.detectionOverlay setAffineTransform:CGAffineTransformScale(CGAffineTransformMakeRotation((M_PI / 2.0)), scale, -scale)];

    self.detectionOverlay.position = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    
    [CATransaction commit];
}

- (CATextLayer*)createTextSubLayerInBounds:(CGRect)bounds identifier:(NSString *)identifer confidence:(VNConfidence)confidence {
    
    CATextLayer *textLayer = [CATextLayer new];
    textLayer.name = @"Object Label";
    NSMutableAttributedString *formattedString = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\nConfidence:  %.2f",identifer,confidence]];
    
    UIFont *largeFont = [UIFont fontWithName:@"Helvetica" size:24.0];
    [formattedString addAttribute:NSFontAttributeName value:largeFont range:NSMakeRange(0, [identifer length])];
    
    textLayer.string = formattedString;
    textLayer.bounds = CGRectMake(0, 0, bounds.size.height - 10, bounds.size.width - 10);
    textLayer.position = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    textLayer.shadowOpacity = 0.7;
    textLayer.shadowOffset = CGSizeMake(2, 2);
   
    textLayer.foregroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:1].CGColor;
    textLayer.contentsScale = 2.0;// retina rendering
    // rotate the layer into screen orientation and scale and mirror
    [textLayer setAffineTransform:CGAffineTransformScale(CGAffineTransformMakeRotation(M_PI / 2.0), 1, -1)];
    return textLayer;
    
}

- (CALayer*)createRoundedRectLayerWithBounds:(CGRect)bounds {
    CALayer *shapeLayer = [CALayer new];
    shapeLayer.bounds = bounds;
    shapeLayer.position = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    shapeLayer.name = @"Found Object";
    
    shapeLayer.backgroundColor = [UIColor colorWithRed:1 green:1 blue:0.2 alpha:0.4].CGColor;
    shapeLayer.cornerRadius = 7;
    return shapeLayer;
}

- (void)startCaptureSession {
    [self.session startRunning];
}


- (void)teardownAVCapture {
    [self.previewLayer removeFromSuperlayer];
    self.previewLayer = nil;
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
            exifOrientation = kCGImagePropertyOrientationUp;
            break;
        default:
            exifOrientation = kCGImagePropertyOrientationUp;
            break;
    }
    return exifOrientation;
}

#pragma mark - ARSCNViewDelegate

/*
// Override to create and configure nodes for anchors added to the view's session.
- (SCNNode *)renderer:(id<SCNSceneRenderer>)renderer nodeForAnchor:(ARAnchor *)anchor {
    SCNNode *node = [SCNNode new];
 
    // Add geometry to the node...
 
    return node;
}
*/

- (void)session:(ARSession *)session didFailWithError:(NSError *)error {
    // Present an error message to the user
    
}

- (void)sessionWasInterrupted:(ARSession *)session {
    // Inform the user that the session has been interrupted, for example, by presenting an overlay
    
}

- (void)sessionInterruptionEnded:(ARSession *)session {
    // Reset tracking and/or remove existing anchors if consistent tracking is required
    
}

@end
