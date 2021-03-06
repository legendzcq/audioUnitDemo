//
//  audioPlayer.m
//  AudioVideoDemoIOS
//
//  Created by 奇少 on 2020/5/14.
//  Copyright © 2020 okjiaoyu. All rights reserved.
//

#import "audioPlayer.h"
#import <AudioUnit/AudioUnit.h>
#import <AVFoundation/AVFoundation.h>
#import <assert.h>


const uint32_t CONST_BUFFER_SIZE = 0x10000;

#define INPUT_BUS 1
#define OUTPUT_BUS 0

@interface audioPlayer() <NSStreamDelegate>

@end

@implementation audioPlayer
{
    AudioUnit audioUnit;
    AudioBufferList *buffList;
    
    NSInputStream *inputSteam;
    NSInputStream *backSteam;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self initData];
    }
    return self;
}

-(void)initData{
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"pcmData" withExtension:@"pcm"];
    backSteam = [NSInputStream inputStreamWithURL:url];
    if (!backSteam) {
        NSLog(@"打开文件失败 %@", url);
    }
    else {
        [backSteam open];
    }
}


- (double)getCurrentTime {
    Float64 timeInterval = 0;
    if (inputSteam) {
        
    }
    
    return timeInterval;
}

-(void)playWithURL:(NSString *)urlStr{
    // open pcm stream
    inputSteam = [NSInputStream inputStreamWithFileAtPath:urlStr];
    inputSteam.delegate = self;
    if (!inputSteam) {
        NSLog(@"打开文件失败 %@", urlStr);
    }
    else {
        [inputSteam open];
    }
    
    [self initPlayer:inputSteam];
}
-(void)playWithMemory:(NSStream *)stream {
    inputSteam =(NSInputStream *) stream;
    if (!inputSteam) {
           NSLog(@"打开文件失败");
       }
       else {
           [inputSteam open];
       }
    [self initPlayer:inputSteam];
}

- (void)initPlayer:(NSInputStream *)inputSteam {

    
    NSError *error = nil;
    OSStatus status = noErr;
    
    // set audio session
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:&error];
    
    AudioComponentDescription audioDesc;
    audioDesc.componentType = kAudioUnitType_Output;
    audioDesc.componentSubType = kAudioUnitSubType_RemoteIO;
    audioDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    audioDesc.componentFlags = 0;
    audioDesc.componentFlagsMask = 0;
    
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &audioDesc);
    AudioComponentInstanceNew(inputComponent, &audioUnit);
    
    // buffer
    buffList = (AudioBufferList *)malloc(sizeof(AudioBufferList));
    buffList->mNumberBuffers = 1;
    buffList->mBuffers[0].mNumberChannels = 1;
    buffList->mBuffers[0].mDataByteSize = CONST_BUFFER_SIZE;
    buffList->mBuffers[0].mData = malloc(CONST_BUFFER_SIZE);
    
    //audio property
    UInt32 flag = 1;
    if (flag) {
        status = AudioUnitSetProperty(audioUnit,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Output,
                                      OUTPUT_BUS,
                                      &flag,
                                      sizeof(flag));
    }
    if (status) {
        NSLog(@"AudioUnitSetProperty error with status:%d", status);
    }
    
    // format
    AudioStreamBasicDescription outputFormat;
    memset(&outputFormat, 0, sizeof(outputFormat));
    outputFormat.mSampleRate       = 44100; // 采样率
    outputFormat.mFormatID         = kAudioFormatLinearPCM; // PCM格式
    outputFormat.mFormatFlags      = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsFloat; // 整形
    outputFormat.mFramesPerPacket  = 1; // 每帧只有1个packet
    outputFormat.mChannelsPerFrame = 1; // 声道数
    outputFormat.mBytesPerFrame    = 4; // 每帧只有2个byte 声道*位深*Packet数
    outputFormat.mBytesPerPacket   = 4; // 每个Packet只有2个byte
    outputFormat.mBitsPerChannel   = 32; // 位深
    [self printAudioStreamBasicDescription:outputFormat];
    
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  OUTPUT_BUS,
                                  &outputFormat,
                                  sizeof(outputFormat));
    if (status) {
        NSLog(@"AudioUnitSetProperty eror with status:%d", status);
    }
    
    
    // callback
    AURenderCallbackStruct playCallback;
    playCallback.inputProc = PlayCallback;
    playCallback.inputProcRefCon = (__bridge void *)self;
    AudioUnitSetProperty(audioUnit,
                         kAudioUnitProperty_SetRenderCallback,
                         kAudioUnitScope_Input,
                         OUTPUT_BUS,
                         &playCallback,
                         sizeof(playCallback));
    
    
    OSStatus result = AudioUnitInitialize(audioUnit);
    AudioOutputUnitStart(audioUnit);

    NSLog(@"result %d", result);
}


static OSStatus PlayCallback(void *inRefCon,
                             AudioUnitRenderActionFlags *ioActionFlags,
                             const AudioTimeStamp *inTimeStamp,
                             UInt32 inBusNumber,
                             UInt32 inNumberFrames,
                             AudioBufferList *ioData) {
    audioPlayer *player = (__bridge audioPlayer *)inRefCon;
    
        ioData->mBuffers[0].mDataByteSize = (UInt32)[player->inputSteam read:ioData->mBuffers[0].mData maxLength:(NSInteger)ioData->mBuffers[0].mDataByteSize];;
    
    NSInteger count= ioData->mBuffers[0].mDataByteSize;
//    void*  tempData = malloc(inNumberFrames * 4 * sizeof(char));
//    NSInteger count=  [player->inputSteam read:tempData maxLength:TEMPDataByteSize];
//    [player->backSteam read:(tempData +TEMPDataByteSize) maxLength:(inNumberFrames * 4- TEMPDataByteSize)];
//
//
//    //
//    ioData->mBuffers[0].mData = tempData;
//    ioData->mBuffers[0].mDataByteSize = TEMPDataByteSize;
    NSLog(@"out size: %d---count:%ld", ioData->mBuffers[0].mDataByteSize,(long)count);
//
//    free(tempData);
    
    if (count <= 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [player stop];
        });
    }
    return noErr;
}

//-()


- (void)stop {
    AudioOutputUnitStop(audioUnit);
    if (buffList != NULL) {
        if (buffList->mBuffers[0].mData) {
            free(buffList->mBuffers[0].mData);
            buffList->mBuffers[0].mData = NULL;
        }
        free(buffList);
        buffList = NULL;
    }
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(onPlayToEnd:)]) {
        __strong typeof (audioPlayer) *player = self;
        [self.delegate onPlayToEnd:player];
    }
    
    [inputSteam close];
}

- (void)dealloc {
    AudioOutputUnitStop(audioUnit);
    AudioUnitUninitialize(audioUnit);
    AudioComponentInstanceDispose(audioUnit);
    
    if (buffList != NULL) {
        free(buffList);
        buffList = NULL;
    }
}


- (void)printAudioStreamBasicDescription:(AudioStreamBasicDescription)asbd {
    char formatID[5];
    UInt32 mFormatID = CFSwapInt32HostToBig(asbd.mFormatID);
    bcopy (&mFormatID, formatID, 4);
    formatID[4] = '\0';
    printf("Sample Rate:         %10.0f\n",  asbd.mSampleRate);
    printf("Format ID:           %10s\n",    formatID);
    printf("Format Flags:        %10X\n",    (unsigned int)asbd.mFormatFlags);
    printf("Bytes per Packet:    %10d\n",    (unsigned int)asbd.mBytesPerPacket);
    printf("Frames per Packet:   %10d\n",    (unsigned int)asbd.mFramesPerPacket);
    printf("Bytes per Frame:     %10d\n",    (unsigned int)asbd.mBytesPerFrame);
    printf("Channels per Frame:  %10d\n",    (unsigned int)asbd.mChannelsPerFrame);
    printf("Bits per Channel:    %10d\n",    (unsigned int)asbd.mBitsPerChannel);
    printf("\n");
}
#pragma mark ---


@end
