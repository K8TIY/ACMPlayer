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
#import "BIFFDocument.h"
#import "Onizuka.h"

#define SIZE_BUFSZ 7
static void format_size(char buf[SIZE_BUFSZ], uint64_t sz);

@implementation NSIndexSet (IndexAtIndex)
-(NSUInteger)indexAtIndex:(NSUInteger)anIndex
{
  if (anIndex >= [self count]) return NSNotFound;
  NSUInteger idx = [self firstIndex];
  for (NSUInteger i = 0; i < anIndex; i++)
    idx = [self indexGreaterThanIndex:idx];
  return idx;
}
@end

@interface BIFFDocument (Private)
-(void)_auxLoadData;
-(void)_timerAction:(NSTimer*)t;
-(void)_tableReturn:(id)sender;
-(void)_endSheet:(NSPanel*)sheet returnCode:(int)code
       contextInfo:(void*)ctx;
@end


@implementation BIFFDocument
-(id)init
{
  self = [super init];
  if (self)
  {
    _lastSelectedRow = -1;
  }
  return self;
}

-(void)dealloc
{
  if (_indices) [_indices release];
  [super dealloc];
}

-(NSString*)windowNibName
{
  return @"BIFFDocument";
}

-(void)windowControllerDidLoadNib:(NSWindowController*)wc
{
  [super windowControllerDidLoadNib:wc];
  [_table setTarget:self];
  [_table setDoubleAction:@selector(doubleClick:)];
  NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];
  BOOL loop = [defs floatForKey:@"defaultLoopBIFF"];
  [_renderer setDoesLoop:loop];
  [_loopButton setState:(loop)? NSOnState:NSOffState];
}

-(void)windowWillClose:(NSNotification*)note
{
  #pragma unused (note)
  if (_timer)
  {
    [_timer invalidate];
    _timer = nil;
  }
  if (_renderer)
  {
    [_renderer setDelegate:nil];
    [_renderer stop];
    [_renderer release];
    _renderer = nil;
  }
}

-(BOOL)readFromData:(NSData*)data ofType:(NSString*)typeName
       error:(NSError**)outError
{
  #pragma unused (data, typeName)
  BOOL ok = YES;
  NSString* key = nil;
  NSString* file = [[self fileURL] path];
  _key = [KEYData KEYDataForFile:file loading:NO];
  _tlk = [TLKData TLKDataForFile:file loading:NO withKEYData:_key];
  _data = [[BIFFData alloc] init];
  [_data setData:data];
  if (0 == [_data.strings count])
  {
    key = @"__NO_SOUNDS__";
    ok = NO;
  }
  else
  {
    _timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
                      selector:@selector(_timerAction:) userInfo:NULL
                      repeats:YES];
    [NSThread detachNewThreadSelector:@selector(_auxLoadData)
              toTarget:self withObject:nil];
  }
  if (!ok && outError != NULL)
  {
    NSString* msg = [[Onizuka sharedOnizuka] copyLocalizedTitle:key];
    NSMutableDictionary* errorDetail = [NSMutableDictionary dictionary];
    [errorDetail setValue:msg forKey:NSLocalizedFailureReasonErrorKey];
		*outError = [NSError errorWithDomain:NSCocoaErrorDomain
                         code:NSFileReadUnknownError userInfo:errorDetail];
    [msg release];
	}
  return ok;
}

-(BOOL)validateMenuItem:(NSMenuItem*)item
{
  SEL action = [item action];
  if (action == @selector(exportAIFF:))
  {
    if (1 != [_table numberOfSelectedRows]) return NO;
  }
  return YES;
}

-(ACMRenderer*)copyRendererForAIFFExport
{
  ACMRenderer* r = nil;
  NSUInteger row = [_table selectedRow];
  if (row != -1)
  {
    if (_indices) row = [_indices indexAtIndex:row];
    NSData* data = [_data dataAtIndex:row];
    r = [[ACMRenderer alloc] initWithData:data];
  }
  return r;
}

-(NSString*)AIFFFilename
{
  NSString* base = [[[[self fileURL] path] lastPathComponent]
                     stringByDeletingPathExtension];
  NSInteger row = [_table selectedRow];
  if (_indices) row = [_indices indexAtIndex:row];
  BIFFFile* str = [_data.strings objectAtIndex:row];
  NSString* val = nil;
  if (row != -1)
  {
    val = [_key resourceNameForPath:[[self fileURL] path] index:str.loc & 0x3FFF];
    if (!val) val = [NSString stringWithFormat:@"%d", str.loc & 0x3FFF];
  }
  if (val) base = [base stringByAppendingFormat:@"-%@", val];
  return [base stringByAppendingPathExtension:@"aiff"];
}

#pragma mark Action
-(IBAction)doSearch:(id)sender
{
  NSString* s = [sender stringValue];
  BOOL reload = NO;
  if (_indices)
  {
    [_indices release];
    _indices = nil;
    reload = YES;
  }
  if (s && [s length])
  {
    _indices = [[NSMutableIndexSet alloc] init];
    NSUInteger n = [_data.strings count];
    NSUInteger i;
    for (i = 0; i < n; i++)
    {
      BIFFFile* str = [_data.strings objectAtIndex:i];
      NSString* name = [_key resourceNameForPath:[[self fileURL] path] index:str.loc & 0x3FFF];
      if (name)
      {
        NSRange range = [name rangeOfString:s options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch];
        if (range.length)
        {
          [_indices addIndex:i];
          reload = YES;
        }
        NSNumber* idx = [_tlk indexOfResName:name];
        if (idx)
        {
          NSString* val = [_tlk stringAtIndex:[idx unsignedIntValue]];
          if (val)
          {
            range = [val rangeOfString:s options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch];
            if (range.length)
            {
              [_indices addIndex:i];
              reload = YES;
            }
          }
        }
      }
    }
  }
  if (reload)
  {
    [_table reloadData];
    [self tableViewSelectionDidChange:nil];
  }
}

-(IBAction)startStop:(id)sender
{
  #pragma unused (sender)
  if (!_renderer)
  {
    NSInteger row = [_table selectedRow];
    if (row != -1)
    {
      if (_indices) row = [_indices indexAtIndex:row];
      NSData* data = [_data dataAtIndex:row];
      _renderer = [[ACMRenderer alloc] initWithData:data];
      [_renderer setDelegate:self];
      [_renderer setAmp:[_ampSlider floatValue]];
      [_renderer setDoesLoop:([_loopButton state] == NSOnState)];
    }
  }
  if (_renderer) [super startStop:self];
}

#pragma mark Delegate
-(void)windowDidReceiveSpace:(id)sender
{
  //[self startStop:sender];
  NSInteger row = [_table selectedRow];
  if (row != -1)
  {
    if (_indices) row = [_indices indexAtIndex:row];
    if (row != _lastSelectedRow)
    {
      if (_renderer)
      {
        [_renderer stop];
        [_renderer release];
        _renderer = nil;
      }
      NSData* data = [_data dataAtIndex:row];
      _renderer = [[ACMRenderer alloc] initWithData:data];
      [_renderer setDelegate:self];
      [_renderer setAmp:[_ampSlider floatValue]];
      [_renderer setDoesLoop:([_loopButton state] == NSOnState)];
      _lastSelectedRow = row;
    }
    
  }
  [super startStop:sender];
}

#pragma mark Internal
-(void)_auxLoadData
{
  NSAutoreleasePool* arp = [[NSAutoreleasePool alloc] init];
  if (1.0 != _key.loaded) [_key setData];
  if (1.0 != _tlk.loaded) [_tlk setData];
  [arp release];
}

-(void)_timerAction:(NSTimer*)t
{
  #pragma unused (t)
  [self doSearch:_search];
  [_table reloadData];
  [self tableViewSelectionDidChange:nil];
  double pct = (_key.loaded + _tlk.loaded) / 2.0;
  //NSLog(@"pct %f from %f, %f, %f", pct, _data.loaded, _key.loaded, _tlk.loaded);
  [_loadProgress setDoubleValue:pct];
  if (pct >= 1.0)
  {
    [_timer invalidate];
    _timer = nil;
    [_loadProgress setHidden:YES];
  }
  if (_data.loaded >= 1.0)
  {
    if (!_didSelect)
    {
      NSIndexSet* is = [NSIndexSet indexSetWithIndex:0];
      [_table selectRowIndexes:is byExtendingSelection:NO];
      _didSelect = YES;
    }
  }
}

-(void)_tableReturn:(id)sender
{
  #pragma unused (sender)
  // FIXME: remove duplication with windowDidReceiveSpace:
  NSInteger row = [_table selectedRow];
  if (row != -1)
  {
    if (_renderer)
    {
      [_renderer stop];
      [_renderer release];
      _renderer = nil;
    }
    if (_indices) row = [_indices indexAtIndex:row];
    NSData* data = [_data dataAtIndex:row];
    _renderer = [[ACMRenderer alloc] initWithData:data];
    [_renderer setDelegate:self];
    [_renderer setAmp:[_ampSlider floatValue]];
    [_renderer setDoesLoop:([_loopButton state] == NSOnState)];
    _lastSelectedRow = row;
    [super startStop:self];
  }
}

-(void)_endSheet:(NSPanel*)sheet returnCode:(int)code
       contextInfo:(void*)ctx
{
  #pragma unused (sheet,code)
  if ([(id)ctx isEqualToString:@"__NO_SOUNDS__"])
    [self close];
}

#pragma mark Table Data Source
-(NSInteger)numberOfRowsInTableView:(NSTableView*)tv
{
  #pragma unused (tv)
  NSInteger cnt = 0;
  @synchronized(_data)
  {
    @synchronized(_key)
    {
      if (_indices) cnt = [_indices count];
      else cnt = [_data.strings count];
    }
  }
  return cnt;
}

-(id)tableView:(NSTableView*)tv objectValueForTableColumn:(NSTableColumn*)col
     row:(NSInteger)row
{
  #pragma unused (tv)
  id identifier = [col identifier];
  id val = nil;
  if (_indices) row = [_indices indexAtIndex:row];
  if ([identifier isEqual:@"1"])
  {
    val = [NSString stringWithFormat:@"%d", row+1];
  }
  else
  {
    BIFFFile* str = [_data.strings objectAtIndex:row];
    if ([identifier isEqual:@"2"])
    {
      val = [NSString stringWithFormat:@"%d", str.loc & 0x3FFF];
    }
    else if ([identifier isEqual:@"3"])
    {
      char buff[SIZE_BUFSZ];
      format_size(buff, str.len);
      val = [NSString stringWithCString:buff encoding:NSUTF8StringEncoding];
    }
    else if ([identifier isEqual:@"4"])
    {
      //val = [NSString stringWithFormat:@"%d", str.type];
      //KEYData* kd = [KEYData KEYDataForFile:[[self fileURL] path] loading:YES];
      val = [_key resourceNameForPath:[[self fileURL] path] index:str.loc & 0x3FFF];
    }
    else if ([identifier isEqual:@"5"])
    {
      //KEYData* kd = [KEYData KEYDataForFile:[[self fileURL] path] loading:YES];
      NSString* name = [_key resourceNameForPath:[[self fileURL] path] index:str.loc & 0x3FFF];
      NSNumber* idx = [_tlk indexOfResName:name];
      if (idx) val = [_tlk stringAtIndex:[idx unsignedIntValue]];
    }
  }
  return val;
}

-(BOOL)tableView:(NSTableView*)tv shouldEditTableColumn:(NSTableColumn*)col
       row:(NSInteger)row
{
  #pragma unused (tv,col,row)
  return NO;
}

-(void)doubleClick:(id)sender
{
  [self _tableReturn:sender];
}

-(void)tableViewSelectionDidChange:(NSNotification*)note
{
  #pragma unused (note)
  if ([_table numberOfSelectedRows] == 1)
  {
    NSInteger row = [_table selectedRow];
    if (_indices) row = [_indices indexAtIndex:row];
    BIFFFile* str = [_data.strings objectAtIndex:row];
    NSString* name = [_key resourceNameForPath:[[self fileURL] path] index:str.loc & 0x3FFF];
    NSString* val = @"";
    if ([name length])
    {
      NSNumber* idx = [_tlk indexOfResName:name];
      if (idx) val = [_tlk stringAtIndex:[idx unsignedIntValue]];
    }
    if (val) [_text setString:val];
  }
}
@end

@implementation BIFFTableView
-(void)keyDown:(NSEvent*)evt
{
  NSString* characters = [evt characters];
  BOOL handled = NO;
  if (([characters length] == 1) && ![evt isARepeat])
  {
    unichar ch = [characters characterAtIndex:0];
    switch (ch)
    {
      case NSNewlineCharacter:
      case NSCarriageReturnCharacter:
      case NSEnterCharacter:
      {
        id del = [self delegate];
        if (del && [del respondsToSelector:@selector(_tableReturn:)])
          [del performSelector:@selector(_tableReturn:) withObject:self];
      }
      handled = YES;
      break;
    }
  }
  if (!handled) [super keyDown:evt];
}
@end

// This code from Dietrich Epp on StackOverflow
// http://stackoverflow.com/questions/7846495/how-to-get-file-size-properly-and-convert-it-to-mb-gb-in-cocoa
static char const SIZE_PREFIXES[] = "kMGTPEZY";

static void format_size(char buf[SIZE_BUFSZ], uint64_t sz)
{
    int pfx = 0;
    unsigned int m, n, rem, hrem;
    uint64_t a;
    if (sz <= 0) {
        memcpy(buf, "0 B", 3);
        return;
    }
    a = sz;
    if (a < 1000) {
        n = a;
        snprintf(buf, SIZE_BUFSZ, "%u B", n);
        return;
    }
    for (pfx = 0, hrem = 0; ; pfx++) {
        rem = a % 1000ULL;
        a = a / 1000ULL;
        if (!SIZE_PREFIXES[pfx + 1] || a < 1000ULL)
            break;
        hrem |= rem;
    }
    n = a;
    if (n < 10) {
        if (rem >= 950) {
            buf[0] = '1';
            buf[1] = '0';
            buf[2] = ' ';
            buf[3] = SIZE_PREFIXES[pfx];
            buf[4] = 'B';
            buf[5] = '\0';
            return;
        } else {
            m = rem / 100;
            rem = rem % 100;
            if (rem > 50 || (rem == 50 && ((m & 1) || hrem)))
                m++;
            snprintf(buf, SIZE_BUFSZ,
                     "%u.%u %cB", n, m, SIZE_PREFIXES[pfx]);
        }
    } else {
        if (rem > 500 || (rem == 500 && ((n & 1) || hrem)))
            n++;
        if (n >= 1000 && SIZE_PREFIXES[pfx + 1]) {
            buf[0] = '1';
            buf[1] = '.';
            buf[2] = '0';
            buf[3] = ' ';
            buf[4] = SIZE_PREFIXES[pfx+1];
            buf[5] = 'B';
            buf[6] = '\0';
        } else {
            snprintf(buf, SIZE_BUFSZ,
                     "%u %cB", n, SIZE_PREFIXES[pfx]);
        }
    }
}
