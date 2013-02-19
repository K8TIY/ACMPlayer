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
#import "ACMDocumentCommon.h"
#import "ACMProgressSlider.h"

@interface ACMWindow : NSWindow
@end

@interface ACMDocumentController : NSDocumentController
@end

@interface ACMDocument : ACMDocumentCommon <ACM>
{
  IBOutlet ACMWindow* _playerWindow;
  //IBOutlet NSPanel* _exportSheet;
  //IBOutlet NSProgressIndicator* _exportSheetProgress;
  IBOutlet NSButton* _ampLoButton;
  IBOutlet NSButton* _ampHiButton;
  IBOutlet NSButton* _timeButton;
  IBOutlet NSButton* _epilogueStateButton;
  IBOutlet NSButton* _epilogueButton;
  IBOutlet ACMProgressSlider* _progress;
  BOOL _showTimeLeft;
  BOOL _closing;
  BOOL _suspendedInBackground; // Playing is suspended because the window was backgrounded.
  BOOL _haveEpilogue; // If reading a playlist w/ epilogue, enable "Epilogue" button
}
-(void)suspend;
-(IBAction)setAmpLo:(id)sender;
-(IBAction)setAmpHi:(id)sender;
-(IBAction)toggleTimeDisplay:(id)sender;
-(IBAction)setProgress:(id)sender;
-(IBAction)epilogueAction:(id)sender;
-(IBAction)exportAIFF:(id)sender;
-(void)windowDidReceiveSpace:(id)sender;
@end

