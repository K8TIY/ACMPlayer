//
//  ACMDocumentCommon.m
//  ACMPlayer
//
//  Created by Moses Hall on 2/13/13.
//  Copyright 2013 __MyCompanyName__. All rights reserved.
//

#import "ACMDocumentCommon.h"
#import "Onizuka.h"

@implementation ACMDocumentCommon

-(void)dealloc
{
  [_img_pause_pressed release];
  [_img_play_pressed release];
  [_img_pause release];
  [_img_play release];
  if (_renderer) [_renderer release];
  [super dealloc];
}

-(void)windowControllerDidLoadNib:(NSWindowController*)controller
{
  #pragma unused (controller)
  NSBundle* mb = [NSBundle mainBundle];
  _img_play = [[NSImage alloc] initWithContentsOfFile:[mb pathForImageResource:@"play"]];
  _img_play_pressed = [[NSImage alloc] initWithContentsOfFile:[mb pathForImageResource:@"play_blue"]];
  _img_pause = [[NSImage alloc] initWithContentsOfFile:[mb pathForImageResource:@"pause"]];
  _img_pause_pressed = [[NSImage alloc] initWithContentsOfFile:[mb pathForImageResource:@"pause_blue"]];
  [_startStopButton setImage:_img_play];
  [_startStopButton setAlternateImage:_img_play_pressed];
  NSWindow* w = [[[self windowControllers] objectAtIndex:0] window];
  [[Onizuka sharedOnizuka] localizeWindow:w];
}

#pragma mark Action
-(IBAction)startStop:(id)sender
{
  #pragma unused (sender)
  if (_renderer && [_renderer isPlaying])
  {
    [_renderer stop];
    [_startStopButton setImage:_img_play];
    [_startStopButton setAlternateImage:_img_play_pressed];
  }
  else
  {
    [_renderer start];
    [_startStopButton setImage:_img_pause];
    [_startStopButton setAlternateImage:_img_pause_pressed];
  }
}

-(IBAction)setAmp:(id)sender
{
  #pragma unused (sender)
  if (_renderer)
  {
    float ampVal = [_ampSlider floatValue];
    [_renderer setAmp:ampVal];
  }
}

-(IBAction)setLoop:(id)sender
{
  #pragma unused (sender)
  [_renderer setDoesLoop:([_loopButton state] == NSOnState)];
}

#pragma mark Notification
-(void)acmDidFinishPlaying:(id)sender
{
  #pragma unused (sender)
  [_renderer stop];
  [_renderer gotoPosition:0.0];
  [_startStopButton setImage:_img_play];
  [_startStopButton setAlternateImage:_img_play_pressed];
}
@end
