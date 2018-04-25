/*
 * Copyright © 2010-2018, Brian "Moses" Hall
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
-(OSStatus)_initAUGraph:(double)rate;
-(int16_t*)_bufferSamples:(UInt32)count;
-(ACMData*)_advACM;
-(ACMData*)_epilogueAtIndex:(NSUInteger)idx;
-(void)_progress;
-(void)_setEpilogueState:(int)state;
-(void)_gotoACMAtIndex:(NSUInteger)index;
-(double)_pctForPCM:(unsigned long)pcm;
@end

static OSStatus	RenderCB(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, 
                         const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, 
                         UInt32 inNumberFrames, AudioBufferList* ioData);

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
  UInt32 samples = inNumberFrames;
  unsigned channels = myself.channels;
  if (channels > 1) samples *= 2;
  int16_t* acmBuffer = [myself _bufferSamples:samples];
  if (acmBuffer) acmBufferRead = acmBuffer;
  for (i = 0; i < inNumberFrames; i++)
  {
    float waveL = 0.0f, waveR = 0.0f;
    if (acmBuffer)
    {
      int16_t lSample = *acmBufferRead;
      acmBufferRead++;
      int16_t rSample = lSample;
      if (channels > 1)
      {
        rSample = *acmBufferRead;
        acmBufferRead++;
      }
      // Scale short int values to {-1,1}
      waveL = (float)lSample/32767.0f;
      if (rSample != lSample) waveR = (float)rSample/32767.0f;
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
@synthesize amp = _amp;
@synthesize seconds = _totalSeconds;
@synthesize channels = _channels;
@synthesize playing = _nowPlaying;
@synthesize loops = _loops;
//@synthesize loopIndex = _loopIndex;
@synthesize epilogueState = _epilogue;
@synthesize isVorbis = _isVorbis;

-(ACMRenderer*)initWithPlaylist:(NSArray*)list andEpilogues:(NSArray*)epilogues
{
  self = [super init];
  _acmFiles = [list retain];
  _epilogueFiles = [epilogues retain];
  _amp = 0.5f;
  _totalSeconds = 0.0;
  _loops = NO;
  double rate = 0.0;
  _acms = [[NSMutableArray alloc] init];
  ACMData* acm;
  for (NSString* file in list)
  {
    acm = [[ACMData alloc] initWithPath:file];
    if (acm)
    {
      if (!_isVorbis) _isVorbis = [acm isVorbis];
      [_acms addObject:acm];
      _totalPCM += [acm PCMTotal];
      _totalSeconds += acm.timeTotal;
      _channels = [acm channels];
      rate = acm.rate;
      [acm release];
    }
    // FIXME: this happens for BGII last entry in BM2.mus
    // Could try to repair???
    else NSLog(@"WARNING: can't find acm file named %@", file);
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
      acm = [[ACMData alloc] initWithPath:file];
      obj = nil;
      if (!acm)
      {
        NSLog(@"WARNING: can't find epilogue named %@; using NSNull", file);
        obj = [NSNull null];
      }
      else obj = acm;
      [_epilogues setObject:obj forKey:file];
      if (acm) [acm release];
    }
    _hasFinalEpilogue = (nil != [self _epilogueAtIndex:[_acms count]-1]);
  }
  OSStatus err = [self _initAUGraph:rate];
  if (err)
  {
    NSLog(@"_initAUGraph: %f failed: '%.4s'", rate, (char*)&err);
    [self release];
    self = nil;
  }
  return self;
}

// FIXME: this needs a better way to report errors
-(ACMRenderer*)initWithData:(NSData*)data
{
  self = [super init];
  _data = [data copy];
  _amp = 0.5f;
  _totalSeconds = 0.0;
  _loops = NO;
  OSStatus err = noErr;
  _acms = [[NSMutableArray alloc] init];
  ACMData* acm = [[ACMData alloc] initWithData:data];
  if (acm)
  {
    [_acms addObject:acm];
    _totalPCM = [acm PCMTotal];
    _totalSeconds = acm.timeTotal;
    _channels = [acm channels];
    [acm release];
    err = [self _initAUGraph:acm.rate];
  }
  else NSLog(@"WARNING: can't load ACM data");
  if (err)
  {
    NSLog(@"_initAUGraph: %d failed: '%.4s'", acm.rate, (char*)&err);
  }
  if (err || !acm)
  {
    [_acms release];
    [self release];
    self = nil;
  }
  return self;
}

-(void)dealloc
{
  if (_ag) DisposeAUGraph(_ag);
  if (_acms) [_acms release];
  if (_epilogueNames) [_epilogueNames release];
  if (_epilogues) [_epilogues release];
  if (_acmFiles) [_acmFiles release];
  if (_epilogueFiles) [_epilogueFiles release];
  if (_data) [_data release];
  [super dealloc];
}

-(id)copyWithZone:(NSZone*)zone
{
  #pragma unused (zone)
  if (_data) return [[ACMRenderer alloc] initWithData:_data];
  else return [[ACMRenderer alloc] initWithPlaylist:_acmFiles andEpilogues:_epilogueFiles];
}

-(void)setDelegate:(id)del {_delegate = del;}

-(void)setDoesLoop:(BOOL)loop
{
  _loops = loop;
  if (loop)
  {
    if (_epilogue == acmWillDoEpilogue ||
        _epilogue == acmWillDoFinalEpilogue) [self _setEpilogueState:acmNoEpilogue];
  }
  else
  {
    if (_hasFinalEpilogue && _epilogue != acmWillDoEpilogue)
      [self _setEpilogueState:acmWillDoFinalEpilogue];
  }
}
-(void)setLoopIndex:(NSUInteger)li {if (li < [_acms count]) _loopIndex = li;}

-(void)start
{
  if (!_nowPlaying)
  {
    OSStatus err = AUGraphStart(_ag);
    if (!err) _nowPlaying = YES;
  }
}

-(void)stop
{
  if (_nowPlaying)
  {
    OSStatus err = AUGraphStop(_ag);
    if (err) NSLog(@"ERROR '%.4s' from AudioOutputUnitStop", (char*)&err);
    else _nowPlaying = NO;
  }
}

-(double)pct
{
  return [self _pctForPCM:_totalPCMPlayed + _totalEpiloguePCMPlayed];
}

// FIXME: this should take into account final epilogue
-(void)gotoPct:(double)pct
{
  if (pct < 0.0) pct = 0.0;
  if (pct > 1.0) pct = 1.0;
  [self _setEpilogueState:acmNoEpilogue];
  unsigned long posPCM = (_totalPCM + _totalEpiloguePCM) * pct;
  _totalPCMPlayed = 0;
  NSUInteger i;
  for (i = 0; i < [_acms count]; i++)
  {
    ACMData* acm = [_acms objectAtIndex:i];
    int acmPCM = acm.PCMTotal;
    if (_totalPCMPlayed + acmPCM >= posPCM)
    {
      unsigned long offset = posPCM - _totalPCMPlayed;
      [acm PCMSeek:offset];
      _totalPCMPlayed += offset;
      _currentACM = i;
      break;
    }
    else
    {
      _totalPCMPlayed += acmPCM;
    }
  }
}

// Returns number between 0.0 and 1.0 inclusive that represents the loop point.
-(double)loopPct
{
  unsigned long pcm = 0;
  NSUInteger i;
  for (i = 0; i < _loopIndex; i++)
  {
    ACMData* acm = [_acms objectAtIndex:i];
    pcm += acm.PCMTotal;
  }
  return [self _pctForPCM:pcm];
}

-(void)setAmp:(double)val
{
  // The dial does not go up to 11 ;-)
  if (val < 0.0) val = 0.0;
  if (val > 1.0) val = 1.0;
  _amp = val;
}

-(void)doEpilogue:(BOOL)flag
{
  if (_epilogues)
    [self _setEpilogueState:(flag)?acmWillDoEpilogue:acmNoEpilogue];
}

-(void)getEpilogueStartPct:(double*)oStart endPct:(double*)oEnd
       pctDelta:(double*)oDelta
{
  double start = 0.0;
  double end = 0.0;
  double delta = 1.0;
  if (_epilogue != acmNoEpilogue && _epilogues)
  {
    unsigned grandTotal = _totalPCM;
    unsigned long startPCM = 0;
    unsigned long endPCM = 0;
    NSUInteger n = [_acms count];
    for (unsigned i = 0; i < n; i++)
    {
      ACMData* acm = [_acms objectAtIndex:i];
      startPCM += acm.PCMTotal;
      endPCM += acm.PCMTotal;
      ACMData* ep = [self _epilogueAtIndex:i];
      if (_epilogue == acmWillDoFinalEpilogue && i < n-1) continue;
      if (i >= _currentACM && ep)
      {
        endPCM += ep.PCMTotal;
        grandTotal += ep.PCMTotal;
        break;
      }
    }
    start = (double)startPCM / (double)grandTotal;
    end = (double)endPCM / (double)grandTotal;
    delta = (double)_totalPCM / (double)grandTotal;
  }
  if (NULL != oStart) *oStart = start;
  if (NULL != oEnd) *oEnd = end;
  if (NULL != oDelta) *oDelta = delta;
}

#pragma mark Internal
-(OSStatus)_initAUGraph:(double)rate
{
  OSStatus result = NewAUGraph(&_ag);
  if (result) return result;
  AUNode outputNode;
  AudioUnit outputUnit;
  //  output component
  ComponentDescription output_desc;
  output_desc.componentType = kAudioUnitType_Output;
  output_desc.componentSubType = kAudioUnitSubType_DefaultOutput;
  output_desc.componentFlags = 0;
  output_desc.componentFlagsMask = 0;
  output_desc.componentManufacturer = kAudioUnitManufacturer_Apple;
  result = AUGraphAddNode(_ag, &output_desc, &outputNode);
  if (result) return result;
  result = AUGraphOpen(_ag);
  if (result) return result;
  result = AUGraphNodeInfo(_ag, outputNode, NULL, &outputUnit);
  if (result) return result;
  AudioStreamBasicDescription desc;
  desc.mSampleRate = rate;
  desc.mFormatID = kAudioFormatLinearPCM;
  desc.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked |
                      kAudioFormatFlagIsNonInterleaved;
#if TARGET_RT_BIG_ENDIAN
  desc.mFormatFlags |= kAudioFormatFlagIsBigEndian;
#endif
  desc.mBytesPerPacket = 4;
  desc.mFramesPerPacket = 1;
  desc.mBytesPerFrame = 4;
  desc.mChannelsPerFrame = 2;
  desc.mBitsPerChannel = 32;
  // Setup render callback struct
  // This struct describes the function that will be called
  // to provide a buffer of audio samples for the mixer unit.
  AURenderCallbackStruct rcbs;
  rcbs.inputProc = RenderCB;
  rcbs.inputProcRefCon = self;
  // Set a callback for the specified node's specified input
  result = AudioUnitSetProperty(outputUnit, kAudioUnitProperty_SetRenderCallback,
                                kAudioUnitScope_Input, 0, &rcbs,
                                sizeof(AURenderCallbackStruct)); 
  //result = AUGraphSetNodeInputCallback(_ag, mixerNode, i, &rcbs);
  if (result) return result;
  // Apply the modified CAStreamBasicDescription to the mixer input bus
  result = AudioUnitSetProperty(outputUnit, kAudioUnitProperty_StreamFormat,
                                kAudioUnitScope_Input, 0,
                                &desc, sizeof(desc));
  if (result) return result;
  // Apply the Description to the mixer output bus
  /*result = AudioUnitSetProperty(outputUnit, kAudioUnitProperty_StreamFormat,
                                kAudioUnitScope_Output, 0,
                                &desc, sizeof(desc));
  if (result) return result;*/
  // Once everything is set up call initialize to validate connections
  return AUGraphInitialize(_ag);
}

-(int16_t*)_bufferSamples:(UInt32)count
{
  //NSLog(@"_bufferSamples:%d", count);
  int16_t* acmBuffer = NULL;
  unsigned long bytesNeeded = count * sizeof(int16_t);
  unsigned long bytesBuffered = 0;
  while (bytesBuffered < bytesNeeded)
  {
    ACMData* acm = NULL;
    if (_epilogue == acmDoingEpilogue)
    {
      if (_currentACM < [_epilogueNames count])
        acm = [self _epilogueAtIndex:_currentACM];
    }
    else
    {
      if (_currentACM < [_acms count])
        acm = [_acms objectAtIndex:_currentACM];
    }
    if (!acm) NSLog(@"No acm at index %u of %lu??", (unsigned)_currentACM,
                    (unsigned long)[_acms count]);
    unsigned pcm1 = [acm PCMTell];
    unsigned pcmall = acm.PCMTotal;
    //NSLog(@" pcm1 %d pcmall %d", pcm1, pcmall);
    if (pcmall > pcm1)
    {
      unsigned long needed = bytesNeeded - bytesBuffered;
      if (!acmBuffer) acmBuffer = calloc(bytesNeeded, 1L);
      int before = [acm PCMTell];
      int res = [acm bufferSamples:((char*)acmBuffer) + bytesBuffered
                     count:needed bigEndian:TARGET_RT_BIG_ENDIAN];
      //#if ACMPLAYER_DEBUG
      //hexdump(((char*)acmBuffer) + bytesBuffered, res);
      //#endif
      int after = [acm PCMTell];
      if (!res) break;
      bytesBuffered += res;
      if (_epilogue != acmDoingEpilogue) _totalPCMPlayed += (after - before);
      else _totalEpiloguePCMPlayed += (after - before);
    }
    else
    {
      acm = [self _advACM];
      if (!acm && _delegate)
      {
        [_delegate performSelectorOnMainThread:@selector(acmDidFinishPlaying:)
                   withObject:self waitUntilDone:NO];
        break;
      }
    }
  }
  //NSLog(@"Position=%f", [self position]);
  return acmBuffer;
}

// Normally will just report the ACM that is playing in sequence.
// When we are in 'epilogue mode' then it reports the ACM that was identified
// in the .mus file by the @tag directive.
// This upates the _currentACM index and returns the next reader to play.
// If nil, we are done playing.
-(ACMData*)_advACM
{
  ACMData* acm = nil;
  BOOL finishedEpilogue = NO;
  if (_epilogue == acmDoingEpilogue)
  {
    finishedEpilogue = YES;
    [self _setEpilogueState:acmNoEpilogue];
  }
  else if (_epilogue == acmWillDoEpilogue)
  {
    acm = [self _epilogueAtIndex:_currentACM];
    if (acm)
    {
      [self _setEpilogueState:acmDoingEpilogue];
      _totalEpiloguePCM = acm.PCMTotal;
      _totalEpiloguePCMPlayed = 0;
    }
  }
  else if (_epilogue == acmWillDoFinalEpilogue &&
           !_loops && _currentACM == [_acms count]-1)
  {
    acm = [self _epilogueAtIndex:_currentACM];
    if (acm)
    {
      [self _setEpilogueState:acmDoingEpilogue];
      _totalEpiloguePCMPlayed = 0;
    }
  }
  if (!finishedEpilogue && !acm)
  {
    _currentACM++;
    if (_loops && _currentACM >= [_acms count])
      [self _gotoACMAtIndex:_loopIndex];
    if (_currentACM < [_acms count])
      acm = [_acms objectAtIndex:_currentACM];
  }
  if (acm) [acm PCMSeek:0];
  else _currentACM = 0;
  return acm;
}

-(ACMData*)_epilogueAtIndex:(NSUInteger)idx
{
  NSString* epname = [_epilogueNames objectAtIndex:idx];
  ACMData* obj = [_epilogues objectForKey:epname];
  if ([obj isKindOfClass:[NSNull class]]) obj = nil;
  return obj;
}

-(void)_progress
{
  if (_delegate && [_delegate respondsToSelector:@selector(acmProgress:)])
  {
    [_delegate performSelectorOnMainThread:@selector(acmProgress:)
               withObject:self waitUntilDone:NO];
  }
}

-(void)_setEpilogueState:(int)state
{
  if (_epilogues)
  {
    if (!_loops && state == acmNoEpilogue && _hasFinalEpilogue)
      state = acmWillDoFinalEpilogue;
    if (state == acmWillDoFinalEpilogue)
    {
      ACMData* ep = [self _epilogueAtIndex:[_acms count]-1];
      _totalEpiloguePCM = ep.PCMTotal;
      _totalEpiloguePCMPlayed = 0;
    }
    if (state == acmNoEpilogue)
    {
      _totalEpiloguePCM = 0;
    }
    int prev = _epilogue;
    if (prev == acmDoingEpilogue && state == acmWillDoEpilogue) return;
    _epilogue = state;
    if (prev != state)
    {
      if (_delegate && [_delegate respondsToSelector:@selector(acmEpilogueStateChanged:)])
      {
        [_delegate performSelectorOnMainThread:@selector(acmEpilogueStateChanged:)
                   withObject:self waitUntilDone:NO];
      }
    }
  }
}

-(void)_gotoACMAtIndex:(NSUInteger)idx
{
  if (idx > [_acms count]) idx = [_acms count]-1;
  [self _setEpilogueState:acmNoEpilogue];
  _totalPCMPlayed = 0;
  _currentACM = idx;
  ACMData* acm;
  for (NSUInteger i = 0; i < idx; i++)
  {
    acm = [_acms objectAtIndex:i];
    int acmPCM = acm.PCMTotal;
    _totalPCMPlayed += acmPCM;
  }
  acm = [_acms objectAtIndex:idx];
  [acm PCMSeek:0];
}

-(double)_pctForPCM:(unsigned long)pcm
{
  double tpcm = (double)_totalPCM + (double)_totalEpiloguePCM;
  double pct = (double)pcm / tpcm;
  //NSLog(@"pcm=%lu tpcm=%f (%f + %f) pct=%f", pcm, tpcm, (double)_totalPCM, (double)_totalEpiloguePCM, pct);
  return pct;
}

#define BUFF_SIZE 0x20000L
-(void)exportAIFFToURL:(NSURL*)url
{
  char* buff = malloc(BUFF_SIZE);
  if (buff)
  {
    ACMData* acm;
    AudioStreamBasicDescription streamFormat;
    acm = [_acms objectAtIndex:0L];
    //NSLog(@"Rate: %d", acm.rate);
    streamFormat.mSampleRate = acm.rate;
    streamFormat.mFormatID = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags = kLinearPCMFormatFlagIsBigEndian |
                                kAudioFormatFlagIsSignedInteger |
                                kLinearPCMFormatFlagIsPacked;
    streamFormat.mChannelsPerFrame = acm.channels;
    streamFormat.mFramesPerPacket = 1;
    streamFormat.mBitsPerChannel = 16;
    streamFormat.mBytesPerFrame = 4;
    streamFormat.mBytesPerPacket = 4;
    SInt64 packetidx = 0;
    AudioFileID fileID;
    OSStatus err = AudioFileCreateWithURL((CFURLRef)url, kAudioFileAIFFType,
                                          &streamFormat,
                                          kAudioFileFlags_EraseFile, &fileID);
    if (err)
      NSLog(@"AudioFileCreateWithURL: error '%.4s' URL %@ rate %f file %d",
            (char*)&err, url, streamFormat.mSampleRate, (int)fileID);
    for (_currentACM = 0; _currentACM < [_acms count]; _currentACM++)
    {
      unsigned bytesDone = 0;
      acm = [_acms objectAtIndex:_currentACM];
      [acm PCMSeek:0];
      unsigned totalBytes = acm.PCMTotal * acm.channels * sizeof(int16_t);
	    while (bytesDone < totalBytes)
      {
        unsigned res = [acm bufferSamples:buff count:BUFF_SIZE bigEndian:YES];
        #if ACMPLAYER_DEBUG
        hexdump(buff,res);
        #endif
        if (!res)
        {
          //NSLog(@"WTF? Couldn't get acm reader to cough up any bits for the epilogue??\n%@", epiacm);
          break;
        }
        UInt32 ioNumPackets = res/streamFormat.mBytesPerPacket;
        err = AudioFileWritePackets(fileID, false, res, NULL, packetidx, &ioNumPackets, buff);
        if (err) NSLog(@"AudioFileWritePackets: error '%.4s'", (char*)&err);
        packetidx += ioNumPackets;
        //NSLog(@"Wrote %lu samples of %lu (%f\%)", _totalSamplesPlayed, _totalSamples, percent*100);
        if (_delegate &&
            [_delegate respondsToSelector:@selector(acmExportProgress:)])
        {
          [_delegate performSelector:@selector(acmExportProgress:)
                     withObject:self];
        }
      }
    }
    //NSLog(@"Ready for AIFF epilogue");
    if (_epilogues && [_epilogues count])
    {
      //NSLog(@"Will use epilogue %@", [_epilogueNames lastObject]);
      acm = [self _epilogueAtIndex:[_epilogueNames count]-1];
      [acm PCMSeek:0];
      unsigned totalBytes = [acm PCMTotal] * acm.channels * ACM_WORD;
	    unsigned bytesDone = 0;
      while (bytesDone < totalBytes)
      {
		    unsigned res = [acm bufferSamples:buff count:BUFF_SIZE bigEndian:YES];
        if (!res)
        {
          //NSLog(@"WTF? Couldn't get acm reader to cough up any bits for the epilogue??\n%@", epiacm);
          break;
        }
        UInt32 ioNumPackets = res/streamFormat.mBytesPerPacket;
        err = AudioFileWritePackets(fileID, false, res, NULL, packetidx,
                                    &ioNumPackets, buff);
        if (err) NSLog(@"AudioFileWritePackets: error '%.4s'", (char*)&err);
        packetidx += ioNumPackets;
      }
    }
    AudioFileClose(fileID);
    free(buff);
  }
}
@end


#if ACMPLAYER_DEBUG
void hexdump(void *data, int size)
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
  for (n=1;n<=size;n++)
  {
    if (n%16 == 1)
    {
      /* store address for this line */
      snprintf(addrstr, sizeof(addrstr), "%.4x",
               ((unsigned int)p-(unsigned int)data));
    }
    c = *p;
    if (isalnum(c) == 0)
    {
      c = '.';
    }
    /* store hex str (for left side) */
    snprintf(bytestr, sizeof(bytestr), "%02X ", *p);
    strncat(hexstr, bytestr, sizeof(hexstr)-strlen(hexstr)-1);
    /* store char str (for right side) */
    snprintf(bytestr, sizeof(bytestr), "%c", c);
    strncat(charstr, bytestr, sizeof(charstr)-strlen(charstr)-1);
    if (n%16 == 0)
    { 
      /* line completed */
      printf("[%4.4s]   %-50.50s  %s\n", addrstr, hexstr, charstr);
      hexstr[0] = 0;
      charstr[0] = 0;
    }
    else if (n%8 == 0)
    {
      /* half line: add whitespaces */
      strncat(hexstr, "  ", sizeof(hexstr)-strlen(hexstr)-1);
      strncat(charstr, " ", sizeof(charstr)-strlen(charstr)-1);
    }
    p++; /* next byte */
  }
  if (strlen(hexstr) > 0)
  {
    /* print rest of buffer if not empty */
    printf("[%4.4s]   %-50.50s  %s\n", addrstr, hexstr, charstr);
  }
}
#endif

