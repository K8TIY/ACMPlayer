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
#import "ACMDocument.h"
#import "Onizuka.h"
#import <objc/runtime.h>

@implementation ACMDocumentController
-(NSInteger)runModalOpenPanel:(NSOpenPanel*)openPanel
            forTypes:(NSArray*)extensions
{
  [openPanel setTreatsFilePackagesAsDirectories:YES];
  return [super runModalOpenPanel:openPanel forTypes:extensions];
}
@end

@interface ACMDocument (Private)
-(void)aiffExportDidEnd:(NSSavePanel*)sheet returnCode:(int)code
       contextInfo:(void*)contextInfo;
-(NSString*)runScript:(NSString*)script onString:(NSString*)string;
@end

@implementation ACMDocument
-(NSString*)windowNibName {return @"ACMDocument";}

-(void)windowControllerDidLoadNib:(NSWindowController*)aController
{
  [super windowControllerDidLoadNib:aController];
  [self setAmp:nil];
  [_progress setDoubleValue:0.0];
  double loopPosition = [_renderer loopPosition];
  if (loopPosition > 0.0) [_progress setLoopPosition:loopPosition];
  if (!_haveEpilogue)
  {
    [_epilogueButton removeFromSuperview];
    _epilogueButton = nil;
  }
  [_epilogueStateButton setTitle:@""];
}

//-(void)windowDidResignMain:(NSNotification*)note
-(void)suspend
{
  if (![_renderer isSuspended])
  {
    [_renderer suspend];
    _suspendedInBackground = YES;
  }
}

-(void)windowDidBecomeMain:(NSNotification*)note
{
  #pragma unused (note)
  NSArray* docs = [[NSDocumentController sharedDocumentController] documents];
  for (ACMDocument* doc in docs)
    if (doc != self)
      if ([doc respondsToSelector:@selector(suspend)])
        [doc suspend];
  if (_suspendedInBackground) [_renderer resume];
}

-(BOOL)readFromURL:(NSURL*)url ofType:(NSString *)type error:(NSError**)oError
{
  BOOL loaded = NO;
  NSUInteger loopPoint = 0;
  NSArray* acms = nil;
  NSArray* eps = nil;
  NSString* path = [url path];
  if ([type isEqualToString:@"__ACM__"] || [type isEqualToString:@"__WAV__"])
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
    _renderer = [[ACMRenderer alloc] initWithPlaylist:acms andEpilogues:eps];
    if (_renderer)
    {
      loaded = YES;
      [_renderer setDelegate:self];
      if (loopPoint != 0) [_renderer setLoopPoint:loopPoint];
    }
  }
  return loaded;
}

#pragma mark Action
-(IBAction)epilogueAction:(id)sender
{
  #pragma unused (sender)
  [_renderer doEpilogue:YES];
  [_loopButton setState:NSOffState];
  [_renderer setDoesLoop:NO];
}

-(IBAction)exportAIFF:(id)sender
{
  #pragma unused (sender)
  NSSavePanel* panel = [NSSavePanel savePanel];
  [panel setAllowedFileTypes:[NSArray arrayWithObject:@"aiff"]];
  [panel setCanSelectHiddenExtension:YES];
  NSString* aiffName = [[[[[self fileURL] path] lastPathComponent]
                         stringByDeletingPathExtension]
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
    [_renderer exportAIFFToURL:url];
    [_epilogueStateButton setTitle:@""];
    [_progress setShowsProgress:NO];
  }
}

-(void)acmProgress:(id)renderer
{
  if (renderer && _renderer && _progress && !_closing)
  {
    double percent = [_renderer position];
    [_progress setDoubleValue:percent];
    [self updateTimeDisplay];
    int es = [_renderer epilogueState];
    if (es == acmWillDoEpilogue)
      [[Onizuka sharedOnizuka] localizeObject:_epilogueStateButton
                               withTitle:@"__EPILOGUE_WILL_PLAY__"];
    else if (es == acmDoingEpilogue)
      [[Onizuka sharedOnizuka] localizeObject:_epilogueStateButton
                               withTitle:@"__EPILOGUE_PLAYING__"];
    else [_epilogueStateButton setTitle:@""];
  }
}

-(void)acmExportProgress:(id)renderer
{
  #pragma unused (renderer)
  double percent = [_renderer position];
  [_progress setProgressValue:percent];
  [_progress display];
}

#pragma mark Internal
// script is full or partial path to script file, including extension.
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
  NSString* outString = [[NSString alloc] initWithData:data
                                          encoding:NSUTF8StringEncoding];
  [data release];
  return [outString autorelease];
}
@end

