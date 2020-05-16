//
//  audioUnitPcm.m
//  AudioVideoDemoIOS
//
//  Created by 奇少 on 2020/5/14.
//  Copyright © 2020 okjiaoyu. All rights reserved.
//

#import "audioUnitPcm.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import "audioEncoderAAC.h"
#import <mach/mach.h>




#define INPUT_BUS  1      ///< A I/O unit's bus 1 connects to input hardware (microphone).
#define OUTPUT_BUS 0      ///< A I/O unit's bus 0 connects to output hardware (speaker).

static AudioUnit                    m_audioUnit;
static AudioBufferList              *m_buffList;
static AudioStreamBasicDescription  m_audioDataFormat;

uint32_t g_av_base_time = 100;

@interface audioUnitPcm()
{
    SInt64      m_recordCurrentPacket;
    AudioFileID m_recordFile;
    AudioTimeStamp m_timeStamp;
    NSOutputStream *outpusStream;
    double sampleRate, duration;
    int tempCount;
}
@property (nonatomic, strong) audioEncoderAAC *audioEncoder;
@property (nonatomic,assign)BOOL isLoop;
@end


@implementation audioUnitPcm
- (instancetype)init
{
    self = [super init];
    if (self) {
        [self initAudioUnit];
    }
    return self;
}


-(void)initAudioUnit {
    _isLoop = YES;
    sampleRate = 0;
    duration = 0;
    [self setupEnv:&sampleRate withDuration:&duration];
    float aa = duration * 44100;
    NSLog(@"++++++++%f",aa);
    tempCount = 0;
}

-(void)startSample {
    NSThread *thread = [[NSThread alloc] initWithBlock:^() {
        AudioComponentDescription desc =  [self dumpAudioUnit];
        [self testAudioUnit:self->sampleRate withDuration:self->duration withDesc:desc];

    }];
    [thread start];
}
-(void) setupEnv: (double *) outSampleRate withDuration: (double *) outDuration {
    NSLog(@"setupEnv");
    
    AVAudioSession *s = [AVAudioSession sharedInstance];
    NSError *err = nil;
//    [s setCategory:AVAudioSessionCategoryPlayAndRecord error:&err];
    assert(err == nil);
    
     [s setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDuckOthers
                      error:&err];

    
    [s setMode:AVAudioSessionModeVoiceChat error:&err];
    assert(err == nil);
    
    [s setActive:YES error:&err];
    assert(err == nil);

    [s setPreferredInputNumberOfChannels:1 error:&err];
    assert(err == nil);

    [s setPreferredSampleRate:44100 error:&err];
    assert(err == nil);
    
    [s setPreferredIOBufferDuration:0.2 error:&err];
    assert(err == nil);
    
    NSLog(@"setupEnv finished");
    
    NSLog(@"IOBufferDuration: %f", s.IOBufferDuration);
    NSLog(@"sampleRate: %f", s.sampleRate);
    NSLog(@"inputNumberOfChannels: %ld", s.inputNumberOfChannels);
    NSLog(@"inputGain: %f", s.inputGain);
    
    *outSampleRate = s.sampleRate;
    *outDuration = s.IOBufferDuration;
}

-(AudioComponentDescription) dumpAudioUnit {
    NSLog(@"dumpAudioUnit");
    
    AudioComponentDescription desc = {0};
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    UInt32 count = AudioComponentCount(&desc);
    NSLog(@"AudioComponentCount: %u", count);
    
    AudioComponent ac = NULL;
    while (true) {
        ac = AudioComponentFindNext(ac, &desc);
        
        if (ac) {
            CFStringRef name = NULL;
            OSStatus err = AudioComponentCopyName(ac, &name);
            assert(err == 0);
            NSLog(@"audio comopnent name: %@", name);
        }
        
        break;
    }
    
    assert(ac);
    
    OSStatus err = AudioComponentGetDescription(ac, &desc);
    assert(err == 0);
    
    NSLog(@"dumpAudioUnit finished");

    return desc;
}

-(void) testAudioUnit:(double) sampleRate
         withDuration:(double) duration
             withDesc:(AudioComponentDescription) audioComponentDesc {
    NSLog(@"testAudioUnit start");
    AudioComponent ac = AudioComponentFindNext(NULL, &audioComponentDesc);
    assert(ac);
    AudioComponentInstance audiounit = NULL;
    OSStatus err = AudioComponentInstanceNew(ac, &audiounit);
    assert(err == 0);
    NSLog(@"audio unit pointer: %p", audiounit);
    
    AudioUnitElement inputBus = 1;
    AudioUnitElement outputBus = 0;
    
    {
        Float64 sampleRate = 44100;
        err = AudioUnitSetProperty(audiounit, kAudioUnitProperty_SampleRate, kAudioUnitScope_Output, inputBus, &sampleRate, sizeof(sampleRate));
        assert(err == 0);
    }
    {
        UInt32 enable = 1;
        err = AudioUnitSetProperty(audiounit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, inputBus, &enable, sizeof(enable));
        assert(err == 0);
    }
    {
        UInt32 enable = 0;
        err = AudioUnitSetProperty(audiounit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, outputBus, &enable, sizeof(enable));
        assert(err == 0);
    }
    {
        AudioStreamBasicDescription asbd = {0};
        asbd.mFramesPerPacket = 1;
        asbd.mSampleRate = 44100;
        asbd.mFormatID = kAudioFormatLinearPCM;
        //        asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved;
        asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        asbd.mChannelsPerFrame = 1;
        asbd.mBitsPerChannel = 4 * 8;//float32
        asbd.mBytesPerFrame = 4;
        asbd.mBytesPerPacket = asbd.mFramesPerPacket * asbd.mBytesPerFrame;
        
        err = AudioUnitSetProperty(audiounit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, inputBus, &asbd, sizeof(asbd));
        assert(err == 0);
        m_audioDataFormat  =  asbd;
        self.audioEncoder = [[audioEncoderAAC alloc] initWithSourceFormat:asbd];
        
        [self printAudioStreamBasicDescription:asbd];
        
    }
    
    UInt32 maxFrames = (UInt32) ceil(sampleRate * duration);
    {
        NSLog(@"maxFrames: %u", maxFrames);
        err = AudioUnitSetProperty(audiounit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, inputBus, &maxFrames, sizeof(maxFrames));
    }
    
    err = AudioUnitInitialize(audiounit);
    assert(err == 0);
    
    err = AudioOutputUnitStart(audiounit);
    assert(err == 0);
    
    {
        //pull data
        NSLog(@"pull data");
        
        AudioUnitRenderActionFlags renderActionFlags = kAudioOfflineUnitRenderAction_Render;
        AudioTimeStamp timeStamp = {0};
        {
            timeStamp.mFlags = kAudioTimeStampSampleTimeValid;
            timeStamp.mSampleTime = 0;
        }
        m_timeStamp = timeStamp;
        UInt32 bus = 1;//input bus
        
        AudioBuffer buffer = {0};
        {
            buffer.mNumberChannels = 1;
            buffer.mDataByteSize = maxFrames * 4;
            buffer.mData = malloc(buffer.mDataByteSize);
        }
        AudioBufferList list = {0};
        {
            list.mNumberBuffers = 1;
            list.mBuffers[0] = buffer;
        }
        m_buffList = &list;
        
        
        m_audioUnit = audiounit;
        //         [self initCaptureCallbackWithAudioUnit:audiounit callBack:AudioCaptureCallback];
        [outpusStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];

        while (_isLoop) {
            
            err = AudioUnitRender(audiounit, &renderActionFlags, &timeStamp, bus, maxFrames, &list);
            assert(err == 0);
            int64_t pts =timeStamp.mSampleTime;
            //                     NSLog(@"sampleTime:%lld",pts);
            timeStamp.mSampleTime += maxFrames ;
            void    *bufferData = list.mBuffers[0].mData;
            UInt32   bufferSize = list.mBuffers[0].mDataByteSize;
            if (recordTypeWAV == _type) {
                [self writeFileWithInNumBytes:bufferSize ioNumPackets:maxFrames inBuffer:bufferData inPacketDesc:nil];
                
            }else if(recordTypeM4A == _type)
            {
                
                
                //                        for (int i=0; i < (bufferSize/maxFrames); i++) {
                //                            [self.audioEncoder encodeAudioWithSourceBuffer:(bufferData+ i* maxFrames) sourceBufferSize:maxFrames pts:pts];
                //                        }
                
                
                [self.audioEncoder encodeAudioWithSourceBuffer:bufferData sourceBufferSize:bufferSize pts:pts];
                
            }else if (recordTypeDATA == _type) {

                [outpusStream write:bufferData maxLength:TEMPDataByteSize];
                tempCount += 1;
                
                //                        break;
            }
            
            
            //
            //                    float timeCount =   maxFrames * (1/44100) * 1000000;
            //                     sleep(timeCount);
            [NSThread sleepForTimeInterval:duration];
            
        }
        
    }
    
    
    NSLog(@"testAudioUnit finished");
    
}
-(void)stopSampleRate {
    OSStatus err;
        err = AudioOutputUnitStop(m_audioUnit);
        assert(err == 0);
    
        err = AudioUnitUninitialize(m_audioUnit);
        assert(err == 0);
    
        err = AudioComponentInstanceDispose(m_audioUnit);
        assert(err == 0);
}

- (void)initCaptureCallbackWithAudioUnit:(AudioUnit)audioUnit callBack:(AURenderCallback)callBack {
    AURenderCallbackStruct captureCallback;
    captureCallback.inputProc        = callBack;
    captureCallback.inputProcRefCon  = (__bridge void *)self;
    OSStatus status                  = AudioUnitSetProperty(audioUnit,
                                                            kAudioOutputUnitProperty_SetInputCallback,
                                                            kAudioUnitScope_Global,
                                                            INPUT_BUS,
                                                            &captureCallback,
                                                            sizeof(captureCallback));
    
    if (status != noErr) {
        NSLog(@"%s - Audio Unit set capture callback failed, status : %d \n", __func__,status);
    }
}


static OSStatus AudioCaptureCallback(void                       *inRefCon,
                                     AudioUnitRenderActionFlags *ioActionFlags,
                                     const AudioTimeStamp       *inTimeStamp,
                                     UInt32                     inBusNumber,
                                     UInt32                     inNumberFrames,
                                     AudioBufferList            *ioData) {
    if (g_av_base_time == 0) {
        return noErr;
    }
    AudioUnitRender(m_audioUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, m_buffList);
    //    NSLog(@"sum: %u--mNumberBuffers:%d", (unsigned int)inNumberFrames,m_buffList->mNumberBuffers);
    
//    Float64 currentTime = CMTimeGetSeconds(CMClockMakeHostTimeFromSystemUnits(inTimeStamp->mHostTime));
//       int64_t pts =timeStamp.mSampleTime;
//    NSLog(@"sampleTime:%f",inTimeStamp->mSampleTime);
//    NSLog(@"currentTime:%f",currentTime);
    int64_t pts =inTimeStamp->mSampleTime;
    
    void    *bufferData = m_buffList->mBuffers[0].mData;
    UInt32   bufferSize = m_buffList->mBuffers[0].mDataByteSize;
    
    audioUnitPcm * controller = (__bridge audioUnitPcm *)inRefCon;
    
    [controller.audioEncoder encodeAudioWithSourceBuffer:bufferData
                                  sourceBufferSize:bufferSize
                                               pts:pts];
    
    
    return noErr;
}
- (void)startRecordClcik {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->m_recordFile = [self initRecordWithFilePath:[self createFilePath:@"pcm"] audioDesc:m_audioDataFormat];
        self->_type = recordTypeWAV;
    });

    
}
- (void)startRecordAACClick {
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->m_recordFile = [self initRecordWithFilePath:[self createFilePath:@"m4a"] audioDesc:self.audioEncoder->mDestinationFormat];
        self.audioEncoder->m_recordFile = self->m_recordFile;
        self->_type = recordTypeM4A;
       
    });
    
}
-(void)strartRecordData {
    _isLoop = YES;
    outpusStream = [NSOutputStream outputStreamToFileAtPath:_pcmPath append:NO];
    [outpusStream open];
     _type = recordTypeDATA;
}


- (void)stopRecord {
    _isLoop = NO;
    AudioFileClose(m_recordFile);
    m_recordCurrentPacket = 0;
    self.audioEncoder->m_recordFile = 0;
    [outpusStream close];
}



-(AudioFileID) initRecordWithFilePath:(NSString *)filePath audioDesc:(AudioStreamBasicDescription)audioDesc {
    CFURLRef url            = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)filePath, NULL);
      NSLog(@"%s - record file path:%@",__func__,filePath);
      
      AudioFileID audioFile;
      // create the audio file   kAudioFileWAVEType  kAudioFileCAFType kAudioFileAAC_ADTSType
      OSStatus status = AudioFileCreateWithURL(url,
                                                kAudioFileAAC_ADTSType,
                                               &audioDesc,
                                               kAudioFileFlags_EraseFile,
                                               &audioFile);
      if (status != noErr) {
          NSLog(@"%s - AudioFileCreateWithURL Failed, status:%d",__func__,(int)status);
      }
      
      CFRelease(url);
      m_recordCurrentPacket = 0;
      return audioFile;
}

- (NSString *)createFilePath:(NSString *)type {
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
    
    NSString *fullFileName  = [NSString stringWithFormat:@"%@.%@",date,type];
    NSString *filePath      = [documentPath stringByAppendingPathComponent:fullFileName];
    return filePath;
}

- (void)writeFileWithInNumBytes:(UInt32)inNumBytes ioNumPackets:(UInt32 )ioNumPackets inBuffer:(const void *)inBuffer inPacketDesc:(nullable const AudioStreamPacketDescription*)inPacketDesc {
    if (!m_recordFile) {
        return;
    }
    
    //    AudioStreamPacketDescription outputPacketDescriptions;
    OSStatus status = AudioFileWritePackets(m_recordFile,
                                            false,
                                            inNumBytes,
                                            inPacketDesc,
                                            m_recordCurrentPacket,
                                            &ioNumPackets,
                                            inBuffer);
    
    if (status == noErr) {
        m_recordCurrentPacket += ioNumPackets;  // 用于记录起始位置
    }else {
        NSLog(@"%s - write file status = %d \n",__func__,(int)status);
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
@end
