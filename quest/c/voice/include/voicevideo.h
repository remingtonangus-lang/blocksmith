// Video clips for the Quest's voice bug notes (P368; dev builds only, like voicemic.h). Implementation:
// quest/c/voice/voicevideo.c. Every call from one serial queue.
#include <stdint.h>

// H.264 hardware encoder fed NV12 pictures (width x height, packed rows; Y plane then interleaved UV), keeping the
// last `windowSeconds` of packets (from a keyframe) in memory. Returns NULL on failure.
void *bs_venc_open(int32_t width, int32_t height, int32_t fps, int32_t bitrate, int32_t keySeconds, int32_t windowSeconds);
int bs_venc_frame(void *enc, const uint8_t *nv12, int64_t ptsUs);   // 0 queued, -1 dropped
// An MP4 at path: the buffered packets, then every new one until bs_venc_end (bytes written; 0: nothing, -1: no clip).
int bs_venc_begin(void *enc, const char *path);                      // 0 ok, -1 error (no picture encoded yet)
int64_t bs_venc_end(void *enc);
int64_t bs_venc_buffered(void *enc);                                 // bytes held in memory
void bs_venc_close(void *enc);
