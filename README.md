## This is ACMPlayer 2.0

ACMPlayer is a player for Baldur's Gate (original or Enhanced Edition)
.acm and .wav music/sound files and .mus playlist files. As of this version
it can open BIFF files (.bif) and find the sounds embedded therein.

###Download a binary for OS X 10.5 and later [here](http://blugs.com/Downloads/ACMPlayer.zip).

### Build Instructions ###
```
git clone https://github.com/markokr/libacm.git
git clone https://github.com/xiph/ogg.git
git clone https://github.com/xiph/vorbis.git
git clone https://github.com/K8TIY/Onizuka.git
```

Build the ogg and vorbis static libraries by futzing with
the XCode project until they compile.

### New in this Version ###
* This is the Baldur's Gate: Enhanced Edition version.
  That means Ogg Vorbis support... and boy howdy does that music sound good!
* Can open .wav (actually compressed wav; really actually
  just acm with an extra header) files used
  for character soundsets. libacm has supported this forever but
  I didn't realize it.
  _Note: do not try to play "real" .wav files. Baldur's Gate .wavs are
  a different beast and playing "real" .wavs with ACMPlayer will likely
  not work._
* Can open BIFF files and find all the sound goodies embedded within.
* Can parse .tlk and .key files and attempt to display the associated
  resource ID and the dialogue string associated with it.

In theory it should work for all games that use the Interplay formats.
Originally I ported ABel's C++ code (from acm2wav.exe) to Objective-C.
This version uses Marko Kreen's libacm, which is here as a git submodule.

ACMPlayer can also export .acm, .wav, and .mus files to AIFF.

Originally I had hoped to produce a QuickTime plugin, but I did not know how
to reconcile the nonlinearity of .mus playlists (i.e. "epilogues",
or different endings depending on how far into the playlist you are) with
QuickTime. So this application lets you play an epilogue at the next available
stopping point. AIFF exports always choose the final epilogue
(longest resulting file).

libacm has reportedly been tested against many, many games, so it is likely
to work well. My Python .mus parser... not so much, so please report anything
that it can't handle. It probably does not deal real elegantly with
case-sensitive filesystems.

### Known Bugs ###
* Error reporting is pretty lousy at this point.
* I doubt we play particularly well with case-sensitive filesystems.
* The play/pause and loop controls use bitmaps and are thus not
  resolution-independent.
* There are still problems with indicating the epilogue shading in the right
  place, particularly when playing one in the middle of the playlist.
* There may still be threading issues when opening a BIFF file; it parses the
  .tlk and .key files in a background thread to keep from beachballing.
  Because .key and .tlk files are globally owned, strange things may happen if
  you open a second BIFF while the first is still loading.
* Because multiple .tlk entries may reference the same sound, only the first
  one encountered in the .tlk file will be displayed.
* Similarly, some sound effects and dialogues appear to share resource ids
  and since ACMPlayer is trying to do a reverse mapping, some sound effects
  can show up with erroneous dialogue strings or descriptions.

### Building ###
You will need to tweak the build settings in the Ogg and Vorbis submodules.
For starters, unless you have the 10.4u SDK, you need to point at 10.5 or later.
Although ACMPlayer is built with LLVM, I found that the frameworks had to be
built with GCC 4.2 in order for 32-bit Ogg Vorbis to produce anything
other than a nasty buzzing sound. YMMV -- I am building on Snow Leopard with
XCode 3.2.6.

