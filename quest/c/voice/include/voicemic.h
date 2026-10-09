// Microphone capture for the Quest's voice bug notes (dev builds only: quest/tools/build-apk.sh copies this into the
// CAndroidGlue module unless STORE=1). Implementation: quest/c/voice/voicemic.c.
#include <stdint.h>
#include <android/native_activity.h>

// RECORD_AUDIO runtime permission through JNI (NativeActivity has no Java of its own).
int bs_mic_permission(ANativeActivity *activity);   // 1 granted, 0 not granted, -1 JNI error
int bs_mic_request(ANativeActivity *activity);      // shows the system dialog (asynchronous); 0 ok, -1 error

// Mono 16-bit AAudio input stream. preset: AAUDIO_INPUT_PRESET_* (VOICE_COMMUNICATION = 7 cancels the game's
// own sound from the speakers). Returns NULL on failure.
void *bs_mic_open(int32_t sampleRate, int32_t preset);
int32_t bs_mic_rate(void *mic);
int32_t bs_mic_read(void *mic, int16_t *pcm, int32_t frames, int64_t timeoutNanos);   // frames read, < 0 on error
void bs_mic_close(void *mic);

// AAC-LC encoder (NdkMediaCodec) writing an ADTS stream: every frame is self-contained, so a file cut short by a
// crash still plays up to its last flushed frame. Returns NULL on failure.
void *bs_aac_open(const char *path, int32_t sampleRate, int32_t bitrate);
int bs_aac_write(void *enc, const int16_t *pcm, int32_t frames);   // 0 ok, -1 error
int64_t bs_aac_bytes(void *enc);
void bs_aac_close(void *enc);
