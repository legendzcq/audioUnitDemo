//
//  audioDecodePCM.m
//  AudioVideoDemoIOS
//
//  Created by 奇少 on 2020/5/15.
//  Copyright © 2020 okjiaoyu. All rights reserved.
//

#import "audioDecodePCM.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import "audioEncoderAAC.h"
#import <mach/mach.h>


/* The main Audio Conversion function using AudioConverter */

enum {
    kMyAudioConverterErr_CannotResumeFromInterruptionError = 'CANT',
    eofErr = -39 // End of file
};

typedef struct {
    AudioFileID                  srcFileID;
    SInt64                       srcFilePos;
    char *                       srcBuffer;
    UInt32                       srcBufferSize;
    AudioStreamBasicDescription     srcFormat;
    UInt32                       srcSizePerPacket; // 最大包的大小
    UInt32                       numPacketsPerRead;
    AudioStreamPacketDescription *packetDescriptions;
} AudioFileIO, *AudioFileIOPtr;

#pragma mark-



// Input data proc callback
static OSStatus EncoderDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    
     UInt32 requestedPackets = *ioNumberDataPackets;
    
    AudioFileIOPtr afio = (AudioFileIOPtr)inUserData;
    OSStatus error;
    
    // figure out how much to read
    UInt32 maxPackets = afio->srcBufferSize / afio->srcSizePerPacket;
    
//        NSLog(@"maxPackets:%d",maxPackets);
    
    if (*ioNumberDataPackets > maxPackets) *ioNumberDataPackets = maxPackets;
    
    // read from the file
    UInt32 outNumBytes = maxPackets * afio->srcSizePerPacket;
    
    error = AudioFileReadPacketData(afio->srcFileID, false, &outNumBytes, afio->packetDescriptions, afio->srcFilePos, ioNumberDataPackets, afio->srcBuffer);
    if (eofErr == error) error = noErr;
    if (error) { printf ("Input Proc Read error: %d (%4.4s)\n", (int)error, (char*)&error); return error; }
    
    //printf("Input Proc: Read %lu packets, at position %lld size %lu\n", *ioNumberDataPackets, afio->srcFilePos, outNumBytes);
    
    // advance input file packet position
    afio->srcFilePos += *ioNumberDataPackets;
    
    // put the data pointer into the buffer list
    ioData->mBuffers[0].mData = afio->srcBuffer;
    ioData->mBuffers[0].mDataByteSize = outNumBytes;
    ioData->mBuffers[0].mNumberChannels = afio->srcFormat.mChannelsPerFrame;
    
    // don't forget the packet descriptions if required
    if (outDataPacketDescription) {
        if (afio->packetDescriptions) {
            *outDataPacketDescription = afio->packetDescriptions;
        } else {
            *outDataPacketDescription = NULL;
        }
    }
    
    return error;
}


@interface audioDecodePCM()

@property(nonatomic,strong)NSOutputStream *outpusStream;
@property (nonatomic,copy) NSString * pcmPath;

@end

@implementation audioDecodePCM
// MARK: Initialization

- (instancetype)initWithSourceURL:(NSURL *)sourceURL  {
    
    if ((self = [super init])) {
        _sourceURL = sourceURL;
        _outpusStream = [NSOutputStream outputStreamToFileAtPath:[self createFilePath1] append:NO];
       [_outpusStream open];
      
    }
    
    return self;
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

-(void)startDecode {
    // This should never run on the main thread.
    
    AudioStreamPacketDescription *outputPacketDescriptions = NULL;
    
    
    // Get the source file.
    AudioFileID sourceFileID = 0;
    
    if (![self checkError:(AudioFileOpenURL((__bridge CFURLRef _Nonnull)self.sourceURL, kAudioFileReadPermission, 0, &sourceFileID)) withErrorString:[NSString stringWithFormat:@"AudioFileOpenURL failed for sourceFile with URL: %@", self.sourceURL]]) {
        return;
    }
    
    // Get the source data format.
    AudioStreamBasicDescription sourceFormat = {};
    UInt32 size = sizeof(sourceFormat);
    if (![self checkError:AudioFileGetProperty(sourceFileID, kAudioFilePropertyDataFormat, &size, &sourceFormat) withErrorString:@"AudioFileGetProperty couldn't get the source data format"]) {
        return;
    }
    
    // Setup the output file format.
    AudioStreamBasicDescription destinationFormat = {0};
    destinationFormat.mSampleRate = 44100;
    
    destinationFormat.mFormatID = kAudioFormatLinearPCM;
    destinationFormat.mChannelsPerFrame = sourceFormat.mChannelsPerFrame;
    destinationFormat.mBitsPerChannel = 32;
    destinationFormat.mBytesPerPacket = destinationFormat.mBytesPerFrame = 4 * destinationFormat.mChannelsPerFrame;
    destinationFormat.mFramesPerPacket = 1;
    destinationFormat.mFormatFlags = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsFloat; // little-endian
    
    
    printf("Source File format:\n");
    [self printAudioStreamBasicDescription:sourceFormat];
    printf("Destination File format:\n");
    [self printAudioStreamBasicDescription:destinationFormat];
    
    // Create the AudioConverterRef.
    AudioConverterRef converter = NULL;
    if (![self checkError:AudioConverterNew(&sourceFormat, &destinationFormat, &converter) withErrorString:@"AudioConverterNew failed"]) {
        return;
    }
    
    // If the source file has a cookie, get ir and set it on the AudioConverterRef.
    [self readCookieFromAudioFile:sourceFileID converter:converter];
    
    // Get the actuall formats (source and destination) from the AudioConverterRef.
    size = sizeof(sourceFormat);
    if (![self checkError:AudioConverterGetProperty(converter, kAudioConverterCurrentInputStreamDescription, &size, &sourceFormat) withErrorString:@"AudioConverterGetProperty kAudioConverterCurrentInputStreamDescription failed!"]) {
        return;
    }
    
    size = sizeof(destinationFormat);
    if (![self checkError:AudioConverterGetProperty(converter, kAudioConverterCurrentOutputStreamDescription, &size, &destinationFormat) withErrorString:@"AudioConverterGetProperty kAudioConverterCurrentOutputStreamDescription failed!"]) {
        return;
    }
    

        
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
    
    // Create the destination audio file.
//    AudioFileID destinationFileID = 0;
//    if (![self checkError:AudioFileCreateWithURL((__bridge CFURLRef _Nonnull)(self.destinationURL), kAudioFileCAFType, &destinationFormat, kAudioFileFlags_EraseFile, &destinationFileID) withErrorString:@"AudioFileCreateWithURL failed!"]) {
//        return;
//    }
    
    // Setup source buffers and data proc info struct.
    AudioFileIO afio = {};
    afio.srcFileID = sourceFileID;
    afio.srcBufferSize = 16384;
    afio.srcBuffer = malloc(afio.srcBufferSize * sizeof(char));
    afio.srcFilePos = 0;
    afio.srcFormat = sourceFormat;
    
    if (sourceFormat.mBytesPerPacket == 0) {
        /*
         if the source format is VBR, we need to get the maximum packet size
         use kAudioFilePropertyPacketSizeUpperBound which returns the theoretical maximum packet size
         in the file (without actually scanning the whole file to find the largest packet,
         as may happen with kAudioFilePropertyMaximumPacketSize)
         */
        size = sizeof(afio.srcSizePerPacket);
        if (![self checkError:AudioFileGetProperty(sourceFileID, kAudioFilePropertyPacketSizeUpperBound, &size, &afio.srcSizePerPacket) withErrorString:@"AudioFileGetProperty kAudioFilePropertyPacketSizeUpperBound failed!"]) {
            return;
        }
        
        // How many packets can we read for our buffer size?
        afio.numPacketsPerRead = afio.srcBufferSize / afio.srcSizePerPacket;
        
        // Allocate memory for the PacketDescription structs describing the layout of each packet.
        afio.packetDescriptions = malloc(afio.numPacketsPerRead * sizeof(AudioStreamPacketDescription));
    } else {
        // CBR source format
        afio.srcSizePerPacket = sourceFormat.mBytesPerPacket;
        afio.numPacketsPerRead = afio.srcBufferSize / afio.srcSizePerPacket;
        afio.packetDescriptions = NULL;
    }
    
    // Set up output buffers
    UInt32 outputSizePerPacket = destinationFormat.mBytesPerPacket;
    UInt32 theOutputBufferSize = 16384;
    char *outputBuffer = malloc(theOutputBufferSize * sizeof(char));
    
    if (outputSizePerPacket == 0) {
        // if the destination format is VBR, we need to get max size per packet from the converter
        size = sizeof(outputSizePerPacket);
        
        if (![self checkError:AudioConverterGetProperty(converter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &outputSizePerPacket) withErrorString:@"AudioConverterGetProperty kAudioConverterPropertyMaximumOutputPacketSize failed!"]) {
            if (afio.srcBuffer) { free(afio.srcBuffer); }
            if (outputBuffer) { free(outputBuffer); }
            
            return;
        }
        
        // allocate memory for the PacketDescription structures describing the layout of each packet
        outputPacketDescriptions = calloc(theOutputBufferSize / outputSizePerPacket, sizeof(AudioStreamPacketDescription));//malloc((theOutputBufferSize / outputSizePerPacket) * sizeof(AudioStreamPacketDescription));
    }
    
    UInt32 numberOutputPackets = theOutputBufferSize / outputSizePerPacket;
    
//    // If the destination format has a cookie, get it and set it on the output file.
//    [self writeCookieForAudioFile:destinationFileID converter:converter];
    
    
    // Used for debugging printf
    UInt64 totalOutputFrames = 0;
    SInt64 outputFilePosition = 0;
    
    // Loop to convert data.
    printf("Converting...\n");
    while (YES) {
        
        // Set up output buffer list.
        AudioBufferList fillBufferList = {};
        fillBufferList.mNumberBuffers = 1;
        fillBufferList.mBuffers[0].mNumberChannels = destinationFormat.mChannelsPerFrame;
        fillBufferList.mBuffers[0].mDataByteSize = theOutputBufferSize;
        fillBufferList.mBuffers[0].mData = outputBuffer;
        
        
        
        
        // Convert data
        UInt32 ioOutputDataPackets = numberOutputPackets;
        printf("AudioConverterFillComplexBuffer...\n");
        error = AudioConverterFillComplexBuffer(converter, EncoderDataProc, &afio, &ioOutputDataPackets, &fillBufferList, outputPacketDescriptions);
        
        [_outpusStream write:fillBufferList.mBuffers[0].mData maxLength:fillBufferList.mBuffers[0].mDataByteSize];

        NSLog(@"ioOutputDataPackets:%d",ioOutputDataPackets);
        // if interrupted in the process of the conversion call, we must handle the error appropriately
        if (error) {
            if (error == kAudioConverterErr_HardwareInUse) {
                printf("Audio Converter returned kAudioConverterErr_HardwareInUse!\n");
            } else {
                if (![self checkError:error withErrorString:@"AudioConverterFillComplexBuffer error!"]) {
                    return;
                }
            }
        } else {
            if (ioOutputDataPackets == 0) {
                // This is the EOF condition.
                [_outpusStream close];
                error = noErr;
                break;
            }
        }
        
        if (error == noErr) {
            // Write to output file.
            UInt32 inNumBytes = fillBufferList.mBuffers[0].mDataByteSize;
            
            
            printf("Convert Output: Write %u packets at position %lld, size: %u\n", (unsigned int)ioOutputDataPackets, outputFilePosition, (unsigned int)inNumBytes);
            
            // Advance output file packet position.
            outputFilePosition += ioOutputDataPackets;
            
            if (destinationFormat.mFramesPerPacket) {
                // The format has constant frames per packet.
                totalOutputFrames += (ioOutputDataPackets * destinationFormat.mFramesPerPacket);
            } else if (outputPacketDescriptions != NULL) {
                // variable frames per packet require doing this for each packet (adding up the number of sample frames of data in each packet)
                for (UInt32 i = 0; i < ioOutputDataPackets; ++i) {
                    totalOutputFrames += outputPacketDescriptions[i].mVariableFramesInPacket;
                }
            }
        }
    }
    
    
    if (![self checkError:error withErrorString:@"An Error Occured during the conversion!"]) {
        return;
    }
    
    
    
    // Cleanup
    if (converter) { AudioConverterDispose(converter); }
    if (sourceFileID) { AudioFileClose(sourceFileID); }
    if (afio.srcBuffer) { free(afio.srcBuffer); }
    if (afio.packetDescriptions) { free(afio.packetDescriptions); }
    if (outputBuffer) { free(outputBuffer); }
    if (outputPacketDescriptions) { free(outputPacketDescriptions); }

    
}


/*
 Some audio formats have a magic cookie associated with them which is required to decompress audio data
 When converting audio data you must check to see if the format of the data has a magic cookie
 If the audio data format has a magic cookie associated with it, you must add this information to anAudio Converter
 using AudioConverterSetProperty and kAudioConverterDecompressionMagicCookie to appropriately decompress the data
 http://developer.apple.com/mac/library/qa/qa2001/qa1318.html
 */
- (void)readCookieFromAudioFile:(AudioFileID)sourceFileID converter:(AudioConverterRef)converter {
    // Grab the cookie from the source file and set it on the converter.
    UInt32 cookieSize = 0;
    OSStatus error = AudioFileGetPropertyInfo(sourceFileID, kAudioFilePropertyMagicCookieData, &cookieSize, NULL);
    
    // If there is an error here, then the format doesn't have a cookie - this is perfectly fine as some formats do not.
    if (error == noErr && cookieSize != 0) {
        char *cookie = malloc(cookieSize * sizeof(char));
        
        error = AudioFileGetProperty(sourceFileID, kAudioFilePropertyMagicCookieData, &cookieSize, cookie);
        if (error == noErr) {
            error = AudioConverterSetProperty(converter, kAudioConverterDecompressionMagicCookie, cookieSize, cookie);
            
            if (error != noErr) {
                printf("Could not Set kAudioConverterDecompressionMagicCookie on the Audio Converter!\n");
            }
        } else {
            printf("Could not Get kAudioFilePropertyMagicCookieData from source file!\n");
        }
        
        free(cookie);
    }
}




- (BOOL)checkError:(OSStatus)error withErrorString:(NSString *)string {
    if (error == noErr) {
        return YES;
    }
    
    return NO;
}





-(void)printAudioStreamBasicDescription:(AudioStreamBasicDescription)asbd {
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
