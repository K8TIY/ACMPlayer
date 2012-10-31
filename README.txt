ACMPlayer is a player for Baldur's Gate .acm music files and
.mus playlist files.

This version (1.2) adds support for navigating into .app packages in
anticipation of Baldur's Gate Extended Edition due in November 2012.
We don't know exactly how it will be packaged, but I suspect the music files
will be embedded inside.

In theory it should work for all games that use the Interplay formats.
Originally I ported ABel's C++ code (from acm2wav.exe) to Objective-C.
This version uses Marko Kreen's libacm, which is here as a git submodule.

ACMPlayer can also export .acm and .mus files to AIFF.
Universal binary, tested on 10.5 and 10.6 Intel 32/64.

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
