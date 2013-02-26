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
#import "ACMDocumentCommon.h"
#import "Onizuka.h"

@interface ACMDocumentCommon (Private)
-(void)_updateTimeDisplay;
@end

// Subclass that can detect spacebar and send notification to its delegate.
@implementation ACMWindow
-(void)sendEvent:(NSEvent*)event
{
  BOOL handled = NO;
  //NSLog(@"sendEvent: %@", event);
  if ([event type] == NSKeyUp || [event type] == NSKeyDown)
  {
    //NSLog(@"got '%@'", [event charactersIgnoringModifiers]);
    if ([[event charactersIgnoringModifiers] isEqualToString:@" "])
    {
      if ([event type] == NSKeyUp)
      {
        id del = [self delegate];
        if (del && [del respondsToSelector:@selector(windowDidReceiveSpace:)])
          [del windowDidReceiveSpace:self];
      }
      handled = YES;
    }
  }
  if (!handled) [super sendEvent:event];
}
@end

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

-(IBAction)setAmpLo:(id)sender
{
  #pragma unused (sender)
  float ampVal = 0.0f;
  [_ampSlider setFloatValue:ampVal];
  [_renderer setAmp:ampVal];
}

-(IBAction)setAmpHi:(id)sender
{
  #pragma unused (sender)
  float ampVal = 1.0f;
  [_ampSlider setFloatValue:ampVal];
  [_renderer setAmp:ampVal];
}

-(IBAction)toggleTimeDisplay:(id)sender
{
  #pragma unused (sender)
  _showTimeLeft = !_showTimeLeft;
  [self _updateTimeDisplay];
}

-(IBAction)setProgress:(id)sender
{
  #pragma unused (sender)
  [_renderer suspend];
  [_renderer gotoPosition:[_progress trackingValue]];
  [_renderer resume];
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

#pragma mark Internal
// FIXME: is it possible to localize this format?
-(void)_updateTimeDisplay
{
  NSString* timeStr;
  double percent = [_renderer position];
  double secs = [_renderer seconds];
  if (_showTimeLeft) secs = secs * (1.0 - percent);
  else secs = secs * percent;
  timeStr = [[NSString alloc] initWithFormat:@"%s%d:%02d:%02d",
                    (_showTimeLeft) ? "-" : "",
                    (int)(secs / 3600.0),
                    (int)(secs / 60.0) % 60,
                    (int)secs % 60];
  [_timeButton setTitle:timeStr];
  [timeStr release];
}

@end
