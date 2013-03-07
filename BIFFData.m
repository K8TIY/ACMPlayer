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
#import "ACMRenderer.h"
#import "BIFFData.h"
#import <zlib.h>

@implementation BIFFFile
@synthesize loc = _loc;
@synthesize off = _off;
@synthesize len = _len;
@synthesize type = _type;

-(id)initWithLocator:(uint32_t)loc offset:(uint32_t)off length:(uint32_t)len type:(uint16_t)type
{
  self = [super init];
  _loc = loc;
  _off = off;
  _len = len;
  _type = type;
  return self;
}
@end

@interface BIFFData (Private)
-(void)setBIFFData:(NSData*)data;
-(void)setBIFData:(NSData*)data;
-(void)setBIFCData:(NSData*)data;
@end

@implementation BIFFData
@synthesize strings = _strings;
@synthesize loaded = _loaded;

-(id)init
{
  self = [super init];
  _loaded = 0.0;
  _strings = [[NSMutableArray alloc] init];
  return self;
}

-(void)dealloc
{
  if (_strings) [_strings release];
  if (_data) [_data release];
  [super dealloc];
}

-(void)setData:(NSData*)data/* path:(NSString*)path*/
{
  _loaded = 0.0;
  if (data)
  {
    char* buff = calloc(1, 12);
    _data = data;
    [data retain];
    _bytes = [data bytes];
    memcpy(buff, _bytes, 4);
    //NSLog(@"Signature: '%s'", buff);
    if (0 == strncmp(buff, "BIFF", 4)) [self setBIFFData:data];
    else if (0 == strncmp(buff, "BIF ", 4)) [self setBIFData:data];
    else if (0 == strncmp(buff, "BIFC", 4)) [self setBIFCData:data];
    free(buff);
  }
  _loaded = 1.0;
}

typedef struct
{
  uint32_t sig;
  uint32_t ver;
  uint32_t nf;
  uint32_t nts;
} BIFFHeader;

-(void)setBIFFData:(NSData*)data
{
  _data = data;
  [data retain];
  _bytes = [data bytes];
  uint32_t nf = EndianU32_LtoN(*(uint32_t*)(_bytes + 0x0008));
  _offset = EndianU32_LtoN(*(uint32_t*)(_bytes + 0x0010));
  const unsigned char* p = _bytes + _offset;
  for (uint32_t i = 0; i < nf; i++)
  {
    BIFFFile* info = nil;
    uint32_t loc = EndianU32_LtoN(*(uint32_t*)p);
    p += 4;
    uint32_t off = EndianU32_LtoN(*(uint32_t*)p);
    p += 4;
    uint32_t len = EndianU32_LtoN(*(uint32_t*)p);
    p += 4;
    uint16_t type = EndianU16_LtoN(*(uint16_t*)p);
    p += 4;
    if (type == 4)
    {
      // Check for a RIFF header
      if (*(_bytes + off) == 'R' &&
          *(_bytes + off + 1) == 'I' &&
          *(_bytes + off + 2) == 'F' &&
          *(_bytes + off + 3) == 'F')
      {
        //NSLog(@"RIFF file detected, skipping");
      }
      else
      {
        info = [[BIFFFile alloc] initWithLocator:loc
                                 offset:off
                                 length:len
                                 type:type];
        @synchronized(self)
        {
          [_strings addObject:info];
          _loaded = (double)i / (double)nf;
        }
        [info release];
      }
    }
  }
}
/*
0x0000	4 (char array)	Signature ('BIF ')
0x0004	4 (char array)	Version ('V1.0')
0x0008	4 (dword)	Length of filename
0x000c	(ASCIIZ char array)	Filename (length specified by previous field)
sizeof(filename)+0x0010	4 (dword)	Uncompressed data length
sizeof(filename)+0x0014	4 (dword)	Compressed data length
sizeof(filename)+0x0018	Variable (raw data)	Compressed data
*/
-(void)setBIFData:(NSData*)data
{
  _bytes = [data bytes];
  uint32_t fnlen = EndianU32_LtoN(*(uint32_t*)(_bytes + 0x0008));
  uint32_t uncmplen = EndianU32_LtoN(*(uint32_t*)(_bytes + fnlen + 0x0010));
  uint32_t cmplen = EndianU32_LtoN(*(uint32_t*)(_bytes + fnlen + 0x0014));
  //NSLog(@"Filename length: %d (%s); uncompressed: %d; compressed: %d", fnlen, _bytes + 0x000C, uncmplen, cmplen);
  unsigned char* decomp = malloc(uncmplen);
  const unsigned char* p = _bytes + fnlen + 0x0014;
  uint32_t bytes = 0; // Amount decompressed
  uLongf zuncmplen = uncmplen;
  if (uncmplen > 0 && cmplen > 0)
  {
    int status = uncompress(decomp, &zuncmplen, p, cmplen);
    if (status != Z_OK)
    {
      NSLog(@"Status: %d", status);
      goto Done;
    }
  }
  //NSLog(@"Bytes read: %d of %d", bytes, sz);
  //hexdump(decomp, bytes);
  NSData* newData = [[NSData alloc] initWithBytes:decomp length:bytes];
  free(decomp);
  decomp = NULL;
  [self setData:newData];
  [newData release];
Done:
  if (decomp) free(decomp);
}

/*Header

Offset	Size (data type)	Description
0x0000	4 (char array)	Signature ('BIFC')
0x0004	4 (char array)	Version ('V1.0')
0x0008	4 (dword)	Uncompressed BIF size
Compressed Blocks

Offset	Size (data type)	Description
0x0000	4 (dword)	Decompressed size
0x0004	4 (dword)	Compressed size
0x0008	varies (bytes)	Compressed data*/
-(void)setBIFCData:(NSData*)data
{
  _bytes = [data bytes];
  uint32_t sz = EndianU32_LtoN(*(uint32_t*)(_bytes + 0x0008));
  //NSLog(@"Size: %d", sz);
  unsigned char* decomp = malloc(sz);
  const unsigned char* p = _bytes + 12;
  uint32_t bytes = 0; // Amount decompressed
  while (bytes < sz)
  {
    // read block header
    uint32_t uncmplen = EndianU32_LtoN(*(uint32_t*)p);
    uLongf zuncmplen = uncmplen;
    p += 4;
    uint32_t cmplen = EndianU32_LtoN(*(uint32_t*)p);
    p += 4;
    //NSLog(@"Compressed: %d, uncompressed: %d", cmplen, uncmplen);
    if (uncmplen > 0 && cmplen > 0)
    {
      int status = uncompress(decomp + bytes, &zuncmplen, p, cmplen);
      if (status != Z_OK)
      {
        NSLog(@"Status: %d", status);
        goto Done;
      }
      p += cmplen;
      bytes += uncmplen;
    }
    //NSLog(@"Bytes read: %d of %d", bytes, sz);
  }
  //hexdump(decomp, bytes);
  NSData* newData = [[NSData alloc] initWithBytes:decomp length:bytes];
  free(decomp);
  decomp = NULL;
  [self setData:newData];
  [newData release];
Done:
  if (decomp) free(decomp);
}

-(NSData*)dataAtIndex:(uint32_t)i
{
  BIFFFile* str = [_strings objectAtIndex:i];
  NSData* val = [[NSData alloc] initWithBytes:_bytes + str.off
                                length:str.len];
  return [val autorelease];
}
@end
