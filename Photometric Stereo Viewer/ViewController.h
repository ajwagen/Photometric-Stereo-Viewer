//
//  ViewController.h
//  RealtimeVideoFilter
//
//  Created by Altitude Labs on 23/12/15.
//  Copyright © 2015 Victor. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreImage/CoreImage.h>
#import <AVFoundation/AVFoundation.h>

@import CoreMotion;


@interface ViewController : UIViewController {
}

@property(strong,nonatomic) AVSpeechSynthesizer *synth;

@property(nonatomic) CIImage *overlayCI_L;
@property(nonatomic) CIImage *overlayCI_R;

@end

