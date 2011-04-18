/*
 * Copyright © 2010-2011, Brian "Moses" Hall
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
#import "ACMProgressSlider.h"

static void _drawKnobInRect(NSRect knobRect);
static void _drawFrameInRect(NSRect frameRect);

@implementation ACMProgressSlider
+(Class)cellClass {return [ACMProgressSliderCell class];}
-(BOOL)acceptsFirstMouse:(NSEvent*)evt
{
  #pragma unused (evt)
  return YES;
}

-(double)trackingValue
{
  return [[self cell] trackingValue];
}

-(void)setShowsProgress:(BOOL)flag
{
  [[self cell] setShowsProgress:flag];
}

-(void)setProgressValue:(double)aDouble
{
  [[self cell] setProgressValue:aDouble];
}

-(void)setLoopPosition:(double)aDouble
{
  [[self cell] setLoopPosition:aDouble];
}
@end


NSColor*_myFillColor = nil;
NSColor*_myBorderColor = nil;

@interface ACMProgressSliderCell (Private)
-(void)setTrackingValue:(double)aDouble;
@end

@implementation ACMProgressSliderCell
-(void)_setup
{
  // set up all the default values...
  [self setDoubleValue:0.0];
  _trackingValue = 0.0;
  _tracking = NO;
  _progressing = NO;
  [self setShowsFirstResponder:YES];
  // these are noted as private in the docs, but this is the only way to configure them.
  _cFlags.actOnMouseDragged = NO;
  _cFlags.actOnMouseDown = NO;
  _cFlags.dontActOnMouseUp = YES;
  _cFlags.refusesFirstResponder = NO;
  [self setContinuous:NO];
}

-(id)init
{
  self = [super init];
  if (self) [self _setup];
  return self;
}

-(id)initTextCell:(NSString*)aString
{
  self = [super initTextCell:aString];
  if (self)
  {
    [self _setup];
    [self setStringValue:aString];
  }
  return self;
}

-(id)initImageCell:(NSImage*)image
{
  self = [super initImageCell:image];
  if (self) [self _setup];
  return self;
}

static void _drawKnobInRect(NSRect r)
{
  // Center knob in given rect
  r.origin.x += (int)((float)(r.size.width - 7)/2.0);
  r.origin.y += (int)((float)(r.size.height - 7)/2.0);
  // Draw diamond
  NSRectFillUsingOperation(NSMakeRect(r.origin.x + 3.0f, r.origin.y + 6.0f, 1.0f, 1.0f), NSCompositeSourceOver);
  NSRectFillUsingOperation(NSMakeRect(r.origin.x + 2.0, r.origin.y + 5.0f, 3.0, 1.0), NSCompositeSourceOver);
  NSRectFillUsingOperation(NSMakeRect(r.origin.x + 1, r.origin.y + 4, 5.0, 1.0), NSCompositeSourceOver);
  NSRectFillUsingOperation(NSMakeRect(r.origin.x + 0, r.origin.y + 3, 7.0, 1.0), NSCompositeSourceOver);
  NSRectFillUsingOperation(NSMakeRect(r.origin.x + 1, r.origin.y + 2, 5.0, 1.0), NSCompositeSourceOver);
  NSRectFillUsingOperation(NSMakeRect(r.origin.x + 2, r.origin.y + 1, 3.0, 1.0), NSCompositeSourceOver);
  NSRectFillUsingOperation(NSMakeRect(r.origin.x + 3, r.origin.y + 0, 1.0, 1.0), NSCompositeSourceOver);
}

static void _drawFrameInRect(NSRect r)
{
  NSRectFillUsingOperation(NSMakeRect(r.origin.x, r.origin.y, r.size.width, 1), NSCompositeSourceOver);
  NSRectFillUsingOperation(NSMakeRect(r.origin.x, r.origin.y + r.size.height-1, r.size.width, 1), NSCompositeSourceOver);
  NSRectFillUsingOperation(NSMakeRect(r.origin.x, r.origin.y, 1, r.size.height), NSCompositeSourceOver);
  NSRectFillUsingOperation(NSMakeRect(r.origin.x + r.size.width-1, r.origin.y, 1, r.size.height), NSCompositeSourceOver);
}

-(void)drawInteriorWithFrame:(NSRect)rect inView:(NSView*)controlView
{
  rect = [controlView bounds];
  NSRect knobRect = rect;
  rect.size.height = 9;
  //[[[NSColor blackColor] colorWithAlphaComponent:0.6] set];
  [[NSColor blackColor] set];
  _drawFrameInRect(rect);
  if (_progressing)
  {
    rect.size.width *= _progressValue;
    NSBezierPath* path = [NSBezierPath bezierPathWithRect:rect];
    [path fill];
  }
  else
  {
    knobRect.size.width = knobRect.size.height;
    knobRect.origin.x += (rect.size.width - knobRect.size.width) * ((_tracking) ? _trackingValue : _value);
    _drawKnobInRect(knobRect);
    // Indicate loop point
    if (_loopPosition != 0.0)
    {
      NSRect loopRect = rect;
      loopRect.size.width *= _loopPosition;
      [[[NSColor blackColor] colorWithAlphaComponent:0.1f] set];
      NSRectFillUsingOperation(loopRect, NSCompositeSourceOver);
    }
  }
  // Draw shadow
  [[[NSColor blackColor] colorWithAlphaComponent:0.1f] set];
  rect.origin.x++;
  rect.origin.y++;
  knobRect.origin.x++;
  knobRect.origin.y++;
  _drawFrameInRect(rect);
  _drawKnobInRect(knobRect);
}

-(BOOL)startTrackingAt:(NSPoint)startPoint inView:(NSView*)controlView
{
  BOOL ret = NO;
  if (!_progressing)
  {
    ret = YES;
    /*if (!_tracking)
    {
      NSView* cv = [self controlView];
      [[cv window] makeFirstResponder:cv];
    }*/
    NSRect r = [controlView bounds];
    double val = (startPoint.x - r.origin.x)/r.size.width;
    _tracking = YES;
    [self setTrackingValue:val];
    //NSLog(@"startTrackingAt: setTrackingValue %f", _trackingValue);
  }
  return ret;
}

-(BOOL)continueTracking:(NSPoint)lastPoint at:(NSPoint)currentPoint
       inView:(NSView*)controlView
{
  #pragma unused (lastPoint)
  BOOL ret = NO;
  if (!_progressing)
  {
    ret = YES;
    NSRect r = [controlView bounds];
    double val = (currentPoint.x - r.origin.x)/r.size.width;
    [self setTrackingValue:val];
    //NSLog(@"continueTracking: setTrackingValue %f", _trackingValue);
  }
  return ret;
}

-(void)stopTracking:(NSPoint)lastPoint at:(NSPoint)stopPoint
       inView:(NSView*)controlView mouseIsUp:(BOOL)flag
{
  #pragma unused (lastPoint)
  _tracking = NO;
  if (!_progressing)
  {
    NSRect r = [controlView bounds];
    double val = (stopPoint.x - r.origin.x)/r.size.width;
    [self setTrackingValue:val];
    if (flag)
    {
      [self setDoubleValue:val];
      //NSLog(@"stopTracking: setDoubleValue %f", val);
      SEL action = [self action];
      id target = [self target];
      if (action && target)
      {
        IMP imp = [target methodForSelector:action];
        (imp)(target, action);
      }
    }
  }
}

-(double)trackingValue {return _trackingValue;}
-(double)doubleValue {return _value;}

-(void)setDoubleValue:(double)aDouble
{
  _value = aDouble;
  if (!_tracking) [[self controlView] setNeedsDisplay:YES];
}

-(void)setTrackingValue:(double)aDouble
{
  _trackingValue = aDouble;
  if (_tracking) [[self controlView] setNeedsDisplay:YES];
}

-(void)setShowsProgress:(BOOL)flag
{
  if (_progressing != flag)
  {
    _progressing = flag;
    [[self controlView] setNeedsDisplay:YES];
  }
}

-(void)setProgressValue:(double)aDouble
{
  if (_progressValue != aDouble)
  {
    _progressValue = aDouble;
    if (_progressing) [[self controlView] setNeedsDisplay:YES];
    else NSLog(@"But I'm not progressive!");
  }
}

-(void)setLoopPosition:(double)aDouble
{
  if (_loopPosition != aDouble)
  {
    _loopPosition = aDouble;
    [[self controlView] setNeedsDisplay:YES];
  }
}
@end

@implementation OldYaller
-(void)drawRect:(NSRect)rect
{
  rect = NSInsetRect([self bounds], 1.0f, 1.0f);
  [[NSColor colorWithCalibratedRed:0.94f green:0.98f blue:0.79f alpha:1.0f] set];
  NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:4.0f yRadius:4.0f];
  [path fill];
  [[NSColor colorWithCalibratedRed:0.2f green:0.2f blue:0.2f alpha:1.0f] set];
  [path stroke];
}
@end
