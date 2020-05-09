//
//  audioEncoder.h
//  AudioVideoDemoIOS
//
//  Created by 奇少 on 2020/5/8.
//  Copyright © 2020 okjiaoyu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN

@interface audioEncoder : NSObject
{
    @public
    AudioConverterRef           mAudioConverter;
    AudioStreamBasicDescription mDestinationFormat;
    AudioStreamBasicDescription mSourceFormat;
    AudioFileID m_recordFile;
    SInt64      m_recordCurrentPacket;
}
- (instancetype)initWithSourceFormat:(AudioStreamBasicDescription)sourceFormat;

- (void)encodeAudioWithSourceBuffer:(void *)sourceBuffer
sourceBufferSize:(UInt32)sourceBufferSize
             pts:(int64_t)pts;

//- (NSString *)createFilePath;
@end

NS_ASSUME_NONNULL_END
