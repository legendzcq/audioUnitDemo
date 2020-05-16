//
//  audioPlayer.h
//  AudioVideoDemoIOS
//
//  Created by 奇少 on 2020/5/14.
//  Copyright © 2020 okjiaoyu. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class audioPlayer;
@protocol OKPlayerDelegate <NSObject>

- (void)onPlayToEnd:(audioPlayer *)player;

@end


@interface audioPlayer : NSObject
@property (nonatomic, weak) id<OKPlayerDelegate> delegate;

-(void)playWithMemory:(NSStream *)stream;
-(void)playWithURL:(NSString *)urlStr;

- (double)getCurrentTime;
@end

NS_ASSUME_NONNULL_END
