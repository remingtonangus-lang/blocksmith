// Video clips for the Quest's voice bug notes (P368; dev builds only, like voicemic.h). Implementation:
// quest/c/voice/voicevideo.c. Every call from one serial queue.
#include <stdint.h>

// H.264 hardware encoder fed NV12 pictures (width x height, packed rows; Y plane then interleaved UV), keeping the
// last `windowSeconds` of packets (from a keyframe) in memory. Returns NULL on failure.
void *bs_venc_open(int32_t width, int32_t height, int32_t fps, int32_t bitrate, int32_t keySeconds, int32_t windowSeconds);
int bs_venc_frame(void *enc, const uint8_t *nv12, int64_t ptsUs);   // 0 queued, -1 dropped
// (Nov 13) An RGBA8 picture (rows `rowBytes` apart), converted straight into the encoder's input.
int bs_venc_frame_rgba(void *enc, const uint8_t *rgba, int32_t rowBytes, int64_t ptsUs);   // 0 queued, -1 dropped
// An MP4 at path: the buffered packets, then every new one until bs_venc_end (bytes written; 0: nothing, -1: no clip).
int bs_venc_begin(void *enc, const char *path);                      // 0 ok, -1 error (no picture encoded yet)
int64_t bs_venc_end(void *enc);
int64_t bs_venc_buffered(void *enc);                                 // bytes held in memory
void bs_venc_close(void *enc);
// Ledger 406 (Nov 21, Remington: the recordings had no sound): the game's own mix and his voice go into the clip as
// one AAC track. Any thread: the audio callback pushes what it plays (interleaved float stereo at `rate`), the voice
// note reader what the microphone hears (mono int16 at `rate`); each with the wall clock (microseconds, the pictures'
// clock) of its first frame. Lock-free for the audio thread: a push that finds the ring busy is dropped.
void bs_vaudio_game(const float *lr, int32_t frames, int32_t rate, int64_t ptsUs);
void bs_vaudio_mic(const int16_t *pcm, int32_t frames, int32_t rate, int64_t ptsUs);
void bs_vaudio_enable(int on);                                      // off: pushes are ignored (no cost)
