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
#import "TLKData.h"

@implementation TLKString
@synthesize snd = _snd;
@synthesize offset = _offset;
@synthesize length = _length;
//@synthesize vol = _vol;
//@synthesize pitch = _pitch;

-(id)initWithSoundName:(NSString*)name offset:(uint32_t)off length:(uint32_t)len
{
  self = [super init];
  if (name) _snd = [name copy];
  _offset = off;
  _length = len;
  return self;
}

-(void)dealloc
{
  if (_snd) [_snd release];
  [super dealloc];
}
@end

@interface TLKData (Private)
+(NSString*)pathToLocalizedTLKInDirecory:(NSString*)path;
@end

// Map of key's enclosing directory -> KEYData*
// In my case it's /Users/moseshll/BG
static NSMutableDictionary* gTLKData = nil;

@implementation TLKData
@synthesize strings = _strings;
@synthesize loaded = _loaded;

+(void)initialize
{
  gTLKData = [[NSMutableDictionary alloc] init];
}

// Gets an already loaded .tlk by repeatedly stripping path components.
// If not loaded, finds the appropriate key file by doing the same,
// load it, and return it.
+(TLKData*)TLKDataForFile:(NSString*)path loading:(BOOL)load
           withKEYData:(KEYData*)keys
{
  NSFileManager* fm = [[NSFileManager alloc] init];
  NSString* path2 = path;
  TLKData* kd = nil;
  BOOL dir;
  NSString* tlkPath = nil;
  @synchronized(gTLKData)
  {
    tlkPath = [keys pathForLocalizedFileName:nil extension:@"tlk"];
    if (!tlkPath)
    {
      path2 = path;
      do
      {
        NSString* path3 = [path2 stringByDeletingLastPathComponent];
        kd = [gTLKData objectForKey:path3];
        if (kd) break;
        NSString* try = [path3 stringByAppendingPathComponent:@"dialog.tlk"];
        //NSLog(@"TLKDataForFile: trying for .tlk at %@", try);
        if ([fm fileExistsAtPath:try isDirectory:&dir] && !dir)
        {
          tlkPath = try;
          path2 = path3;
          break;
        }
        //NSLog(@"TLKDataForFile: %@=%@?", path2, path3);
        if ([path3 isEqualToString:path2]) break;
        path2 = path3;
      } while (YES);
    }
    if (tlkPath)
    {
      //NSLog(@"GOT IT! %@", tlkPath);
      NSData* data = [[NSData alloc] initWithContentsOfFile:tlkPath];
      kd = [[TLKData alloc] initWithData:data];
      if (load) [kd setData];
      [data release];
      [gTLKData setObject:kd forKey:path2];
      [kd release];
    }
  } // Synchronized
  [fm release];
  return kd;
}

-(id)initWithData:(NSData*)data
{
  self = [super init];
  _loaded = 0.0;
  _data = [data copy];
  _strings = [[NSMutableArray alloc] init];
  _resNames = [[NSMutableDictionary alloc] init];
  return self;
}

-(void)dealloc
{
  if (_strings) [_strings release];
  if (_data) [_data release];
  if (_resNames) [_resNames release];
  [super dealloc];
}

-(void)setData
{
  if (_data)
  {
    unsigned char* buff = calloc(1, 12);
    _bytes = [_data bytes];
    const unsigned char* p = _bytes;
    memcpy(buff, p, 4);
    //NSLog(@"Signature: '%s'", buff);
    p += 4;
    memcpy(buff, p, 4);
    //NSLog(@"Version: '%s'", buff);
    p += 6;
    uint32_t n = EndianU32_LtoN(*(uint32_t*)p);
    p += 4;
    _offset = EndianU32_LtoN(*(uint32_t*)p);
    p += 4;
    //NSLog(@"There are %d strings at offset %d", n, _offset);
    uint32_t i;
    for (i = 0; i < n; i++)
    {
      /*
      00 - No message data
      01 - Text exists
      02 - Sound exists
      03 - Standard message. Ambient message. Used for sound without text (BG1) or message displayed over characters head (BG2) , Message with tags (for instance <CHARNAME>) for all games except BG2
      07 - Message with tags (for instance <CHARNAME> ) in BG2 only
      */
      //uint16_t flag = EndianU32_LtoN(*(uint16_t*)p);
      p += 2;
      bzero(buff, 12);
      (void)strncpy(buff, p, 8);
      p += 8;
      //uint32_t vol = EndianU32_LtoN(*(uint32_t*)p);
      p += 4;
      //uint32_t pitch = EndianU32_LtoN(*(uint32_t*)p);
      p += 4;
      uint32_t off = EndianU32_LtoN(*(uint32_t*)p);
      p += 4;
      uint32_t len = EndianU32_LtoN(*(uint32_t*)p);
      p += 4;
      NSString* str = nil;
      if (strlen(buff))
      {
        str = [[NSString alloc] initWithCString:buff encoding:NSUTF8StringEncoding];
        // FIXME use the flags to determine whether the value should be replaced.
        //if (nil == [_resNames objectForKey:str])
        {
          [_resNames setObject:[NSNumber numberWithUnsignedInt:i] forKey:str];
        }
      }
      TLKString* string = [[TLKString alloc] initWithSoundName:str
                                             offset:_offset + off
                                             length:len];
      if (str) [str release];
      @synchronized(self)
      {
        [_strings addObject:string];
        _loaded = (double)i / (double)n;
      }
      [string release];
    }
    //NSLog(@"%@", _resNames);
    free(buff);
  }
  _loaded = 1.0;
}

-(NSString*)stringAtIndex:(uint32_t)i
{
  NSString* val = nil;
  @synchronized(self)
  {
    if (i >= [_strings count]) return nil;
    TLKString* str = [_strings objectAtIndex:i];
    val = [[NSString alloc] initWithBytes:_bytes + str.offset
                            length:str.length
                            encoding:NSUTF8StringEncoding];
    [val autorelease];
  }
  return val;
}

-(NSNumber*)indexOfResName:(NSString*)name
{
  return [_resNames objectForKey:name];
}
@end
