#!/usr/bin/env python
# Returns a dictionary-type property list.
# Keys:
#   'loop' = An integer loop index (0-based)
#   'files' = An array of file paths
#   'epilogues' = An array of epilogue file paths (empty string for no epilogue)
#                 and empty list if no epilogues at all
import os,sys,re

files = list()
epilogues = list()
loop = None # The name of the file to loop to
# Read the path to the .mus file from stdin
path = ""
while True:
  tmp = sys.stdin.read()
  if not tmp: break
  path += tmp
# FIXME: convert path from utf-8 to native string
#print >>sys.stderr, "From STDIN: path to MUS file is %s" % path
f = open(path,'r')
data = f.read().strip()
f.close()
data = re.split(r'[\r\n]+',data)
#print >>sys.stderr, "File data:\n%s" % data
prefix = data.pop(0) # The subdir e.g., music/BD1
dir = os.path.join(os.path.split(path)[0],prefix)
#print >>sys.stderr, "Reading from music directory %s" % dir
entries = data.pop(0) # Number of entries
for line in data:
  line = re.sub(r'#.*','',line)
  if not len(line): continue
  comps = re.split(r'\s+',line)
  #print >>sys.stderr, "LINE %s" % comps
  # First component is acm file name
  acm = comps.pop(0)
  # Ignore silent files; FIXME: what are the silence files for all games?
  if acm.lower().startswith('spc'): continue
  files.append(os.path.join(dir,prefix+acm+".acm"))
  while len(comps) > 0:
    # Next components may be [@TAG,epilogue] or loop, or in some cases [prefix,loop]
    # This seems to happen only after SPC1 line, as if to remind the MUS reader to go back to
    # the correct subdirectory (since SPC1 is up a level).
    tag = comps.pop(0)
    if tag.lower() == prefix.lower(): pass
    elif tag.upper() == "@TAG":
      tag = comps.pop(0)
      if tag.upper() != "END":
        epilogues.append(os.path.join(dir,prefix+tag+".acm"))
    else:
      loop = os.path.join(dir,prefix+tag+".acm")
  if len(epilogues) < len(files): epilogues.append("")
#printf("{\n  loop=%d;\n  files=(%s);\n  epilogues=(%s);\n}", $loopIndex, join(",\n", @files), join(",\n", @tags));
loopidx = 0
if loop is not None:
  for i in xrange(len(files)):
    if files[i].lower() == loop.lower():
      loopidx = i + 1
      break
haveEpilogue = False
for e in epilogues:
  if len(e) > 0:
    haveEpilogue = True
    break
if not haveEpilogue: epilogues = list()
out = """{
  loop=%d;
  files=(%s);
  epilogues=(%s);
}""" % (loopidx,',\n'.join(['"%s"' % f for f in files]),',\n'.join(['"%s"' % f for f in epilogues]))
print out
