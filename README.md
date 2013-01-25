## This is ACMPlayer 1.3

ACMPlayer is a player for Baldur's Gate .acm and .wav music/sound files and
.mus playlist files.

_Note: do not try to play "real" .wav files. Baldur's Gate .wavs are a different
beast and will likely not work._

Version 1.3 adds support for .wav (actually compressed wav; really actually
just acm with an extra header) files used
for character soundsets. I say "adds support" but in fact the support
has always been in libacm, I just didn't realize it. So all I had to do was
add one entry to the application plist and a half a line of code, and,
as they say, *viola*.

In theory it should work for all games that use the Interplay formats.
Originally I ported ABel's C++ code (from acm2wav.exe) to Objective-C.
This version uses Marko Kreen's libacm, which is here as a git submodule.

ACMPlayer can also export .acm, .wav, and .mus files to AIFF.

Originally I had hoped to produce a QuickTime plugin, but I did not know how
to reconcile the slight nonlinearity of .mus playlists (i.e. "epilogues",
or different endings depending on how far into the playlist you are) with
QuickTime. So this application lets you play an epilogue at the next available
stopping point. AIFF exports always choose the final epilogue
(longest resulting file).

libacm has reportedly been tested against many, many games, so it is likely
to work well. My Python .mus parser... not so much, so please report anything
that it can't handle. It probably does not deal real elegantly with
case-sensitive filesystems.
