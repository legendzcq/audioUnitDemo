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
#import "audioDecodePCM.h"


@interface ViewController ()
@property (nonatomic, strong) audioUnitPcm *audioPcm;
@property (nonatomic, strong) audioPlayer *audioPlay;
@property (nonatomic, strong) audioDecodePCM * decodePcm;



@property (nonatomic, strong) NSURL *sourceURL;
@property (nonatomic, strong) NSURL *destinationURL;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    //采集pcm 以及 pcm-> aac
    self.audioPcm = [[audioUnitPcm alloc] init];
    // 播放pcm 数据，包含一些对缺失数据的处理
    self.audioPlay = [[audioPlayer alloc] init];
    

    
    
    //解码demo  aac-> pcm
    

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
    
    [self.audioPlay playWithURL:[self createFilePath1]];
}
- (NSString *)createFilePath1 {

    
    NSArray *searchPaths    = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                  NSUserDomainMask,
                                                                  YES);
    
    NSString *documentPath  = [searchPaths objectAtIndex:0];
    
    // 先创建子目录. 注意,若果直接调用AudioFileCreateWithURL创建一个不存在的目录创建文件会失败
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:documentPath]) {
        [fileManager createDirectoryAtPath:documentPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSString *fullFileName  = [NSString stringWithFormat:@"pcmData.pcm"];
    NSString *filePath      = [documentPath stringByAppendingPathComponent:fullFileName];
    return filePath;
}
- (NSString *)createFilePath{
//    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
//    dateFormatter.dateFormat = @"yyyy_MM_dd__HH_mm_ss";
//    NSString *date = [dateFormatter stringFromDate:[NSDate date]];
    NSString *date = @"abcd";
    NSArray *searchPaths    = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                  NSUserDomainMask,
                                                                  YES);
    
    NSString *documentPath  = [[searchPaths objectAtIndex:0] stringByAppendingPathComponent:@"Voice"];
    
    // 先创建子目录. 注意,若果直接调用AudioFileCreateWithURL创建一个不存在的目录创建文件会失败
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:documentPath]) {
        [fileManager createDirectoryAtPath:documentPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSString *fullFileName  = [NSString stringWithFormat:@"%@.m4a",date];
    NSString *filePath      = [documentPath stringByAppendingPathComponent:fullFileName];
    return filePath;
}

- (IBAction)startDecodeClick:(id)sender {
    
    self.sourceURL = [NSURL URLWithString:[self createFilePath]];
      
    
    self.decodePcm = [[audioDecodePCM alloc] initWithSourceURL:self.sourceURL ];
    self.decodePcm.audioPlay = self.audioPlay;
    [self.decodePcm startDecode];
    [self.audioPlay playWithURL:[self createFilePath1]];
}

@end
