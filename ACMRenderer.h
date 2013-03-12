/*
 * Copyright © 2010-2013, Brian "Moses" Hall
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
#import "ACMData.h"

@protocol ACM
-(void)acmDidFinishPlaying:(id)renderer;
-(void)acmProgress:(id)renderer;
-(void)acmEpilogueStateChanged:(id)renderer;
@end

enum
{
  acmNoEpilogue,
  acmWillDoEpilogue,
  acmWillDoFinalEpilogue,
  acmDoingEpilogue
};

@interface ACMRenderer : NSObject <NSCopying>
{
  double                 _amp;
  double                 _totalSeconds;
  NSArray*               _acmFiles; // For NSCopying
  NSArray*               _epilogueFiles; // For NSCopying
  NSData*                _data; // For NSCopying
  NSMutableArray*        _acms; // Array of ACMData*
  NSMutableArray*        _epilogueNames; // Names, may be nil
  NSMutableDictionary*   _epilogues; // Name -> ACMData*, may be nil
  AUGraph                _ag;
  id                     _delegate;
  unsigned               _channels;
  uint64_t               _totalPCM;
  uint64_t               _totalPCMPlayed;
  uint64_t               _totalEpiloguePCM;
  uint64_t               _totalEpiloguePCMPlayed;
  NSUInteger             _currentACM; // 0-based
  //FIXME: _loopPoint should be a PCM number for efficiency
  NSUInteger             _loopIndex; // 0-based
  BOOL                   _nowPlaying;
  BOOL                   _loops;
  BOOL                   _hasFinalEpilogue;
  // When we have epilogues, and we get done with an acm that has one,
  //   we will play the epilogue and stop playing (and clear these flags).
  int                    _epilogue;
}
@property(readonly) double amp;
@property(readonly) double seconds;
@property(readonly) unsigned channels;
@property(readonly) BOOL playing;
@property(readonly) BOOL loops;
@property(readonly) int epilogueState;

-(ACMRenderer*)initWithPlaylist:(NSArray*)list andEpilogues:(NSArray*)epilogues;
-(ACMRenderer*)initWithData:(NSData*)data;
-(void)setAmp:(double)val;
-(void)start;
-(void)stop;
-(double)pct;
-(void)gotoPct:(double)pct;
-(void)setDelegate:(id)delegate;
-(void)setDoesLoop:(BOOL)loop;
-(void)setLoopIndex:(NSUInteger)li;
-(double)loopPct;
-(void)doEpilogue:(BOOL)flag;
-(void)getEpilogueStartPct:(double*)oStart endPct:(double*)oEnd
       pctDelta:(double*)oDelta;
-(void)exportAIFFToURL:(NSURL*)url;
@end

#ifndef ACMPLAYER_DEBUG
#define ACMPLAYER_DEBUG 0
#endif

#if ACMPLAYER_DEBUG
void hexdump(void *data, int size);
#endif
