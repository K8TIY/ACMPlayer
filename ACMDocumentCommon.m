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

NSImage* gPlayImage = nil;
NSImage* gPlayPressedImage = nil;
NSImage* gPauseImage = nil;
NSImage* gPausePressedImage = nil;

@implementation ACMDocumentCommon
+(void)initialize
{
  NSBundle* mb = [NSBundle mainBundle];
  gPlayImage = [[NSImage alloc] initWithContentsOfFile:[mb pathForImageResource:@"play"]];
  gPlayPressedImage = [[NSImage alloc] initWithContentsOfFile:[mb pathForImageResource:@"play_blue"]];
  gPauseImage = [[NSImage alloc] initWithContentsOfFile:[mb pathForImageResource:@"pause"]];
  gPausePressedImage = [[NSImage alloc] initWithContentsOfFile:[mb pathForImageResource:@"pause_blue"]];
}

-(void)dealloc
{
  if (_renderer) [_renderer release];
  [super dealloc];
}

-(void)windowControllerDidLoadNib:(NSWindowController*)controller
{
  #pragma unused (controller)
  [_startStopButton setImage:gPlayImage];
  [_startStopButton setAlternateImage:gPlayPressedImage];
  NSWindow* w = [[[self windowControllers] objectAtIndex:0] window];
  [[Onizuka sharedOnizuka] localizeWindow:w];
  NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];
  float ampVal = [defs floatForKey:@"defaultVol"];
  if (_renderer) [_renderer setAmp:ampVal];
  [_ampSlider setDoubleValue:ampVal];
}

-(ACMRenderer*)copyRendererForAIFFExport
{
  return [_renderer copy];
}

-(NSString*)AIFFFilename
{
  return [[[[[self fileURL] path] lastPathComponent]
           stringByDeletingPathExtension]
           stringByAppendingPathExtension:@"aiff"];
}

#pragma mark Action
-(IBAction)startStop:(id)sender
{
  #pragma unused (sender)
  if (_renderer && _renderer.playing)
  {
    [_renderer stop];
    [_startStopButton setImage:gPlayImage];
    [_startStopButton setAlternateImage:gPlayPressedImage];
  }
  else
  {
    [_renderer start];
    [_startStopButton setImage:gPauseImage];
    [_startStopButton setAlternateImage:gPausePressedImage];
  }
}

-(IBAction)rewind:(id)sender
{
  #pragma unused (sender)
  [_renderer gotoPct:0.0];
  [_progress setDoubleValue:0.0];
  [self _updateTimeDisplay];
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
  [_renderer gotoPct:[_progress trackingValue]];
  [_renderer resume];
}

-(IBAction)setLoop:(id)sender
{
  #pragma unused (sender)
  [_renderer setDoesLoop:([_loopButton state] == NSOnState)];
  [_progress setLoopPct:[_renderer loopPct]];
}

-(IBAction)exportAIFF:(id)sender
{
  #pragma unused (sender)
  NSSavePanel* panel = [NSSavePanel savePanel];
  [panel setAllowedFileTypes:[NSArray arrayWithObject:@"aiff"]];
  [panel setCanSelectHiddenExtension:YES];
  NSString* aiffName = [self AIFFFilename];
  [panel beginSheetForDirectory:nil file:aiffName
         modalForWindow:_docWindow modalDelegate:self
         didEndSelector:@selector(aiffExportDidEnd:returnCode:contextInfo:)
         contextInfo:nil];
}

#pragma mark Delegate
-(void)windowWillClose:(NSNotification*)note
{
  #pragma unused (note)
  _closing = YES;
  [_renderer setDelegate:nil];
  [_renderer stop];
}

-(void)windowDidReceiveSpace:(id)sender
{
  [self startStop:sender];
}

#pragma mark Callback
-(void)aiffExportDidEnd:(NSSavePanel*)sheet returnCode:(int)code
       contextInfo:(void*)ctx
{
  #pragma unused (ctx)
  if (code == NSOKButton)
  {
    NSURL* url = [sheet URL];
    ACMRenderer* r = [self copyRendererForAIFFExport];
    [r exportAIFFToURL:url];
    [r release];
    [sheet orderOut:nil];
  }
}

#pragma mark Notification
-(void)acmDidFinishPlaying:(id)sender
{
  #pragma unused (sender)
  [_renderer stop];
  [_renderer gotoPct:0.0];
  [_startStopButton setImage:gPlayImage];
  [_startStopButton setAlternateImage:gPlayPressedImage];
}

-(void)acmProgress:(id)renderer
{
  #pragma unused (renderer)
  if (_renderer && _progress && !_closing)
  {
    [_progress setDoubleValue:[_renderer pct]];
    [self _updateTimeDisplay];
  }
}

#pragma mark Internal
// FIXME: is it possible to localize this format?
-(void)_updateTimeDisplay
{
  NSString* timeStr;
  double pct = _renderer.pct;
  double secs = _renderer.seconds;
  if (_showTimeLeft) secs = secs * (1.0 - pct);
  else secs = secs * pct;
  timeStr = [[NSString alloc] initWithFormat:@"%s%d:%02d:%02d",
                    (_showTimeLeft) ? "-" : "",
                    (int)(secs / 3600.0),
                    (int)(secs / 60.0) % 60,
                    (int)secs % 60];
  [_timeButton setTitle:timeStr];
  [timeStr release];
}

@end
