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
#import "KEYData.h"

// Map of key's enclosing directory -> KEYData*
// In my case it's /Users/moseshll/BG
static NSMutableDictionary* gKEYData = nil;

@interface KEYData (Private)
-(void)findLocalizedDirectory;
@end

@implementation KEYData
@synthesize loaded = _loaded;

+(void)initialize
{
  gKEYData = [[NSMutableDictionary alloc] init];
}

// Gets an already loaded Chitin.key by repeatedly stripping path components.
// If not loaded, finds the appropriate key file by doing the same,
// load it, and return it.
+(KEYData*)KEYDataForFile:(NSString*)path loading:(BOOL)load
{
  NSFileManager* fm = [[NSFileManager alloc] init];
  NSString* path2 = path;
  BOOL dir;
  KEYData* kd = nil;
  do
  {
    //NSLog(@"Start loop 1");
    kd = [gKEYData objectForKey:path2];
    if (kd) break;
    NSString* path3 = [path2 stringByDeletingLastPathComponent];
    //NSLog(@"KEYDataForFile: trying %@", path2);
    //NSLog(@"KEYDataForFile: %@=%@?", path2, path3);
    if ([path3 isEqualToString:path2]) break;
    path2 = path3;
  } while (YES);
  if (!kd)
  {
    path2 = path;
    do
    {
      //NSLog(@"Start loop 2");
      if ([fm fileExistsAtPath:path2 isDirectory:&dir] && dir)
      {
        for (NSString* file in [fm contentsOfDirectoryAtPath:path2 error:NULL])
        {
          //NSLog(@"Looking at %@ (%@)", file, [file pathExtension]);
          if ([[file pathExtension] isEqualToString:@"key"])
          {
            file = [path2 stringByAppendingPathComponent:file];
            //NSLog(@"GOT IT! %@", file);
            kd = [[KEYData alloc] initWithPath:file loading:load];
            [gKEYData setObject:kd forKey:path2];
            [kd release];
            break;
          }
        }
      }
      if (kd) break;
      NSString* path3 = [path2 stringByDeletingLastPathComponent];
      //NSLog(@"KEYDataForFile: trying for key at %@", path3);
      //NSLog(@"KEYDataForFile: %@=%@?", path2, path3);
      if ([path3 isEqualToString:path2]) break;
      path2 = path3;
    } while (YES);
  }
  [fm release];
  return kd;
}

-(id)initWithPath:(NSString*)path loading:(BOOL)load
{
  self = [super init];
  _path = [path copy];
  _biffs = [[NSMutableDictionary alloc] init];
  //_revlocs = [[NSMutableDictionary alloc] init];
  _data = [[NSData alloc] initWithContentsOfFile:path];
  if (load) [self setData];
  return self;
}

-(void)dealloc
{
  if (_path) [_path release];
  if (_biffs) [_biffs release];
  //if (_revlocs) [_revlocs release];
  if (_data) [_data release];
  if (_locDir) [_locDir release];
  [super dealloc];
}

/*
0x0000	4 (char array)	Signature ('KEY ')
0x0004	4 (char array)	Version ('V1 ')
0x0008	4 (dword)	Count of BIF entries
0x000c	4 (dword)	Count of resource entries
0x0010	4 (dword)	Offset (from start of file) to BIF entries
0x0014	4 (dword)	Offset (from start of file) to resource entries
*/

/*
0x0000	4 (dword)	Length of BIF file
0x0004	4 (dword)	Offset from start of file to ASCIIZ BIF filename
0x0008	2 (word)	Length, including terminating NUL, of ASCIIZ BIF filename
0x000a	2 (word)	The 16 bits of this field are used individually to mark the location of the relevant file.

(MSB) xxxx xxxx ABCD EFGH (LSB)
Bits marked A to F determine on which CD the file is stored (A = CD6, F = CD1)
Bit G determines if the file is in the \cache directory
Bit H determines if the file is in the \data directory
*/

/*
0x0000	8 (resref)	Resource name
0x0008	2 (word)	Resource type
0x000a	4 (dword)	Resource locator. The IE resource manager uses 32-bit values as a 'resource index', which codifies the source of the resource as well as which source it refers to. The layout of this value is below.

bits 31-20: source index (the ordinal value giving the index of the corresponding BIF entry)
bits 19-14: tileset index
bits 13- 0: non-tileset file index (any 12 bit value, so long as it matches the value used in the BIF file)
*/
-(void)setData
{
  if (_data)
  {
    NSMutableDictionary* biffs = [[NSMutableDictionary alloc] init];
    NSString* here = [_path stringByDeletingLastPathComponent];
    char* buff = calloc(1, 12);
    const char* bytes = [_data bytes];
    memcpy(buff, bytes, 4);
    //NSLog(@"Signature: '%s'", buff);
    uint32_t nBIF = EndianU32_LtoN(*(uint32_t*)(bytes + 0x0008));
    uint32_t nRes = EndianU32_LtoN(*(uint32_t*)(bytes + 0x000C));
    uint32_t offBIF = EndianU16_LtoN(*(uint32_t*)(bytes + 0x0010));
    uint16_t offRes = EndianU16_LtoN(*(uint32_t*)(bytes + 0x0014));
    //NSLog(@"%d BIF, %d Res", nBIF, nRes);
    const char* p = bytes + offBIF;
    NSMutableString* loc = [[NSMutableString alloc] init];
    for (uint32_t i = 0; i < nBIF; i++)
    {
      [loc setString:@""];
      //uint32_t len = EndianU32_LtoN(*(uint32_t*)p);
      p += 4;
      uint32_t offName = EndianU32_LtoN(*(uint32_t*)p);
      p += 4;
      //uint16_t lenName = EndianU16_LtoN(*(uint16_t*)p);
      p += 2;
      uint16_t bits = EndianU16_LtoN(*(uint16_t*)p);
      p += 2;
      NSString* fileName = [NSString stringWithCString:bytes + offName encoding:NSUTF8StringEncoding];
      fileName = [fileName stringByReplacingOccurrencesOfString:@":" withString:@"/"];
      if ((bits & 0x01) == 0x01)
      {
        [loc setString:[here stringByAppendingPathComponent:fileName]];
      }
      if ((bits & 0x02) == 0x02)
      {
        [loc setString:[here stringByAppendingPathComponent:@"cache/data"]];
        [loc setString:[loc stringByAppendingPathComponent:fileName]];
      }
      if (bits & 0x04)
      {
        [loc setString:[here stringByAppendingPathComponent:@"cd1"]];
        [loc setString:[loc stringByAppendingPathComponent:fileName]];
      }
      if (bits & 0x08)
      {
        [loc setString:[here stringByAppendingPathComponent:@"cd2"]];
        [loc setString:[loc stringByAppendingPathComponent:fileName]];
      }
      if (bits & 0x10)
      {
        [loc setString:[here stringByAppendingPathComponent:@"cd3"]];
        [loc setString:[loc stringByAppendingPathComponent:fileName]];
      }
      if (bits & 0x20)
      {
        [loc setString:[here stringByAppendingPathComponent:@"cd4"]];
        [loc setString:[loc stringByAppendingPathComponent:fileName]];
      }
      if (bits & 0x40)
      {
        [loc setString:[here stringByAppendingPathComponent:@"cd5"]];
        [loc setString:[loc stringByAppendingPathComponent:fileName]];
      }
      if (bits & 0x80)
      {
        [loc setString:[here stringByAppendingPathComponent:@"cd6"]];
        [loc setString:[loc stringByAppendingPathComponent:fileName]];
      }
      if ([loc length])
      {
        NSRange where = [[loc lastPathComponent] rangeOfString:@"loc"
                                                 options:NSCaseInsensitiveSearch];
        if (where.location == 0 && where.length == 3)
        {
          NSString* bare = [[loc lastPathComponent]
                                 stringByDeletingPathExtension];
          NSString* ext = [fileName pathExtension];
          NSString* localized = [self pathForLocalizedFileName:bare
                                      extension:ext];
          if (localized)
            [loc setString:localized];
        }
        NSString* cpy = [[NSString alloc] initWithString:[loc lowercaseString]];
        [biffs setObject:[NSNumber numberWithInt:i] forKey:cpy];
        [cpy release];
      }
      //NSLog(@"BIF %d: len %d, offset to name %d, name length %d, bits %d [%@]
      //(%@)", i, len, offName, lenName, bits, local_BinaryStringForByte(bits),
      //loc);
    }
    p = bytes + offRes;
    //NSLog(@"%@", biffs);
    for (uint32_t i = 0; i < nRes; i++)
    {
      bzero(buff, 12);
      memcpy(buff, p, 8);
      p += 8;
      uint16_t type = EndianU16_LtoN(*(uint16_t*)p);
      p += 2;
      uint32_t locator = EndianU32_LtoN(*(uint32_t*)p);
      p += 4;
      uint32_t idxBIF = (locator & 0xFFF00000) >> 20;
      //uint32_t idxTS = (locator & 0x000FC000) >> 13;
      uint32_t idxNonTS = locator & 0x3FFF;
      if (type == 4)
      {
        //NSLog(@"Res '%s' type %d, loc %d (BIFF %d, ts %d nonts %d)", buff,
        // type, locator, idxBIF, idxTS, idxNonTS);
        NSNumber* n = [[NSNumber alloc] initWithInt:idxBIF];
        for (NSString* biff in [biffs allKeys])
        {
          NSNumber* n2 = [[NSNumber alloc] initWithInt:idxNonTS];
          NSString* s2 = [[NSString alloc] initWithCString:buff
                                           encoding:NSUTF8StringEncoding];
          if ([n isEqualToNumber:[biffs objectForKey:biff]])
          {
            //NSLog(@"Doing %@", biff);
            NSMutableDictionary* d = [_biffs objectForKey:biff];
            BOOL rel = NO;
            if (!d)
            {
              d = [[NSMutableDictionary alloc] init];
              [_biffs setObject:d forKey:biff];
              rel = YES;
            }
            //NSLog(@"%@: %@->%@ in 0x%X", biff, n2, s2, (int)d);
            [d setObject:s2 forKey:n2];
            if (rel) [d release];
          }
          [n2 release];
          [s2 release];
        }
        [n release];
      }
      @synchronized (self)
      {
        _loaded = (double)i/(double)nRes;
      }
    }
    //NSLog(@"%@", _biffs);
    [biffs release];
    [loc release];
    free(buff);
    @synchronized (self)
    {
      _loaded = 1.0;
    }
    [_data release];
    _data = nil;
  }
}

-(NSString*)resourceNameForPath:(NSString*)path index:(uint32_t)idx
{
  NSString* s = nil;
  NSString* lc = [path lowercaseString];
  NSDictionary* d = [_biffs objectForKey:lc];
  if (d) s = [d objectForKey:[NSNumber numberWithInt:idx]];
  return s;
}

-(NSString*)pathForLocalizedFileName:(NSString*)name extension:(NSString*)ext
{
  NSString* ret = nil;
  if (_noLoc) return nil;
  if (!_locDir) [self findLocalizedDirectory];
  if (!_locDir) return nil;
  NSFileManager* fm = [[NSFileManager alloc] init];
  BOOL dir;
  if ([fm fileExistsAtPath:_locDir isDirectory:&dir] && dir)
  {
    NSDirectoryEnumerator* enu = [fm enumeratorAtPath:_locDir];
    for (NSString* file in enu)
    {
      //NSLog(@"pathToLocalizedTLKInDirecory looking for (%@,%@) at %@", name, ext, file);
      NSString* bareFile = [[file lastPathComponent]
                            stringByDeletingPathExtension];
      if ((!ext || NSOrderedSame == [[file pathExtension] compare:ext
                                     options:NSCaseInsensitiveSearch]) &&
          (!name || NSOrderedSame == [bareFile compare:name
                                      options:NSCaseInsensitiveSearch]))
      {
        ret = [_locDir stringByAppendingPathComponent:file];
        //NSLog(@"pathForLocalizedFileName: GOT IT! %@", file);
        break;
      }
    }
  }
  [fm release];
  return ret;
}

-(void)findLocalizedDirectory
{
  NSFileManager* fm = [[NSFileManager alloc] init];
  BOOL dir;
  NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];
  NSArray* langs = [defs objectForKey:@"AppleLanguages"];
  NSString* enclosing = [_path stringByDeletingLastPathComponent];
  NSString* langdir = [enclosing stringByAppendingPathComponent:@"lang"];
  if ([fm fileExistsAtPath:langdir isDirectory:&dir] && dir)
  {
    for (NSString* lang in langs)
    {
      NSArray* a1 = [lang componentsSeparatedByString:@"-"];
      //NSLog(@"findLocalizedDirectory: trying language '%@' (%@)", lang, a1);
      NSDirectoryEnumerator* enu = [fm enumeratorAtPath:langdir];
      for (NSString* lang2 in enu)
      {
        NSString* langdir2 = [langdir stringByAppendingPathComponent:lang2];
        //NSLog(@"findLocalizedDirectory: looking into %@", langdir2);
        if ([fm fileExistsAtPath:langdir2 isDirectory:&dir] && dir)
        {
          //NSLog(@"It exists!");
          NSArray* a2 = [lang2 componentsSeparatedByString:@"_"];
          //NSLog(@"Comparing %@ and %@", [a2 objectAtIndex:0], [a1 objectAtIndex:0]);
          if (NSOrderedSame == [[a1 objectAtIndex:0] compare:[a2 objectAtIndex:0]
                                 options:NSCaseInsensitiveSearch])
          {
            _locDir = [[NSString alloc] initWithString:langdir2];
            //NSLog(@"locDir is %@", _locDir);
          }
        }
        if (_locDir) break;
      }
      if (_locDir) break;
    }
  }
  if (!_locDir) _noLoc = YES;
  [fm release];
}
@end

