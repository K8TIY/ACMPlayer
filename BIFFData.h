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
#import <Cocoa/Cocoa.h>

@interface BIFFFile : NSObject
{
  uint32_t  _loc;
  uint32_t  _off; // From _bytes
  uint32_t  _len;
  uint16_t  _type;
}
@property (readonly) uint32_t loc;
@property (readonly) uint32_t off;
@property (readonly) uint32_t len;
@property (readonly) uint16_t type;

-(id)initWithLocator:(uint32_t)loc offset:(uint32_t)off length:(uint32_t)len
     type:(uint16_t)type;
@end

@interface BIFFData : NSObject
{
  NSMutableArray*      _strings;
  uint32_t             _offset;  // To string data
  NSData*              _data;    // Release when done
  const unsigned char* _bytes;   // [_data bytes]
  double               _loaded;  // Ratio loaded (0.0 to 1.0)
}
-(void)setData:(NSData*)data/* path:(NSString*)path*/;
-(NSData*)dataAtIndex:(uint32_t)i;
@property (readonly) NSArray* strings;
@property (readonly) double loaded;
@end
