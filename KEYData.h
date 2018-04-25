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
#import <Cocoa/Cocoa.h>

// Make it easy to look up the resource name, given
// The file path and the resource index.
typedef struct
{
  uint32_t biff;  // Index of item in _biffs
  uint32_t idx;
} KeyResourceInfo;

@interface KEYData : NSObject
{
  NSData*              _data;
  NSString*            _path;  // Path to this file
  NSString*            _locDir; // (BG:EE) localized directory
  NSMutableDictionary* _biffs; // File path -> NSDictionary of NSNumber -> Resname
  double               _loaded; // Ratio loaded (0.0 to 1.0)
  BOOL                 _noLoc;
}
+(KEYData*)KEYDataForFile:(NSString*)path loading:(BOOL)load;
-(id)initWithPath:(NSString*)path loading:(BOOL)load;
-(void)setData;
-(NSString*)resourceNameForPath:(NSString*)path index:(uint32_t)idx;
-(NSString*)pathForLocalizedFileName:(NSString*)name extension:(NSString*)ext;
@property (readonly) double loaded;
@end
