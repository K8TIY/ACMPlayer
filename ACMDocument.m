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

NSArray* gGameIcons;

@implementation ACMDocumentController
-(NSInteger)runModalOpenPanel:(NSOpenPanel*)openPanel
            forTypes:(NSArray*)extensions
{
  [openPanel setTreatsFilePackagesAsDirectories:YES];
  return [super runModalOpenPanel:openPanel forTypes:extensions];
}
@end

@interface ACMDocument (Private)
-(NSString*)_runScript:(NSString*)script onString:(NSString*)string;
@end

@implementation ACMDocument
+(void)initialize
{
  gGameIcons = [[NSArray alloc] initWithObjects:@"bg.icns", @"bg2.icns",
                                @"iwd.icns", NULL];
}

-(NSString*)windowNibName {return @"ACMDocument";}

-(void)windowControllerDidLoadNib:(NSWindowController*)controller
{
  [super windowControllerDidLoadNib:controller];
  [self setAmp:nil];
  [_progress setDoubleValue:0.0];
  double loopPct = [_renderer loopPct];
  if (loopPct > 0.0) [_progress setLoopPct:loopPct];
  _trackTitleField.wantsLayer = YES;
  _trackTitleField.layer.cornerRadius = 4.0f;
  _trackTitleField.layer.borderWidth = 1.0f;
  NSColor* border = [NSColor colorWithCalibratedRed:0.2f green:0.3f
                             blue:0.1f alpha:1.0f];
  NSColor* bg  = [_renderer isVorbis]?
                   [NSColor colorWithCalibratedRed:0.79f green:0.94f
                            blue:0.98f alpha:1.0f]:
                   [NSColor colorWithCalibratedRed:0.94f green:0.98f
                            blue:0.79f alpha:1.0f];
  _trackTitleField.layer.borderColor = border.CGColor;
  [_trackTitleField setBackgroundColor:bg];
  [_trackTitleField setStringValue:(_trackTitle)? _trackTitle:@""];
  NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];
  BOOL loop = [defs floatForKey:@"defaultLoop"];
  [_renderer setDoesLoop:loop];
  [_loopButton setState:(loop)? NSOnState:NSOffState];
  if (_game < kUnknownGameIdentifier)
  {
    NSImage* img = [NSImage imageNamed:[gGameIcons objectAtIndex:_game]];
    [_gameIcon setImage:img];
  }
}

-(BOOL)readFromURL:(NSURL*)url ofType:(NSString *)type error:(NSError**)oError
{
  _game = kUnknownGameIdentifier;
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
    NSBundle* mb = [NSBundle mainBundle];
    _game = [ACMGame identifyGameAtURL:url];
    if (_game <= kLastGameIdentifier)
    {
      NSString* name = (_game == kBaldursGateGameIdentifier)? @"bg":
        ((_game == kBaldursGate2GameIdentifier)? @"bg2":@"iwd");
      NSString* p = [mb pathForResource:name ofType:@"strings"];
      NSDictionary* trackTitles = [[NSDictionary alloc] initWithContentsOfFile:p];
      if (trackTitles)
      {
        NSString* title = [trackTitles objectForKey:[[url lastPathComponent] lowercaseString]];
        if (title) _trackTitle = [[NSString alloc] initWithString:title];
        [trackTitles release];
      }
    }
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

