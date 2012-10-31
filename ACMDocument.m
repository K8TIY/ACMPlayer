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
#import "ACMDocument.h"
#import "Onizuka.h"

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

@implementation ACMDocumentController
-(NSInteger)runModalOpenPanel:(NSOpenPanel*)openPanel
            forTypes:(NSArray*)extensions
{
  [openPanel setTreatsFilePackagesAsDirectories:YES];
  return [super runModalOpenPanel:openPanel forTypes:extensions];
}
@end

@interface ACMDocument (Private)
-(void)updateTimeDisplay;
-(void)aiffExportDidEnd:(NSSavePanel*)sheet returnCode:(int)code contextInfo:(void*)contextInfo;
-(NSString*)runScript:(NSString*)script onString:(NSString*)string;
@end

@implementation ACMDocument
-(id)init
{
  self = [super init];
  _showTimeLeft = NO;
  return self;
}

-(void)dealloc
{
  [o_img_pause_pressed release];
  [o_img_play_pressed release];
  [o_img_pause release];
  [o_img_play release];
  if (_musicRenderer) [_musicRenderer release];
  [super dealloc];
}

-(NSString*)windowNibName {return @"ACMDocument";}

-(void)windowControllerDidLoadNib:(NSWindowController*)aController
{
  [super windowControllerDidLoadNib:aController];
  [self setAmp:nil];
  [_progress setDoubleValue:0.0];
  double loopPosition = [_musicRenderer loopPosition];
  if (loopPosition > 0.0) [_progress setLoopPosition:loopPosition];
  NSBundle* mb = [NSBundle mainBundle];
  o_img_play = [[NSImage alloc] initWithContentsOfFile:[mb pathForImageResource:@"play"]];
  o_img_play_pressed = [[NSImage alloc] initWithContentsOfFile:[mb pathForImageResource:@"play_blue"]];
  o_img_pause = [[NSImage alloc] initWithContentsOfFile:[mb pathForImageResource:@"pause"]];
  o_img_pause_pressed = [[NSImage alloc] initWithContentsOfFile:[mb pathForImageResource:@"pause_blue"]];
  [_startStopButton setImage:o_img_play];
  [_startStopButton setAlternateImage:o_img_play_pressed];
  [_epilogueStateButton setTitle:@""];
  if (!_haveEpilogue)
  {
    [_epilogueButton removeFromSuperview];
    _epilogueButton = nil;
  }
  float ampVal = [_ampSlider floatValue];
  [_musicRenderer setAmp:ampVal];
  [[Onizuka sharedOnizuka] localizeWindow:_playerWindow];
}

-(void)windowWillClose:(NSNotification*)note
{
  #pragma unused (note)
  _closing = YES;
  [_musicRenderer setDelegate:nil];
  [_musicRenderer stop];
}

//-(void)windowDidResignMain:(NSNotification*)note
-(void)suspend
{
  if (![_musicRenderer isSuspended])
  {
    [_musicRenderer suspend];
    _suspendedInBackground = YES;
  }
}

-(void)windowDidBecomeMain:(NSNotification*)note
{
  #pragma unused (note)
  NSArray* docs = [[NSDocumentController sharedDocumentController] documents];
  for (ACMDocument* doc in docs)
    if (doc != self) [doc suspend];
  //NSLog(@"windowDidBecomeMain:");
  if (_suspendedInBackground) [_musicRenderer resume];
}

-(BOOL)readFromURL:(NSURL*)url ofType:(NSString *)type error:(NSError**)oError
{
  BOOL loaded = NO;
  NSUInteger loopPoint = 0;
  NSArray* acms = nil;
  NSArray* eps = nil;
  NSString* path = [url path];
  if ([type isEqualToString:@"__ACM__"])
  {
    acms = [NSArray arrayWithObjects:path, NULL];
  }
  else if ([type isEqualToString:@"__MUS__"])
  {
    NSString* parsed = [self runScript:@"mus.py" onString:path];
    NSDictionary* pl = [parsed propertyList];
    acms = [pl objectForKey:@"files"];
    eps = [pl objectForKey:@"epilogues"];
    loopPoint = [[pl objectForKey:@"loop"] intValue];
    if ([eps count]) _haveEpilogue = YES;
  }
  else if (oError)
  {
    NSString* localized = [[Onizuka sharedOnizuka]
                            copyLocalizedTitle:@"__ILLEGAL_FILE_TYPE__"];
    NSString* desc = [NSString stringWithFormat:localized, type];
    [localized release];
    NSDictionary* eDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                        desc, NSLocalizedDescriptionKey,
                                        path, NSFilePathErrorKey, NULL];
    *oError = [NSError errorWithDomain:@"ACMPlayer" code:-1 userInfo:eDict];
  }
  if (acms)
  {
    _musicRenderer = [[ACMRenderer alloc] initWithPlaylist:acms andEpilogues:eps];
    if (_musicRenderer)
    {
      loaded = YES;
      [_musicRenderer setDelegate:self];
      if (loopPoint != 0) [_musicRenderer setLoopPoint:loopPoint];
    }
  }
  return loaded;
}

#pragma mark Action
-(IBAction)startStop:(id)sender
{
  #pragma unused (sender)
  if ([_musicRenderer isPlaying])
  {
    [_musicRenderer stop];
    [_startStopButton setImage:o_img_play];
    [_startStopButton setAlternateImage:o_img_play_pressed];
  }
  else
  {
    [_musicRenderer start];
    [_startStopButton setImage:o_img_pause];
    [_startStopButton setAlternateImage:o_img_pause_pressed];
  }
}

-(IBAction)setAmp:(id)sender
{
  #pragma unused (sender)
  float ampVal = [_ampSlider floatValue];
  [_musicRenderer setAmp:ampVal];
}

-(IBAction)setAmpLo:(id)sender
{
  #pragma unused (sender)
  float ampVal = 0.0f;
  [_ampSlider setFloatValue:ampVal];
  [_musicRenderer setAmp:ampVal];
}

-(IBAction)setAmpHi:(id)sender
{
  #pragma unused (sender)
  float ampVal = 1.0f;
  [_ampSlider setFloatValue:ampVal];
  [_musicRenderer setAmp:ampVal];
}

-(IBAction)toggleTimeDisplay:(id)sender
{
  #pragma unused (sender)
  //NSLog(@"toggleTimeDisplay");
  _showTimeLeft = !_showTimeLeft;
  [self updateTimeDisplay];
}

-(IBAction)setLoop:(id)sender
{
  #pragma unused (sender)
  [_musicRenderer setDoesLoop:([_loopButton state] == NSOnState)];
}

-(IBAction)setProgress:(id)sender
{
  #pragma unused (sender)
  [_musicRenderer suspend];
  [_musicRenderer gotoPosition:[_progress trackingValue]];
  [_musicRenderer resume];
}

-(IBAction)epilogueAction:(id)sender
{
  #pragma unused (sender)
  [_musicRenderer doEpilogue:YES];
  [_loopButton setState:NSOffState];
  [_musicRenderer setDoesLoop:NO];
}

-(IBAction)exportAIFF:(id)sender
{
  #pragma unused (sender)
  NSSavePanel* panel = [NSSavePanel savePanel];
  [panel setAllowedFileTypes:[NSArray arrayWithObject:@"aiff"]];
  NSString* aiffName = [[[[self fileURL] path] stringByDeletingPathExtension]
                        stringByAppendingPathExtension:@"aiff"];
  [panel beginSheetForDirectory:nil file:aiffName
         modalForWindow:_playerWindow modalDelegate:self
         didEndSelector:@selector(aiffExportDidEnd:returnCode:contextInfo:)
         contextInfo:nil];
}

#pragma mark Callback
-(void)aiffExportDidEnd:(NSSavePanel*)sheet returnCode:(int)code
       contextInfo:(void*)ctx
{
  #pragma unused (ctx)
  if (code == NSOKButton)
  {
    NSURL* url = [sheet URL];
    //NSLog(@"Saving to %@", filename);
    [sheet orderOut:nil];
    /*[NSApp beginSheet:_exportSheet modalForWindow:_playerWindow
           modalDelegate:self didEndSelector:NULL contextInfo:nil];*/
    [_progress setShowsProgress:YES];
    [_epilogueStateButton setTitle:NSLocalizedString(@"__EXPORTING__",@"blah")];
    [_epilogueStateButton display];
    // Have to call [_epilogueStateButton display]; because we are hogging the
    // main thread here during the export. Should spawn a new thread but would
    // have to probably start a new renderer or the current one might freak out
    // doing 2 things at once.
    [_musicRenderer exportAIFFToURL:url];
    [_epilogueStateButton setTitle:@""];
    [_progress setShowsProgress:NO];
  }
}

-(void)acmDidFinishPlaying:(id)sender
{
  #pragma unused (sender)
  [_musicRenderer stop];
  [_musicRenderer gotoPosition:0.0];
  [_startStopButton setImage:o_img_play];
  [_startStopButton setAlternateImage:o_img_play_pressed];
}

-(void)acmProgress:(id)renderer
{
  if (renderer && _musicRenderer && _progress && !_closing)
  {
    double percent = [_musicRenderer position];
    [_progress setDoubleValue:percent];
    [self updateTimeDisplay];
    int es = [_musicRenderer epilogueState];
    if (es == acmWillDoEpilogue)
      [[Onizuka sharedOnizuka] localizeObject:_epilogueStateButton
                               withTitle:@"__EPILOGUE_WILL_PLAY__"];
    else if (es == acmDoingEpilogue)
      [[Onizuka sharedOnizuka] localizeObject:_epilogueStateButton
                               withTitle:@"__EPILOGUE_PLAYING__"];
    else [_epilogueStateButton setTitle:@""];
  }
}

// FIXME: is it possible to localize this format?
-(void)updateTimeDisplay
{
  NSString* timeStr;
  double percent = [_musicRenderer position];
  double secs = [_musicRenderer seconds];
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

-(void)acmExportProgress:(id)renderer
{
  #pragma unused (renderer)
  double percent = [_musicRenderer position];
  [_progress setProgressValue:percent];
  [_progress display];
}

#pragma mark Delegate
-(void)windowDidReceiveSpace:(id)sender
{
  [self startStop:sender];
}

#pragma mark Internal
// scriptPath is full or partial path to script file, including extension.
-(NSString*)runScript:(NSString*)script onString:(NSString*)string
{
  NSBundle* bundle = [NSBundle mainBundle];
  NSString* path = [bundle pathForResource:script ofType:nil];
  NSTask* task = [[NSTask alloc] init];
  [task setLaunchPath:path];
  NSPipe* readPipe = [NSPipe pipe];
  NSFileHandle* readHandle = [readPipe fileHandleForReading];
  NSPipe* writePipe = [NSPipe pipe];
  NSFileHandle* writeHandle = [writePipe fileHandleForWriting];
  [task setStandardInput: writePipe];
  [task setStandardOutput: readPipe];
  [task launch];
  [writeHandle writeData:[string dataUsingEncoding:NSUTF8StringEncoding]];
  [writeHandle closeFile];
  NSMutableData* data = [[NSMutableData alloc] init];
  NSData* readData;
  while ((readData = [readHandle availableData]) && [readData length])
    [data appendData:readData];
  [task release];
  NSString* outString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  [data release];
  return [outString autorelease];
}
@end

