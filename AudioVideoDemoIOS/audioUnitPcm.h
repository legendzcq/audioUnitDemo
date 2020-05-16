//
//  audioUnitPcm.h
//  AudioVideoDemoIOS
//
//  Created by 奇少 on 2020/5/14.
//  Copyright © 2020 okjiaoyu. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef enum : NSUInteger {
    recordTypeWAV,
    recordTypeM4A,
    recordTypeDATA,
} recordType;

@interface audioUnitPcm : NSObject
@property (nonatomic,copy) NSString * pcmPath;

@property (nonatomic ) recordType  type;

- (void)startRecordClcik;
- (void)startRecordAACClick;
-(void)strartRecordData;
- (void)stopRecord;
-(void)startSample;
-(void)stopSampleRate;
@end

NS_ASSUME_NONNULL_END
