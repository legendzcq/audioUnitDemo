//
//  ViewController.m
//  AudioVideoDemoIOS
//
//  Created by wanghao on 2020/5/6.
//  Copyright © 2020 okjiaoyu. All rights reserved.
//

#import "ViewController.h"
#import "audioUnitPcm.h"
#import "audioPlayer.h"


@interface ViewController ()
@property (nonatomic, strong) audioUnitPcm *audioPcm;
@property (nonatomic, strong) audioPlayer *audioPlay;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    self.audioPcm = [[audioUnitPcm alloc] init];
    
    self.audioPlay = [[audioPlayer alloc] init];
    

}


- (IBAction)startRecordClcik:(id)sender {
    [self.audioPcm startRecordClcik];
    
}
- (IBAction)startRecordAACClick:(id)sender {

    [self.audioPcm startSample];
    [self.audioPcm startRecordAACClick];

}
- (IBAction)startRecordData:(id)sender {
     [self.audioPcm startSample];
    [self.audioPcm strartRecordData];
   
}


- (IBAction)stopRecord:(id)sender {
    [self.audioPcm stopRecord];
    [self.audioPcm stopSampleRate];
}

- (IBAction)playRecord:(id)sender {
    [self.audioPlay play:self.audioPcm.pcmPath];
}


@end
