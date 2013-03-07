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
#import "ACMData.h"
#include <stdio.h>

static size_t read_func(void *ptr, size_t size, size_t n, void *datasrc);
static int seek_func(void *datasrc, int64_t offset, int whence);
static int close_func(void *datasrc);
static int get_length_func(void *datasrc);
static long tell_func(void* datasrc);

@interface ACMData (Private)
-(void)_coreInit;
@end

@interface ACMVorbisData : ACMData
{}
@end


@implementation ACMData
@synthesize PCMTotal = _pcmTotal;
@synthesize timeTotal = _timeTotal;
@synthesize channels = _channels;
@synthesize rate = _rate;
@synthesize data = _data;
@synthesize dataOffset = _dataOffset;
-(id)initWithPath:(NSString*)path
{
  self = [super init];
  int err = acm_open_file(&_acm.acm, [path UTF8String], 0);
  if (!err)
  {
    [self _coreInit];
  }
  else
  {
    [self dealloc];
    self = [[ACMVorbisData alloc] initWithPath:path];
    if (!self)
    {
      NSLog(@"WARNING: can't find acm file named %@; %s", path, acm_strerror(err));
    }
  }
  // FIXME: this happens for BGII last entry in BM2.mus
  // Could try to repair???
  return self;
}

-(id)initWithData:(NSData*)data
{
  self = [super init];
  _data = [data copy];
  acm_io_callbacks io = {read_func, seek_func, close_func, get_length_func};
  int err = acm_open_decoder(&_acm.acm, self, io, 0);
  if (!err)
  {
    [self _coreInit];
  }
  else
  {
    [self dealloc];
    self = [[ACMVorbisData alloc] initWithData:data];
    if (!self)
    {
      NSLog(@"WARNING: can't open acm data; %s", acm_strerror(err));
    }
  }
  return self;
}

-(void)_coreInit
{
  _rate = acm_rate(_acm.acm);
  _channels = acm_channels(_acm.acm);
  _pcmTotal = acm_pcm_total(_acm.acm);
  _timeTotal = acm_time_total(_acm.acm)/ 1000.0;
  acm_seek_pcm(_acm.acm, _pcmTotal-4);
  acm_seek_pcm(_acm.acm, 0);
}

-(void)dealloc
{
  if (_acm.acm) acm_close(_acm.acm);
  if (_data) [_data release];
  [super dealloc];
}

-(uint64_t)PCMTell
{
  return acm_pcm_tell(_acm.acm);
}

-(void)PCMSeek:(uint64_t)off
{
  acm_seek_pcm(_acm.acm, off);
}

-(long)bufferSamples:(char*)buffer count:(unsigned)bytes bigEndian:(BOOL)big
{
  long n = 0;
  do
  {
    long res = acm_read_loop(_acm.acm, buffer + n, bytes - n, big, 2, 1);
    if (0 == res) break;
    n += res;
  } while (n < bytes);
  return n;
}
@end

// FIXME: turn this into a class cluster.
@implementation ACMVorbisData
-(id)initWithPath:(NSString*)path
{
  FILE* f = fopen([path UTF8String], "r");
  OggVorbis_File* vf = malloc(sizeof(OggVorbis_File));
  int err = ov_open_callbacks(f, vf, NULL, 0, OV_CALLBACKS_DEFAULT);
  if (err < 0)
  {
    NSLog(@"Input does not appear to be an Ogg bitstream (err %d).", err);
    [self release];
    self = nil;
  }
  else
  {
    _acm.ogg = vf;
    [self _coreInit];
  }
  return self;
}

-(id)initWithData:(NSData*)data
{
  self = [super init];
  _data = [data copy];
  ov_callbacks io = {read_func, seek_func, close_func, tell_func};
  OggVorbis_File* vf = malloc(sizeof(OggVorbis_File));
  int err = ov_open_callbacks(self, vf, NULL, 0, io);
  if (err < 0)
  {
    NSLog(@"Input does not appear to be an Ogg bitstream (err %d).", err);
    [self release];
    self = nil;
  }
  else
  {
    _acm.ogg = vf;
    [self _coreInit];
  }
  return self;
}

-(void)_coreInit
{
  OggVorbis_File* vf = _acm.ogg;
  vorbis_info* vi = ov_info(vf, 0);
  //NSLog(@"Bitstream is %d channel, %ldHz",vi->channels,vi->rate);
  //NSLog(@"Decoded length: %ld samples",
  //        (long)ov_pcm_total(vf,-1));
  //fprintf(stderr,"Encoded by: %s\n\n",ov_comment(vf,-1)->vendor);
  //fprintf(stderr,"Seekable? %s\n", ov_seekable(vf)? "yes":"no");
  //fprintf(stderr,"Raw total? %lu\n", ov_raw_total(vf, 0));
  //fprintf(stderr,"PCM total? %lu\n", ov_pcm_total(vf, 0));
  //fprintf(stderr,"Time total? %f\n", ov_time_total(vf, 0));
  _rate = vi->rate;
  _channels = vi->channels;
  _pcmTotal = ov_pcm_total(vf, 0);
  _timeTotal = ov_time_total(vf, 0);
  ov_pcm_seek(vf, _pcmTotal-4);
  ov_pcm_seek(vf, 0);
}

-(void)dealloc
{
  ov_clear(_acm.ogg);
  free(_acm.ogg);
  bzero(&_acm.ogg, sizeof(void*));
  [super dealloc];
}

-(uint64_t)PCMTell
{
  return ov_pcm_tell(_acm.ogg);
}

-(void)PCMSeek:(uint64_t)off
{
  ov_pcm_seek(_acm.ogg, off);
}

-(long)bufferSamples:(char*)buffer count:(unsigned)bytes bigEndian:(BOOL)big
{
  int current_section;
  long n = 0;
  do
  {
    long res = ov_read(_acm.ogg, buffer + n, bytes - n, big, 2, 1,
                       &current_section);
    if (0 == res || OV_HOLE == res ||
        OV_EBADLINK == res || OV_EINVAL == res)
      break;
    n += res;
  } while (n < bytes);
  return n;
  
}
@end

#pragma mark Callbacks for libacm/vorbis
static size_t read_func(void* ptr, size_t size, size_t n, void* datasrc)
{
  ACMData* myself = datasrc;
  size_t bytes = n * size;
  size_t avail = [myself.data length] - myself.dataOffset;
  if (avail < bytes) bytes = avail;
  [myself.data getBytes:ptr range:NSMakeRange(myself.dataOffset, bytes)];
  myself.dataOffset += bytes;
  return bytes;
}

static int seek_func(void* datasrc, int64_t offset, int whence)
{
  ACMData* myself = datasrc;
  if (whence == SEEK_SET) myself.dataOffset = offset;
  else if (whence == SEEK_CUR) myself.dataOffset += offset;
  else if (whence == SEEK_END) myself.dataOffset = [myself.data length] + offset;
  return 0;
}

static int close_func(void* datasrc)
{
  #pragma unused (datasrc)
  return 0;
}

static int get_length_func(void* datasrc)
{
  ACMData* myself = datasrc;
  return [myself.data length];
}

static long tell_func(void* datasrc)
{
  ACMData* myself = datasrc;
  return myself.dataOffset;
}
