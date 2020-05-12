//
//  ViewController.m
//  AudioVideoDemoIOS
//
//  Created by wanghao on 2020/5/6.
//  Copyright © 2020 okjiaoyu. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import "audioEncoder.h"
#import <mach/mach.h>




#define INPUT_BUS  1      ///< A I/O unit's bus 1 connects to input hardware (microphone).
#define OUTPUT_BUS 0      ///< A I/O unit's bus 0 connects to output hardware (speaker).

static AudioUnit                    m_audioUnit;
static AudioBufferList              *m_buffList;
static AudioStreamBasicDescription  m_audioDataFormat;

uint32_t g_av_base_time = 100;

@interface ViewController ()
{
    SInt64      m_recordCurrentPacket;
    AudioFileID m_recordFile;
    AudioTimeStamp m_timeStamp;
    
}
@property (nonatomic, strong) audioEncoder *audioEncoder;
@property (nonatomic,assign)BOOL isPCMRecord;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    _isPCMRecord = YES;
    double sampleRate = 0, duration = 0;
    [self setupEnv:&sampleRate withDuration:&duration];
    
    NSThread *thread = [[NSThread alloc] initWithBlock:^() {
        AudioComponentDescription desc =  [self dumpAudioUnit];
        [self testAudioUnit:sampleRate withDuration:duration withDesc:desc];

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
        self.audioEncoder = [[audioEncoder alloc] initWithSourceFormat:asbd];

      
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

                while (true) {
                    err = AudioUnitRender(audiounit, &renderActionFlags, &timeStamp, bus, maxFrames, &list);
                    assert(err == 0);
                    int64_t pts =timeStamp.mSampleTime;
//                     NSLog(@"sampleTime:%lld",pts);
                    timeStamp.mSampleTime += maxFrames ;
                    void    *bufferData = list.mBuffers[0].mData;
                    UInt32   bufferSize = list.mBuffers[0].mDataByteSize;
                    if (_isPCMRecord) {
                        [self writeFileWithInNumBytes:bufferSize ioNumPackets:maxFrames inBuffer:bufferData inPacketDesc:nil];
                    }else
                    {
                        
                        
//                        for (int i=0; i < (bufferSize/maxFrames); i++) {
//                            [self.audioEncoder encodeAudioWithSourceBuffer:(bufferData+ i* maxFrames) sourceBufferSize:maxFrames pts:pts];
//                        }
                        
                        
                         [self.audioEncoder encodeAudioWithSourceBuffer:bufferData sourceBufferSize:bufferSize pts:pts];
                        
                    }


//
//                    float timeCount =   maxFrames * (1/44100) * 1000000;
//                     sleep(timeCount);
                    [NSThread sleepForTimeInterval:duration];

                }
        
    }
    
//    err = AudioOutputUnitStop(audiounit);
//    assert(err == 0);
//
//    err = AudioUnitUninitialize(audiounit);
//    assert(err == 0);
//
//    err = AudioComponentInstanceDispose(audiounit);
//    assert(err == 0);
    
    NSLog(@"testAudioUnit finished");

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
    
    ViewController * controller = (__bridge ViewController *)inRefCon;
    
    [controller.audioEncoder encodeAudioWithSourceBuffer:bufferData
                                  sourceBufferSize:bufferSize
                                               pts:pts];
    
    
    return noErr;
}
- (IBAction)startRecordClcik:(id)sender {
    
     m_recordFile = [self initRecordWithFilePath:[self createFilePath:@"wav"] audioDesc:m_audioDataFormat];
    _isPCMRecord = YES;
    
}
- (IBAction)startRecordAACClick:(id)sender {
    
    
    m_recordFile = [self initRecordWithFilePath:[self createFilePath:@"m4a"] audioDesc:self.audioEncoder->mDestinationFormat];
    self.audioEncoder->m_recordFile = m_recordFile;
      _isPCMRecord = NO;
}


- (IBAction)stopRecord:(id)sender {
    AudioFileClose(m_recordFile);
       m_recordCurrentPacket = 0;
    self.audioEncoder->m_recordFile = 0;
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
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy_MM_dd__HH_mm_ss";
    NSString *date = [dateFormatter stringFromDate:[NSDate date]];
    
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
// 轮询检查多个线程 CPU 情况
//- (void)updateCPU {
//    thread_act_array_t threads;
//    mach_msg_type_number_t threadCount = 0;
//    const task_t thisTask = mach_task_self();
//    kern_return_t kr = task_threads(thisTask, &threads, &threadCount);
//    if (kr != KERN_SUCCESS) {
//        return;
//    }
//    for (int i = 0; i < threadCount; i++) {
//        thread_info_data_t threadInfo;
//        thread_basic_info_t threadBaseInfo;
//        mach_msg_type_number_t threadInfoCount = THREAD_INFO_MAX;
//        if (thread_info((thread_act_t)threads[i], THREAD_BASIC_INFO, (thread_info_t)threadInfo, &threadInfoCount) == KERN_SUCCESS) {
//            threadBaseInfo = (thread_basic_info_t)threadInfo;
//            if (!(threadBaseInfo->flags & TH_FLAGS_IDLE)) {
//                integer_t cpuUsage = threadBaseInfo->cpu_usage / 10;
//                if (cpuUsage > 90) {
//                    //cup 消耗大于 90 时打印和记录堆栈
//                    NSString *reStr = smStackOfThread(threads[i]);
//                    // 记录数据库中
//                    [[[SMLagDB shareInstance] increaseWithStackString:reStr] subscribeNext:^(id x) {}];
//                    NSLog(@"CPU useage overload thread stack：\n%@",reStr);
//                }
//            }
//        }
//    }
//}
@end
