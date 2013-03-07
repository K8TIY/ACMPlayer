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
#import "AppController.h"
#import "Onizuka.h"

@implementation AppController
-(void)awakeFromNib
{
  NSString* where = [[NSBundle mainBundle] pathForResource:@"defaults" ofType:@"plist"];
  NSMutableDictionary* d = [NSMutableDictionary dictionaryWithContentsOfFile:where];
  [[NSUserDefaults standardUserDefaults] registerDefaults:d];
  Onizuka* oz = [Onizuka sharedOnizuka];
  [oz localizeMenu:[NSApp mainMenu]];
  [oz localizeWindow:_prefsWindow];
}

-(BOOL)applicationShouldOpenUntitledFile:(NSApplication*)sender
{
  #pragma unused (sender)
  return NO;
}

-(IBAction)orderFrontPrefsWindow:(id)sender
{
  #pragma unused (sender)
  [_prefsWindow makeKeyAndOrderFront:sender];
}
@end
