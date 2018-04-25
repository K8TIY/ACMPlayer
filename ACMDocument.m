/*
 * Copyright © 2010-2018, Brian "Moses" Hall
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
-(void)_aiffExportDidEnd:(NSSavePanel*)sheet returnCode:(int)code
       contextInfo:(void*)contextInfo;
-(NSString*)_runScript:(NSString*)script onString:(NSString*)string;
@end

@implementation ACMDocument
-(NSString*)windowNibName {return @"ACMDocument";}

-(void)windowControllerDidLoadNib:(NSWindowController*)aController
{
  [super windowControllerDidLoadNib:aController];
  [self setAmp:nil];
  [_progress setDoubleValue:0.0];
  double loopPct = [_renderer loopPct];
  if (loopPct > 0.0) [_progress setLoopPct:loopPct];
  if (!_haveEpilogue)
  {
    [_epilogueButton removeFromSuperview];
    _epilogueButton = nil;
  }
  [_epilogueStateButton setTitle:@""];
  NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];
  BOOL loop = [defs floatForKey:@"defaultLoop"];
  [_renderer setDoesLoop:loop];
  [_loopButton setState:(loop)? NSOnState:NSOffState];
}

-(BOOL)readFromURL:(NSURL*)url ofType:(NSString *)type error:(NSError**)oError
{
  BOOL loaded = NO;
  NSUInteger loopIndex = 0;
  NSArray* acms = nil;
  NSArray* eps = nil;
  NSString* path = [url path];
  if ([type isEqualToString:@"__ACM__"] || [type isEqualToString:@"__WAV__"])
  {
    acms = [NSArray arrayWithObjects:path, NULL];
  }
  else if ([type isEqualToString:@"__MUS__"])
  {
    NSString* parsed = [self _runScript:@"mus.py" onString:path];
    NSDictionary* pl = [parsed propertyList];
    acms = [pl objectForKey:@"files"];
    eps = [pl objectForKey:@"epilogues"];
    loopIndex = [[pl objectForKey:@"loop"] intValue];
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
      if (loopIndex != 0) [_renderer setLoopIndex:loopIndex];
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

#pragma mark Callback
-(void)acmEpilogueStateChanged:(id)renderer
{
  #pragma unused (renderer)
  if (_renderer && _progress && !_closing)
  {
    double start, end, delta;
    [_renderer getEpilogueStartPct:&start endPct:&end pctDelta:&delta];
    //NSLog(@"start %f, end %f, delta %f pct %f", start, end, delta, [_renderer pct]);
    [_progress setDoubleValue:[_renderer pct]];
    [_progress setEpilogueStartPct:start endPct:end];
    int es = [_renderer epilogueState];
    if (es == acmNoEpilogue || es == acmWillDoFinalEpilogue)
    {
      [_epilogueButton setEnabled:YES];
      [_epilogueStateButton setTitle:@""];
    }
    else
    {
      [_epilogueButton setEnabled:NO];
      if (es == acmWillDoEpilogue)
      {
        [[Onizuka sharedOnizuka] localizeObject:_epilogueStateButton
                                 withTitle:@"__EPILOGUE_WILL_PLAY__"];
      }
      else if (es == acmDoingEpilogue)
      {
        [[Onizuka sharedOnizuka] localizeObject:_epilogueStateButton
                                 withTitle:@"__EPILOGUE_PLAYING__"];
      }
    }
  }
}

#pragma mark Internal
// script is full or partial path to script file, including extension.
-(NSString*)_runScript:(NSString*)script onString:(NSString*)string
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

