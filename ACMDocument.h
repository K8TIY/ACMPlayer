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
#import <Cocoa/Cocoa.h>
#import "ACMRenderer.h"
#import "ACMProgressSlider.h"

@interface ACMDocument : NSDocument <ACM>
{
  IBOutlet NSWindow* _playerWindow;
  //IBOutlet NSPanel* _exportSheet;
  //IBOutlet NSProgressIndicator* _exportSheetProgress;
  IBOutlet NSButton* _startStopButton;
  IBOutlet NSButton* _loopButton;
  IBOutlet NSSlider* _ampSlider;
  IBOutlet NSButton* _ampLoButton;
  IBOutlet NSButton* _ampHiButton;
  IBOutlet NSButton* _timeButton;
  IBOutlet NSButton* _epilogueStateButton;
  IBOutlet NSButton* _epilogueButton;
  IBOutlet ACMProgressSlider* _progress;
	ACMRenderer* _musicRenderer;
  NSImage* o_img_play;
  NSImage* o_img_pause;
  NSImage* o_img_play_pressed;
  NSImage* o_img_pause_pressed;
  BOOL _showTimeLeft;
  BOOL _closing;
  BOOL _suspendedInBackground; // Playing is suspended because the window was backgrounded.
  BOOL _haveEpilogue; // If reading a playlist w/ epilogue, enable "Epilogue" button
}
-(void)suspend;
-(IBAction)startStop:(id)sender;
-(IBAction)setAmp:(id)sender;
-(IBAction)setAmpLo:(id)sender;
-(IBAction)setAmpHi:(id)sender;
-(IBAction)toggleTimeDisplay:(id)sender;
-(IBAction)setLoop:(id)sender;
-(IBAction)setProgress:(id)sender;
-(IBAction)epilogueAction:(id)sender;
-(IBAction)exportAIFF:(id)sender;
@end

