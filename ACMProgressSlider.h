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

@interface ACMProgressSliderCell : NSActionCell
{
  double _value; // A value between 0.0 and 1.0 inclusive.
  double _trackingValue;
  double _loopPct;
  double _epilogueStartPct;
  double _epilogueEndPct;
  BOOL   _tracking;
}
-(double)trackingValue;
@end

@interface ACMProgressSlider : NSControl{}
-(double)trackingValue;
-(void)setLoopPct:(double)pct;
-(void)setEpilogueStartPct:(double)start endPct:(double)end;
@end

@interface OldYaller : NSView
{
  NSColor* _color;
}
-(void)setColor:(NSColor*)color;
@end
