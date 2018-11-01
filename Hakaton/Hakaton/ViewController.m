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
@property (nonatomic, assign) CGFloat bubbleDepth; // the 'depth' of 3D text
@property (nonatomic, copy) NSString *latestPrediction;// a variable containing the latest CoreML prediction
@property (nonatomic, assign) CGPoint point;

@property (nonatomic, strong) NSMutableDictionary *container;

@property (nonatomic, strong) UIView *rectV;

@end

    
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.rectV = [UIView new];
    [self.rectV setBackgroundColor:[UIColor colorWithRed:0 green:1 blue:0 alpha:0.3]];
    [self.view addSubview:self.rectV];
    [self setupQuery];
    self.container = [NSMutableDictionary dictionary];
//    self.session = [AVCaptureSession new];
//    self.videoDataOutput = [AVCaptureVideoDataOutput new];
    
    self.bubbleDepth = 0.01;
    self.latestPrediction = @"…";
    self.point = CGPointZero;
    // Set the view's delegate
    self.sceneView.delegate = self;
    
    // Show statistics such as fps and timing information
    self.sceneView.showsStatistics = YES;
   [self setupVision];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Create a session configuration
    ARWorldTrackingConfiguration *configuration = [ARWorldTrackingConfiguration new];

    // Run the view's session
    [self.sceneView.session runWithConfiguration:configuration];
    [self loopCoreMLUpdate];
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
    objectRecognition.imageCropAndScaleOption = VNImageCropAndScaleOptionCenterCrop;
    self.requests = @[objectRecognition];
    return error;
}

- (void)drawVisionRequestResults:(NSArray*)results {
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    self.detectionOverlay.sublayers = nil;
    for (VNRecognizedObjectObservation *observation in results) {
        
        
            self.latestPrediction = [[[observation labels] firstObject] identifier];
        
        CGFloat squard = 416.0;
        
        CGFloat offR = (MAX(self.bufferSize.width, self.bufferSize.height) - MIN(self.bufferSize.width, self.bufferSize.height))/2.0f;
        
        
       
        
            CGSize screenSize = [[UIScreen mainScreen] bounds].size;
            
            CGFloat scalefactor = MAX(screenSize.height/self.bufferSize.height, screenSize.width/self.bufferSize.width);
        
        CGFloat heightT = (squard * scalefactor);
        CGFloat widthT = (squard * scalefactor);
        
        
        

        
            CGFloat yOffset = (heightT - screenSize.height) / 2.0;
            CGFloat xOffset = (widthT - screenSize.width) / 2.0f;
        
            CGFloat sideBuf = squard * scalefactor;
        
        
        
            CGRect objectBounds = VNImageRectForNormalizedRect(observation.boundingBox, sideBuf, sideBuf);
         
        
            NSLog(@"%@\n%@\n%@\n",NSStringFromCGRect(objectBounds),NSStringFromCGSize(screenSize),NSStringFromCGSize(self.bufferSize));
            
            objectBounds.origin.x -= xOffset;
            objectBounds.origin.y -= yOffset;
        
        
        
            
        [self.rectV setFrame:objectBounds];
           
            
        if (![self.container objectForKey:self.latestPrediction]) {
            [self.container setObject:observation.uuid forKey:self.latestPrediction];
            self.point = CGPointMake(objectBounds.origin.x + objectBounds.size.width /2.0f, objectBounds.origin.y + objectBounds.size.height / 2.0);
            
            [self handleTapGestureRecognize:nil];
        } else {
            
        }
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
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    self.bufferSize = CGSizeMake(width, height);
    CGImagePropertyOrientation exifOrientation = [self exifOrientationFromDeviceOrientation];
    VNImageRequestHandler *imageRequestHandler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer orientation:exifOrientation options:@{}];
    [imageRequestHandler performRequests:self.requests error:nil];
    
    NSLog(@"pixelBufferFromFrame");
}


- (void)classificationCompleteHandler:(VNRequest *)request {
    
    VNRecognizedObjectObservation *result = request.results.firstObject;
    NSString *str = [result.labels.firstObject identifier];
    
    if (str != nil) {
       
        dispatch_async(dispatch_get_main_queue(), ^{
            CGFloat sst = MIN([UIScreen mainScreen].bounds.size.width,  [UIScreen mainScreen].bounds.size.height);
            CGFloat ssv = MAX([UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
            CGRect objectBounds = VNImageRectForNormalizedRect(result.boundingBox, sst, ssv);
            objectBounds.origin.y += fabs(sst-ssv);
            self.point = CGPointMake(objectBounds.origin.x + (objectBounds.size.width / 2.0), objectBounds.origin.y + (objectBounds.size.height / 2.0));
            self.latestPrediction = str;
        });
    }
}

- (void)loopCoreMLUpdate {
    // Continuously run CoreML whenever it's ready. (Preventing 'hiccups' in Frame Rate)
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateCoreML];
        [self loopCoreMLUpdate];
    });
}

- (void)updateCoreML {
    ///////////////////////////
    // Get Camera Image as RGB
    CVPixelBufferRef pixbuff = self.sceneView.session.currentFrame.capturedImage;
    CGFloat scale =  [[UIScreen mainScreen] scale];
    size_t width = CVPixelBufferGetWidth(pixbuff)/scale;
    size_t height = CVPixelBufferGetHeight(pixbuff)/scale;
    self.bufferSize = CGSizeMake(height, width);
    
    
    if (pixbuff == nil) { return; }
    CIImage *ciImage = [[CIImage alloc] initWithCVPixelBuffer:pixbuff];
    CGSize centerSize = CGSizeMake(width/2.0, height/2.0);
    CIImage *croppedCIImage = [ciImage imageByCroppingToRect:CGRectMake(-centerSize.width/2.0, -centerSize.height/2.0, centerSize.width, centerSize.height)];
    
    
    // Note: Not entirely sure if the ciImage is being interpreted as RGB, but for now it works with the Inception model.
    // Note2: Also uncertain if the pixelBuffer should be rotated before handing off to Vision (VNImageRequestHandler) - regardless, for now, it still works well with the Inception model.
    
    ///////////////////////////
    // Prepare CoreML/Vision Request
    VNImageRequestHandler *imageRequestHandler = [[VNImageRequestHandler alloc] initWithCIImage:ciImage orientation:[self exifOrientationFromDeviceOrientation] options:@{}];
    
    [imageRequestHandler performRequests:self.requests error:nil];
}


- (SCNNode *)createNewBubbleParentNode:(NSString *)text {
    // Warning: Creating 3D Text is susceptible to crashing. To reduce chances of crashing; reduce number of polygons, letters, smoothness, etc.
    
    // TEXT BILLBOARD CONSTRAINT
    SCNBillboardConstraint *billboardConstraint = [SCNBillboardConstraint billboardConstraint];
    billboardConstraint.freeAxes = SCNBillboardAxisY;
    
    // BUBBLE-TEXT
    SCNText *bubble = [SCNText textWithString:text extrusionDepth:self.bubbleDepth];
    UIFont *font = [UIFont fontWithName:@"Futura" size:0.15];
    //font = font?.withTraits(traits: .traitBold);
    bubble.font = font;
    bubble.alignmentMode = kCAAlignmentCenter;
    bubble.firstMaterial.diffuse.contents = UIColor.orangeColor;
    bubble.firstMaterial.specular.contents = UIColor.whiteColor;
    bubble.firstMaterial.doubleSided = YES;
    // bubble.flatness // setting this too low can cause crashes.
    bubble.chamferRadius = self.bubbleDepth;
    
    // BUBBLE NODE
    //let (minBound, maxBound) = bubble.boundingBox
    
    SCNNode *bubbleNode = [SCNNode nodeWithGeometry:bubble];
    
    SCNVector3 minBounds;
    SCNVector3 maxBounds;
    [bubble getBoundingBoxMin:&minBounds max:&maxBounds];
    // Centre Node - to Centre-Bottom point
    bubbleNode.pivot = SCNMatrix4MakeTranslation( (maxBounds.x - minBounds.x)/2, minBounds.y, self.bubbleDepth/2);
    // Reduce default text size
    bubbleNode.scale = SCNVector3Make(0.2, 0.2, 0.2);
    
    // CENTRE POINT NODE
    SCNSphere *sphere = [SCNSphere sphereWithRadius:0.005];
    sphere.firstMaterial.diffuse.contents = UIColor.cyanColor;
    SCNNode *sphereNode = [SCNNode nodeWithGeometry:sphere];
    
    // BUBBLE PARENT NODE
    SCNNode *bubbleNodeParent = [SCNNode node];
    [bubbleNodeParent addChildNode:bubbleNode];
    [bubbleNodeParent addChildNode:sphereNode];
    bubbleNodeParent.constraints = @[billboardConstraint];
    
    return bubbleNodeParent;
}

- (void)handleTapGestureRecognize:(UITapGestureRecognizer *)gestureRecognize {
    // HIT TEST : REAL WORLD
    // Get Screen Centre
    //let screenCentre : CGPoint = CGPoint(x: self.sceneView.bounds.midX, y: self.sceneView.bounds.midY)
    CGPoint screenCentre = self.point;
    NSArray <ARHitTestResult *> *arHitTestResults = [self.sceneView hitTest:screenCentre types:ARHitTestResultTypeFeaturePoint];
    
    ARHitTestResult *closestResult = arHitTestResults.firstObject;
    if (closestResult != nil)  {
        // Get Coordinates of HitTest
        matrix_float4x4 transform = closestResult.worldTransform;
        SCNVector3 worldCoord = SCNVector3Make(transform.columns[3].x, transform.columns[3].y, transform.columns[3].z);
        
        // Create 3D Text
        SCNNode *node = [self createNewBubbleParentNode:self.latestPrediction];
        [self.sceneView.scene.rootNode addChildNode:node];
        node.position = worldCoord;
    }
}

@end
