//
//  audioEncoder.m
//  AudioVideoDemoIOS
//
//  Created by 奇少 on 2020/5/8.
//  Copyright © 2020 okjiaoyu. All rights reserved.
//

#import "audioEncoder.h"

struct OKConverterInfo {
    UInt32   sourceChannelsPerFrame;
    UInt32   sourceDataSize;
    void     *sourceBuffer;
    

};

typedef struct OKConverterInfo converterInfoType;



@implementation audioEncoder

- (instancetype)initWithSourceFormat:(AudioStreamBasicDescription)sourceFormat {
    if (self = [super init]) {
         m_recordCurrentPacket = 0;
       mAudioConverter = [self configureEncoderBySourceFormat:sourceFormat];
      }

 return self;   
}

- (AudioConverterRef)configureEncoderBySourceFormat:(AudioStreamBasicDescription)sourceFormat {
    mSourceFormat   = sourceFormat;
    AudioFormatID destFormatID  = kAudioFormatMPEG4AAC;
//    kAudioFormatiLBC;
    
    AudioStreamBasicDescription destinationFormat = {0};
    destinationFormat.mSampleRate = 44100;
    
    destinationFormat.mFormatID = destFormatID;
    
    // For iLBC, the number of channels must be 1.
    destinationFormat.mChannelsPerFrame = 1;

    // Use AudioFormat API to fill out the rest of the description.
    printf("Destination File format:\n");
    [self printAudioStreamBasicDescription:destinationFormat];
   UInt32 size = sizeof(destinationFormat);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &destinationFormat);
    printf("----Destination File format:\n");
    [self printAudioStreamBasicDescription:destinationFormat];
    memcpy(&mDestinationFormat, &destinationFormat, sizeof(AudioStreamBasicDescription));
    
//    printf("Source File format:\n");
//    [self printAudioStreamBasicDescription:sourceFormat];

    
    // encoder conut by channels.
      AudioClassDescription requestedCodecs[destinationFormat.mChannelsPerFrame];
      const OSType subtype = destFormatID;
      for (int i = 0; i < destinationFormat.mChannelsPerFrame; i++) {
          AudioClassDescription codec = {
              kAudioEncoderComponentType,
              subtype,
              kAppleHardwareAudioCodecManufacturer,
          };
          requestedCodecs[i] = codec;
      }
    
    // Create the AudioConverterRef.
    AudioConverterRef converter = NULL;
    AudioConverterNewSpecific(&sourceFormat, &destinationFormat, destinationFormat.mChannelsPerFrame, requestedCodecs, &converter);
    
    
    /*
     If encoding to AAC set the bitrate kAudioConverterEncodeBitRate is a UInt32 value containing
     the number of bits per second to aim for when encoding data when you explicitly set the bit rate
     and the sample rate, this tells the encoder to stick with both bit rate and sample rate
     but there are combinations (also depending on the number of channels) which will not be allowed
     if you do not explicitly set a bit rate the encoder will pick the correct value for you depending
     on samplerate and number of channels bit rate also scales with the number of channels,
     therefore one bit rate per sample rate can be used for mono cases and if you have stereo or more,
     you can multiply that number by the number of channels.
     */
    
        UInt32 outputBitRate = 192000;
        
        UInt32 propSize = sizeof(outputBitRate);
        
        outputBitRate *= destinationFormat.mChannelsPerFrame;
        
        // Set the bit rate depending on the sample rate chosen.
        AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, propSize, &outputBitRate);
        
        // Get it back and print it out.
        AudioConverterGetProperty(converter, kAudioConverterEncodeBitRate, &propSize, &outputBitRate);
        printf ("AAC Encode Bitrate: %u\n", (unsigned int)outputBitRate);
    
    
    
    /*
     Can the Audio Converter resume after an interruption?
     this property may be queried at any time after construction of the Audio Converter after setting its output format
     there's no clear reason to prefer construction time, interruption time, or potential resumption time but we prefer
     construction time since it means less code to execute during or after interruption time.
     */
    BOOL canResumeFromInterruption = YES;
    UInt32 canResume = 0;
    size = sizeof(canResume);
    OSStatus error = AudioConverterGetProperty(converter, kAudioConverterPropertyCanResumeFromInterruption, &size, &canResume);
    
    if (error == noErr) {
        /*
         we recieved a valid return value from the GetProperty call
         if the property's value is 1, then the codec CAN resume work following an interruption
         if the property's value is 0, then interruptions destroy the codec's state and we're done
         */
        
        if (canResume == 0) {
            canResumeFromInterruption = NO;
        }
        
        printf("Audio Converter %s continue after interruption!\n", (!canResumeFromInterruption ? "CANNOT" : "CAN"));
        
    } else {
        /*
         if the property is unimplemented (kAudioConverterErr_PropertyNotSupported, or paramErr returned in the case of PCM),
         then the codec being used is not a hardware codec so we're not concerned about codec state
         we are always going to be able to resume conversion after an interruption
         */
        
        if (error == kAudioConverterErr_PropertyNotSupported) {
            printf("kAudioConverterPropertyCanResumeFromInterruption property not supported - see comments in source for more info.\n");
            
        } else {
            printf("AudioConverterGetProperty kAudioConverterPropertyCanResumeFromInterruption result %d, paramErr is OK if PCM\n", (int)error);
        }
        
        error = noErr;
    }
    
    mAudioConverter = converter;
   
    return converter;
}


OSStatus ConverterComplexInputDataProc(AudioConverterRef              inAudioConverter,
                                             UInt32                         *ioNumberDataPackets,
                                             AudioBufferList                *ioData,
                                             AudioStreamPacketDescription   **outDataPacketDescription,
                                             void                           *inUserData) {
    converterInfoType *info = (converterInfoType *)inUserData;
    ioData->mNumberBuffers              = 1;
    ioData->mBuffers[0].mData           = info->sourceBuffer;
    ioData->mBuffers[0].mNumberChannels = info->sourceChannelsPerFrame;
    ioData->mBuffers[0].mDataByteSize   = info->sourceDataSize;
    
    
//    NSLog(@"size:%d---mNumberChannels:%d---mData:%p",ioData->mBuffers[0].mDataByteSize,ioData->mBuffers[0].mNumberChannels,ioData->mBuffers[0].mData );
    
    return noErr;
}

- (void)encodeAudioWithSourceBuffer:(void *)sourceBuffer sourceBufferSize:(UInt32)sourceBufferSize pts:(int64_t)pts {
    
    
    
    UInt32 outputSizePerPacket = mDestinationFormat.mBytesPerPacket;
    if (outputSizePerPacket == 0) {
        // if the destination format is VBR, we need to get max size per packet from the converter
        UInt32 size = sizeof(outputSizePerPacket);
        AudioConverterGetProperty(mAudioConverter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &outputSizePerPacket);
    }
    
    UInt32 numberOutputPackets = 1;
    UInt32 theOutputBufferSize = sourceBufferSize;
    AudioStreamPacketDescription outputPacketDescriptions;
    
    // Set up output buffer list.
    AudioBufferList fillBufferList = {};
    fillBufferList.mNumberBuffers = 1;
    fillBufferList.mBuffers[0].mNumberChannels  = mDestinationFormat.mChannelsPerFrame;
    fillBufferList.mBuffers[0].mDataByteSize    = theOutputBufferSize;
    fillBufferList.mBuffers[0].mData            = malloc(theOutputBufferSize * sizeof(char));
    
    
    converterInfoType userInfo   = {0};
    userInfo.sourceBuffer           = sourceBuffer;
    userInfo.sourceDataSize         = sourceBufferSize;
    userInfo.sourceChannelsPerFrame = mSourceFormat.mChannelsPerFrame;
    
    // Convert data
    UInt32 ioOutputDataPackets = numberOutputPackets;
    OSStatus status = AudioConverterFillComplexBuffer(mAudioConverter,
                                                      ConverterComplexInputDataProc,
                                                      &userInfo,
                                                      &ioOutputDataPackets,
                                                      &fillBufferList,
                                                      &outputPacketDescriptions);
    
//    NSLog(@"------size:%d---mNumberChannels:%d---pts:%lld",sourceBufferSize,mSourceFormat.mChannelsPerFrame,pts );
    
    

     [self writeAACFileWithInNumBytes:fillBufferList.mBuffers->mDataByteSize
                      ioNumPackets:ioOutputDataPackets
                          inBuffer:fillBufferList.mBuffers->mData
                      inPacketDesc:&outputPacketDescriptions];
    
//    [self writeAACFileWithInNumBytes:fillBufferList.mBuffers->mDataByteSize
//                     ioNumPackets:ioOutputDataPackets
//                         inBuffer:fillBufferList.mBuffers->mData
//                     inPacketDesc:NULL];
    
    
    if (status == kAudioConverterErr_HardwareInUse) {
        printf("Audio Converter returned kAudioConverterErr_HardwareInUse!\n");
    }
    
    free(fillBufferList.mBuffers->mData);
    
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


- (void)writeAACFileWithInNumBytes:(UInt32)inNumBytes ioNumPackets:(UInt32 )ioNumPackets inBuffer:(const void *)inBuffer inPacketDesc:(nullable const AudioStreamPacketDescription*)inPacketDesc {
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
@end
