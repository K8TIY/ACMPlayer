/*
 * Copyright © 2010-2011, Brian "Moses" Hall
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */
#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreAudio/AudioHardware.h>
#import <CoreServices/CoreServices.h>
#import <AudioToolbox/AudioToolbox.h>
#import "libacm.h"

@protocol ACM
-(void)acmDidFinishPlaying:(id)renderer;
-(void)acmProgress:(id)renderer;
-(void)acmExportProgress:(id)renderer;
@end

enum
{
  acmNoEpilogue,
  acmWillDoEpilogue,
  acmDoingEpilogue,
  acmDidEpilogue
};

@interface ACMRenderer : NSObject //<NSCopying> This would make AIFF rendering easier
{
  float _amp;
  double _totalSeconds;
  NSMutableArray* _acms; // Array of NSValue of ACMStream*
  NSMutableArray* _epilogueNames; // Names, may be nil
  NSMutableDictionary* _epilogues; // Name -> NSValue -> ACMStream*, may be nil
  AUGraph _ag;
  id _delegate;
  unsigned long _totalPCM;
  unsigned long _totalPCMPlayed;
  NSUInteger _currentACM; // 0-based
  NSUInteger _loopPoint; // 0-based
  BOOL _nowPlaying;
  BOOL _suspended;
  BOOL _loop;
  BOOL _mono;
  // When we have epilogues, and we get done with an acm that has one,
  //   we will play the epilogue and stop playing (and clear these flags).
  int _epilogue;
}
@property (readonly) BOOL mono;

-(ACMRenderer*)initWithPlaylist:(NSArray*)list andEpilogues:(NSArray*)epilogues;
-(float)amp;
-(void)setAmp:(float)val;
-(void)start;
-(void)stop;
-(void)suspend;
-(void)resume;
-(BOOL)isSuspended;
-(double)position;
-(void)gotoPosition:(double)pos;
-(double)loopPosition;
-(double)seconds;
-(BOOL)isPlaying;
-(void)setDelegate:(id)delegate;
-(void)setDoesLoop:(BOOL)loop;
-(void)setLoopPoint:(NSUInteger)lp;
-(NSUInteger)loopPoint;
-(BOOL)doesLoop;
-(int)epilogueState;
-(void)doEpilogue:(BOOL)flag;
-(void)exportAIFFToURL:(NSURL*)url;
@end
