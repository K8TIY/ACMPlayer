/*
 * Copyright © 2010, Brian "Moses" Hall
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
#import "ACMRenderer.h"
#import <AudioToolbox/AudioToolbox.h>

@interface ACMRenderer (Private)
-(ACMStream*)_acmAtIndex:(NSUInteger)i;
-(OSStatus)_createAU:(double)rate;
-(int16_t*)_bufferSamples:(UInt32)count;
-(ACMStream*)_advACM;
-(ACMStream*)_epilogueAtPosition:(NSUInteger)pos;
-(void)_progress;
@end


static OSStatus	RenderCB(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, 
                         const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, 
                         UInt32 inNumberFrames, AudioBufferList* ioData);
#if 0
static void hexdump(void *data, int size);
#endif

static OSStatus RenderCB(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, 
                         const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, 
                         UInt32 inNumberFrames, AudioBufferList* ioData)
{
  #pragma unused (ioActionFlags,inTimeStamp,inBusNumber)
  ACMRenderer* myself = inRefCon;
  NSUInteger i;
  short* acmBufferRead = NULL;
  float* lBuffer = ioData->mBuffers[0].mData;
  float* rBuffer = ioData->mBuffers[1].mData;
  short* acmBuffer = [myself _bufferSamples:inNumberFrames * 2];
  if (acmBuffer) acmBufferRead = acmBuffer;
  for (i = 0; i < inNumberFrames; i++)
  {
    float waveL = 0.0f, waveR = 0.0f;
    if (acmBuffer)
    {
      int16_t lSample = *acmBufferRead;
      acmBufferRead++;
      int16_t rSample = *acmBufferRead;
      acmBufferRead++;
      // Scale short int values to {-1,1}
      waveL = (float)lSample/35526.0f;
      if (rSample != lSample) waveR = (float)rSample/35526.0f;
      else waveR = waveL;
      // Only multiply by amp if we have to.
      float amp = [myself amp];
      if (amp != 1.0)
      {
        waveL *= amp;
        waveR *= amp;
      }
    }
    *lBuffer++ = waveL;
    *rBuffer++ = waveR;
  }
  [myself _progress];
  if (acmBuffer) free(acmBuffer);
  return noErr;
}

@implementation ACMRenderer
-(ACMRenderer*)initWithPlaylist:(NSArray*)list andEpilogues:(NSArray*)epilogues
{
  self = [super init];
  _amp = 0.5f;
  _totalSeconds = 0.0;
  _loop = NO;
  double rate = 0.0;
  _acms = [[NSMutableArray alloc] init];
  ACMStream* acm;
  for (NSString* file in list)
  {
    int err = acm_open_file(&acm, [file UTF8String], 0);
    if (!err)
    {
      rate = acm_rate(acm);
      unsigned int tpcm = acm_pcm_total(acm);
      [_acms addObject:[NSValue valueWithPointer:acm]];
      _totalPCM += tpcm;
      _totalSeconds += tpcm/rate/2.0;
    }
    // FIXME: this happens for BGII last entry in BM2.mus
    // Could try to repair???
    else NSLog(@"WARNING: can't find acm file named %@; sound will be truncated", file);
	}
  if (epilogues && [epilogues count])
  {
    _epilogueNames = [[NSMutableArray alloc] init];
    _epilogues = [[NSMutableDictionary alloc] init];
    for (NSString* file in epilogues)
    {
      acm = nil;
      file = [file stringByExpandingTildeInPath];
      //NSLog(@"ep: %@", file);
      [_epilogueNames addObject:file];
      // If the file name is already in the dict, then the ACM is already loaded so we go on to the next.
      // But if it's NULL, then we can try again.
      id obj = [_epilogues objectForKey:file];
      if (obj)
      {
        if (![obj isKindOfClass:[NSNull class]]) continue;
        //NSLog(@"trying to fix NSNull for %@", file);
      }
      int err = acm_open_file(&acm, [file UTF8String], 0);
      obj = nil;
      if (err)
      {
        NSLog(@"WARNING: can't find epilogue named %@; using NSNull", file);
        obj = [NSNull null];
      }
      else
      {
        obj = [NSValue valueWithPointer:acm];
      }
      [_epilogues setObject:obj forKey:file];
    }
  }
  OSErr err = [self _createAU:rate];
  //NSLog(@"Total time: %f sec", _totalSeconds);
  return self;
}

-(void)dealloc
{
  CloseComponent(_au);
  for (NSValue* val in _acms) acm_close([val pointerValue]);
  [_acms release];
  if (_epilogueNames) [_epilogueNames release];
  if (_epilogues) [_epilogues release];
  [super dealloc];
}

-(void)setDelegate:(id)del {_delegate = del;}
-(void)setDoesLoop:(BOOL)loop {_loop = loop;}
-(BOOL)doesLoop {return _loop;}
-(NSUInteger)loopPoint {return _loopPoint;}
-(void)setLoopPoint:(NSUInteger)lp {if (lp < [_acms count]) _loopPoint = lp;}

-(void)start
{
  if (!_nowPlaying)
  {
    OSStatus err = AudioOutputUnitStart(_au);
    if (!err) _nowPlaying = YES;
  }
}

-(void)stop
{
  if (_nowPlaying)
  {
    OSStatus err = AudioOutputUnitStop(_au);
    if (err) NSLog(@"ERROR %ld from AudioOutputUnitStop", err);
    else _nowPlaying = NO;
  }
}

-(void)suspend {_suspended = YES;}
-(void)resume {_suspended = NO;}
-(BOOL)isSuspended {return _suspended;}

-(double)position
{
  double tsp = (double)_totalPCMPlayed;
  double ts = (double)_totalPCM;
  double p = tsp/ts;
  //NSLog(@"tsp=%f ts=%f p=%f", tsp, ts, p);
  return p;
}

-(void)gotoPosition:(double)pos
{
  _epilogue = acmNoEpilogue;
  unsigned long posPCM = _totalPCM * pos;
  _totalPCMPlayed = 0;
  NSUInteger i;
  for (i = 0; i < [_acms count]; i++)
  {
    ACMStream* acm = [self _acmAtIndex:i];
    int acmPCM = acm_pcm_total(acm);
    if (_totalPCMPlayed + acmPCM > posPCM)
    {
      unsigned long offset = posPCM - _totalPCMPlayed;
      //NSLog(@"Renderer gotoPosition:%f, acm %d of %d posInACM(%f)/contribution(%f)=amt(%f)",
      //  pos, i+1, [_acms count], posInACM, acmContribution, amt);
      acm_seek_pcm(acm, (unsigned)offset);
      _totalPCMPlayed += offset;
      _currentACM = i;
      break;
    }
    else
    {
      //NSLog(@"Renderer gotoPosition:%f, posInACM=%f passing acm %d of %d contribution=%f",
      //  pos, posInACM, i+1, [_acms count], acmContribution);
      _totalPCMPlayed += acmPCM;
    }
  }
}

// Returns a number between 0.0 and 1.0 inclusive that represents the loop point.
-(double)loopPosition
{
  double pos = 0.0, samplesBeforeLoop = 0.0;
  unsigned long i;
  for (i = 0; i < _loopPoint; i++)
  {
    samplesBeforeLoop += acm_pcm_total([self _acmAtIndex:i]);
  }
  pos = samplesBeforeLoop / (double)_totalPCM;
  return pos;
}

-(ACMStream*)_acmAtIndex:(NSUInteger)i
{
  return [[_acms objectAtIndex:i] pointerValue];
}

-(double)seconds {return _totalSeconds;}

-(void)setAmp:(float)val {_amp = val;}
-(float)amp {return _amp;}
-(BOOL)isPlaying {return _nowPlaying;}

-(OSStatus)_createAU:(double)rate
{
	OSStatus err = noErr;
  AURenderCallbackStruct input;
	ComponentDescription desc;
	desc.componentType = kAudioUnitType_Output;
	desc.componentSubType = kAudioUnitSubType_DefaultOutput;
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;
	desc.componentFlags = 0;
	desc.componentFlagsMask = 0;
	Component comp = FindNextComponent(NULL, &desc);
	if (comp == NULL) { printf("FindNextComponent\n"); return err; }
	err = OpenAComponent(comp, &_au);
	if (err) { printf("OpenAComponent=%ld\n", err); return err; }
	input.inputProc = RenderCB;
	input.inputProcRefCon = self;
	err = AudioUnitSetProperty(_au, kAudioUnitProperty_SetRenderCallback, 
								             kAudioUnitScope_Input, 0, &input, sizeof(input));
	if (err) { printf("AudioUnitSetProperty-CB=%ld\n", err); return err; }
	AudioStreamBasicDescription streamFormat;
  streamFormat.mSampleRate = rate;
  streamFormat.mFormatID = kAudioFormatLinearPCM;
  streamFormat.mFormatFlags = kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
  streamFormat.mBytesPerPacket = 4;
  streamFormat.mFramesPerPacket = 1;
  streamFormat.mBytesPerFrame = 4;
  streamFormat.mChannelsPerFrame = 2;
  streamFormat.mBitsPerChannel = 32;
	err = AudioUnitSetProperty(_au, kAudioUnitProperty_StreamFormat,
							kAudioUnitScope_Input, 0, &streamFormat,
							sizeof(AudioStreamBasicDescription));
	if (err) { printf("AudioUnitSetProperty-SF=%4.4s, %ld\n", (char*)&err, err); return err; }
	err = AudioUnitInitialize(_au);
	if (err) { printf("AudioUnitInitialize=%ld\n", err); return err; }
	Float64 outSampleRate;
	UInt32 size = sizeof(Float64);
	err = AudioUnitGetProperty(_au, kAudioUnitProperty_SampleRate,
							kAudioUnitScope_Output, 0, &outSampleRate, &size);
	if (err) { printf ("AudioUnitSetProperty-GF=%4.4s, %ld\n", (char*)&err, err);}
	return err;
}

-(int16_t*)_bufferSamples:(UInt32)count
{
  //NSLog(@"_bufferSamples:%d", count);
  int16_t* acmBuffer = NULL;
  if (!_suspended && _epilogue != acmDidEpilogue)
  {
    unsigned long bytesNeeded = count * 2 * sizeof(int16_t);
    unsigned long bytesBuffered = 0;
    while (bytesBuffered < bytesNeeded)
    {
      ACMStream* acm = NULL;
      if (_epilogue == acmDoingEpilogue)
      {
        if (_currentACM < [_epilogueNames count]) acm = [self _epilogueAtPosition:_currentACM];
      }
      else
      {
        if (_currentACM < [_acms count]) acm = [self _acmAtIndex:_currentACM];
      }
      if (!acm) NSLog(@"No acm at index %d of %d??", _currentACM, [_acms count]);
      unsigned pcm1 = acm_pcm_tell(acm);
      unsigned pcmall = acm_pcm_total(acm);
      //NSLog(@" pcm1 %d pcmall %d", pcm1, pcmall);
      if (pcmall > pcm1)
      {
        unsigned long needed = bytesNeeded - bytesBuffered;
        if (!acmBuffer) acmBuffer = calloc(bytesNeeded, 1L);
        int before = acm_pcm_tell(acm);
        int res = acm_read_loop(acm, ((char*)acmBuffer) + bytesBuffered, needed, 0, 2, 1);
        //hexdump(((char*)acmBuffer) + bytesBuffered, res);
        int after = acm_pcm_tell(acm);
        //NSLog(@"  needed %d, read %d bytes, was %d, now %d", needed, res, before, after);
        bytesBuffered += res;
        if (_epilogue != acmDoingEpilogue) _totalPCMPlayed += (after - before);
      }
      else
      {
        acm = [self _advACM];
        if (!acm)
        {
          if (_delegate)
          {
            [_delegate performSelectorOnMainThread:@selector(acmDidFinishPlaying:)
                       withObject:self waitUntilDone:NO];
          }
          break;
        }
      }
    }
  }
  //NSLog(@"Position=%f", [self position]);
  return acmBuffer;
}

-(void)doEpilogue:(BOOL)flag
{
  if (_epilogues) _epilogue = flag;
}

-(int)epilogueState {return _epilogue;}

// Normally will just report the ACM that is playing in sequence.
// When we are in 'epilogue mode' then it reports the ACM that was identified in the .mus file
// by the @tag directive.
// This upates the _currentACM index and returns the next reader to play.
// If nil, we are done playing.
-(ACMStream*)_advACM
{
  //NSLog(@"_advACM with epilogue state=%d; _epilogues=0x%X", _epilogue, _epilogues);
  ACMStream* acm = NULL;
  if (_epilogue == acmDidEpilogue) {}
  else if (_epilogue == acmDoingEpilogue) _epilogue = acmDidEpilogue;
  else if (_epilogue == acmWillDoEpilogue || (!_loop && _currentACM == [_acms count]-1))
  {
    if (_epilogues)
    {
      acm = [self _epilogueAtPosition:_currentACM];
      if (acm) _epilogue = acmDoingEpilogue;
    }
  }
  if (_epilogue != acmDidEpilogue && !acm)
  {
    _currentACM++;
    if (_loop && _currentACM >= [_acms count])
    {
      [self gotoPosition:[self loopPosition]];
    }
    if (_currentACM < [_acms count]) acm = [[_acms objectAtIndex:_currentACM] pointerValue];
  }
  if (acm) acm_seek_time(acm, 0);
  //NSLog(@"_advACM (ep %d) returns %@ with _currentACM %d of %d", _epilogue, (acm)?[acm name]:@"nil", _currentACM, [_acms count]);
  //NSLog(@"%@", acm);
  if (!acm) _currentACM = 0;
  return acm;
}

-(ACMStream*)_epilogueAtPosition:(NSUInteger)pos
{
  NSString* epname = [_epilogueNames objectAtIndex:pos];
  id obj = [_epilogues objectForKey:epname];
  if ([obj isKindOfClass:[NSNull class]]) return nil;
  return [obj pointerValue];
}

-(void)_progress
{
  if (!_suspended && _delegate && [_delegate respondsToSelector:@selector(acmProgress:)])
  {
    [_delegate performSelectorOnMainThread:@selector(acmProgress:)
               withObject:self waitUntilDone: NO];
  }
}

#define BUFF_SIZE 0x20000L
-(void)exportAIFFToURL:(NSURL*)url
{
  unsigned char *buff = NULL;
  buff = malloc(BUFF_SIZE);
  if (buff)
  {
    ACMStream* acm;
    BOOL savesusp = _suspended;
    [self suspend];
    double savePos = [self position];
    [self gotoPosition:0.0];
    AudioStreamBasicDescription streamFormat;
    acm = [[_acms objectAtIndex:0L] pointerValue];
    unsigned channels = acm_channels(acm);
    streamFormat.mSampleRate = acm_rate(acm);
    streamFormat.mFormatID = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags = kLinearPCMFormatFlagIsBigEndian | kLinearPCMFormatFlagIsPacked;
    streamFormat.mChannelsPerFrame = channels;
    streamFormat.mFramesPerPacket = 1;
    streamFormat.mBitsPerChannel = 16;
    streamFormat.mBytesPerFrame = 4;
    streamFormat.mBytesPerPacket = 4;
    SInt64 packetidx = 0;
    AudioFileID fileID;
    OSStatus err = AudioFileCreateWithURL((CFURLRef)url, kAudioFileAIFFType, &streamFormat, kAudioFileFlags_EraseFile, &fileID);
    NSLog(@"AudioFileCreateWithURL %.4s rate %f file %d", &err, streamFormat.mSampleRate, fileID);
    for (_currentACM = 0; _currentACM < [_acms count]; _currentACM++)
    {
      unsigned bytesDone = 0;
      acm = [self _acmAtIndex:_currentACM];
      acm_seek_pcm(acm, 0);
      unsigned totalBytes = acm_pcm_total(acm) * acm_channels(acm) * ACM_WORD;
	    while (bytesDone < totalBytes)
      {
		    int res = acm_read_loop(acm, buff, BUFF_SIZE, 1, 2, 1);
        //hexdump(buff,res);
        if (!res)
        {
          //NSLog(@"WTF? Couldn't get acm reader to cough up any bits for the epilogue??\n%@", epiacm);
          break;
        }
        UInt32 ioNumPackets = res/streamFormat.mBytesPerPacket;
        err = AudioFileWritePackets(fileID, false, res, NULL, packetidx, &ioNumPackets, buff);
        packetidx += ioNumPackets;
        //NSLog(@"AudioFileWritePackets %.4s", &err);
        //double percent = (double)_totalPCMPlayed/(double)_totalPCM;
        //NSLog(@"Wrote %lu samples of %lu (%f\%)", _totalSamplesPlayed, _totalSamples, percent*100);
        if (_delegate && [_delegate respondsToSelector:@selector(acmExportProgress:)])
        {
          [_delegate acmExportProgress:self];
        }
      }
    }
    //NSLog(@"Ready for AIFF epilogue");
    if (_epilogues && [_epilogues count])
    {
      //NSLog(@"Will use epilogue %@", [_epilogueNames lastObject]);
      acm = [self _epilogueAtPosition:[_epilogueNames count]-1];
      acm_seek_pcm(acm, 0);
      unsigned totalBytes = acm_pcm_total(acm) * acm_channels(acm) * ACM_WORD;
	    unsigned bytesDone = 0;
      while (bytesDone < totalBytes)
      {
		    int res = acm_read_loop(acm, buff, BUFF_SIZE, 1, 2, 1);
        //int acm_read_loop(ACMStream *acm, void *dst, unsigned bytes, int bigendianp, int wordlen, int sgned)
        if (!res)
        {
          //NSLog(@"WTF? Couldn't get acm reader to cough up any bits for the epilogue??\n%@", epiacm);
          break;
        }
        UInt32 ioNumPackets = res/streamFormat.mBytesPerPacket;
        err = AudioFileWritePackets(fileID, false, res, NULL, packetidx, &ioNumPackets, buff);
        packetidx += ioNumPackets;
        //NSLog(@"AudioFileWritePackets %.4s", &err);
      }
    }
    AudioFileClose(fileID);
    [self gotoPosition:savePos];
    if (!savesusp) [self resume];
    free(buff);
  }
}
@end

#if 0
static void hexdump(void *data, int size)
{
    /* dumps size bytes of *data to stdout. Looks like:
     * [0000] 75 6E 6B 6E 6F 77 6E 20
     *                  30 FF 00 00 00 00 39 00 unknown 0.....9.
     * (in a single line of course)
     */

    unsigned char *p = data;
    unsigned char c;
    int n;
    char bytestr[4] = {0};
    char addrstr[10] = {0};
    char hexstr[ 16*3 + 5] = {0};
    char charstr[16*1 + 5] = {0};
    for(n=1;n<=size;n++) {
        if (n%16 == 1) {
            /* store address for this line */
            snprintf(addrstr, sizeof(addrstr), "%.4x",
               ((unsigned int)p-(unsigned int)data) );
        }
            
        c = *p;
        if (isalnum(c) == 0) {
            c = '.';
        }

        /* store hex str (for left side) */
        snprintf(bytestr, sizeof(bytestr), "%02X ", *p);
        strncat(hexstr, bytestr, sizeof(hexstr)-strlen(hexstr)-1);

        /* store char str (for right side) */
        snprintf(bytestr, sizeof(bytestr), "%c", c);
        strncat(charstr, bytestr, sizeof(charstr)-strlen(charstr)-1);

        if(n%16 == 0) { 
            /* line completed */
            printf("[%4.4s]   %-50.50s  %s\n", addrstr, hexstr, charstr);
            hexstr[0] = 0;
            charstr[0] = 0;
        } else if(n%8 == 0) {
            /* half line: add whitespaces */
            strncat(hexstr, "  ", sizeof(hexstr)-strlen(hexstr)-1);
            strncat(charstr, " ", sizeof(charstr)-strlen(charstr)-1);
        }
        p++; /* next byte */
    }

    if (strlen(hexstr) > 0) {
        /* print rest of buffer if not empty */
        printf("[%4.4s]   %-50.50s  %s\n", addrstr, hexstr, charstr);
    }
}
#endif

