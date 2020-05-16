//
//  audioDecodePCM.h
//  AudioVideoDemoIOS
//
//  Created by 奇少 on 2020/5/15.
//  Copyright © 2020 okjiaoyu. All rights reserved.
//

#import <Foundation/Foundation.h>
@import AudioToolbox;
#import "audioPlayer.h"


NS_ASSUME_NONNULL_BEGIN

@interface audioDecodePCM : NSObject

- (instancetype)initWithSourceURL:(NSURL *)sourceURL;

@property (readonly, nonatomic, strong) NSURL *sourceURL;

//@property (readonly, nonatomic, strong) NSURL *destinationURL;

-(void)startDecode;
@property (nonatomic, strong) audioPlayer *audioPlay;

@end


NS_ASSUME_NONNULL_END
