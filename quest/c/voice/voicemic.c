// Voice bug notes on the Quest (dev builds only): RECORD_AUDIO permission, AAudio input, AAC/ADTS encoding.
#include "voicemic.h"
#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <aaudio/AAudio.h>
#include <media/NdkMediaCodec.h>
#include <media/NdkMediaFormat.h>
#include <android/log.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "Blocksmith", __VA_ARGS__)

// MARK: permission

static JNIEnv *attach(ANativeActivity *a, int *attached) {
    JNIEnv *env = NULL;
    *attached = 0;
    jint r = (*a->vm)->GetEnv(a->vm, (void **)&env, JNI_VERSION_1_6);
    if (r == JNI_EDETACHED) {
        if ((*a->vm)->AttachCurrentThread(a->vm, &env, NULL) != JNI_OK) return NULL;
        *attached = 1;
    } else if (r != JNI_OK) return NULL;
    return env;
}

static void detach(ANativeActivity *a, int attached) {
    if (attached) (*a->vm)->DetachCurrentThread(a->vm);
}

static int cleared(JNIEnv *env) {
    if ((*env)->ExceptionCheck(env)) { (*env)->ExceptionClear(env); return 1; }
    return 0;
}

int bs_mic_permission(ANativeActivity *a) {
    int attached;
    JNIEnv *env = attach(a, &attached);
    if (!env) return -1;
    int result = -1;
    jclass cls = (*env)->GetObjectClass(env, a->clazz);
    jmethodID m = (*env)->GetMethodID(env, cls, "checkSelfPermission", "(Ljava/lang/String;)I");
    if (m && !cleared(env)) {
        jstring p = (*env)->NewStringUTF(env, "android.permission.RECORD_AUDIO");
        jint r = (*env)->CallIntMethod(env, a->clazz, m, p);
        if (!cleared(env)) result = r == 0 ? 1 : 0;     // PackageManager.PERMISSION_GRANTED = 0
        (*env)->DeleteLocalRef(env, p);
    }
    (*env)->DeleteLocalRef(env, cls);
    detach(a, attached);
    return result;
}

int bs_mic_request(ANativeActivity *a) {
    int attached;
    JNIEnv *env = attach(a, &attached);
    if (!env) return -1;
    int result = -1;
    jclass cls = (*env)->GetObjectClass(env, a->clazz);
    jmethodID m = (*env)->GetMethodID(env, cls, "requestPermissions", "([Ljava/lang/String;I)V");
    if (m && !cleared(env)) {
        jclass str = (*env)->FindClass(env, "java/lang/String");
        jstring p = (*env)->NewStringUTF(env, "android.permission.RECORD_AUDIO");
        jobjectArray arr = (*env)->NewObjectArray(env, 1, str, p);
        (*env)->CallVoidMethod(env, a->clazz, m, arr, (jint)7301);
        if (!cleared(env)) result = 0;
        (*env)->DeleteLocalRef(env, arr);
        (*env)->DeleteLocalRef(env, p);
        (*env)->DeleteLocalRef(env, str);
    }
    (*env)->DeleteLocalRef(env, cls);
    detach(a, attached);
    return result;
}

// MARK: microphone

void *bs_mic_open(int32_t sampleRate, int32_t preset) {
    AAudioStreamBuilder *b = NULL;
    if (AAudio_createStreamBuilder(&b) != AAUDIO_OK || !b) return NULL;
    AAudioStreamBuilder_setDirection(b, AAUDIO_DIRECTION_INPUT);
    AAudioStreamBuilder_setFormat(b, AAUDIO_FORMAT_PCM_I16);
    AAudioStreamBuilder_setChannelCount(b, 1);
    AAudioStreamBuilder_setSampleRate(b, sampleRate);
    AAudioStreamBuilder_setSharingMode(b, AAUDIO_SHARING_MODE_SHARED);
    AAudioStreamBuilder_setPerformanceMode(b, AAUDIO_PERFORMANCE_MODE_POWER_SAVING);
    AAudioStreamBuilder_setInputPreset(b, (aaudio_input_preset_t)preset);
    AAudioStream *s = NULL;
    aaudio_result_t r = AAudioStreamBuilder_openStream(b, &s);
    AAudioStreamBuilder_delete(b);
    if (r != AAUDIO_OK || !s) { LOGI("voicenotes: mic open failed (%d, preset %d)", (int)r, (int)preset); return NULL; }
    if (AAudioStream_requestStart(s) != AAUDIO_OK) { AAudioStream_close(s); return NULL; }
    LOGI("voicenotes: mic open, %d Hz, preset %d", (int)AAudioStream_getSampleRate(s), (int)preset);
    return s;
}

int32_t bs_mic_rate(void *mic) { return mic ? AAudioStream_getSampleRate((AAudioStream *)mic) : 0; }

int32_t bs_mic_read(void *mic, int16_t *pcm, int32_t frames, int64_t timeoutNanos) {
    return mic ? AAudioStream_read((AAudioStream *)mic, pcm, frames, timeoutNanos) : -1;
}

void bs_mic_close(void *mic) {
    if (!mic) return;
    AAudioStream_requestStop((AAudioStream *)mic);
    AAudioStream_close((AAudioStream *)mic);
}

// MARK: AAC encoder

typedef struct {
    AMediaCodec *codec;
    FILE *file;
    int32_t rate, freqIndex;
    int64_t frames;         // input frames queued (presentation time)
    int64_t bytes;          // bytes written
    int eos;                // the end-of-stream frame came out
} Enc;

static int freqIndex(int32_t rate) {
    static const int32_t rates[] = { 96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000 };
    for (int i = 0; i < 12; i++) if (rates[i] == rate) return i;
    return 8;
}

static void drain(Enc *e, int64_t timeoutUs) {
    for (;;) {
        AMediaCodecBufferInfo info;
        ssize_t i = AMediaCodec_dequeueOutputBuffer(e->codec, &info, timeoutUs);
        if (i == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED || i == AMEDIACODEC_INFO_OUTPUT_BUFFERS_CHANGED) continue;
        if (i < 0) return;      // AMEDIACODEC_INFO_TRY_AGAIN_LATER or an error
        size_t cap = 0;
        uint8_t *buf = AMediaCodec_getOutputBuffer(e->codec, (size_t)i, &cap);
        int eos = (info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM) != 0;
        if (buf && info.size > 0 && !(info.flags & AMEDIACODEC_BUFFER_FLAG_CODEC_CONFIG) && e->file) {
            // ADTS header: MPEG-4 AAC LC, no CRC, mono.
            int len = info.size + 7;
            uint8_t h[7] = { 0xFF, 0xF1, (uint8_t)((1 << 6) | (e->freqIndex << 2)), (uint8_t)((1 << 6) | ((len >> 11) & 3)),
                             (uint8_t)((len >> 3) & 0xFF), (uint8_t)(((len & 7) << 5) | 0x1F), 0xFC };
            fwrite(h, 1, 7, e->file);
            fwrite(buf + info.offset, 1, (size_t)info.size, e->file);
            e->bytes += len;
        }
        AMediaCodec_releaseOutputBuffer(e->codec, (size_t)i, false);
        if (eos) { e->eos = 1; return; }
    }
}

void *bs_aac_open(const char *path, int32_t sampleRate, int32_t bitrate) {
    AMediaCodec *c = AMediaCodec_createEncoderByType("audio/mp4a-latm");
    if (!c) { LOGI("voicenotes: no AAC encoder"); return NULL; }
    AMediaFormat *f = AMediaFormat_new();
    AMediaFormat_setString(f, AMEDIAFORMAT_KEY_MIME, "audio/mp4a-latm");
    AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_SAMPLE_RATE, sampleRate);
    AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_CHANNEL_COUNT, 1);
    AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_BIT_RATE, bitrate);
    AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_AAC_PROFILE, 2);          // MPEG4AACProfile LC
    AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_MAX_INPUT_SIZE, 16384);
    media_status_t st = AMediaCodec_configure(c, f, NULL, NULL, AMEDIACODEC_CONFIGURE_FLAG_ENCODE);
    AMediaFormat_delete(f);
    if (st != AMEDIA_OK || AMediaCodec_start(c) != AMEDIA_OK) {
        LOGI("voicenotes: AAC encoder setup failed (%d)", (int)st);
        AMediaCodec_delete(c);
        return NULL;
    }
    FILE *file = fopen(path, "wb");
    if (!file) { AMediaCodec_stop(c); AMediaCodec_delete(c); return NULL; }
    Enc *e = calloc(1, sizeof(Enc));
    e->codec = c; e->file = file; e->rate = sampleRate; e->freqIndex = freqIndex(sampleRate);
    return e;
}

int bs_aac_write(void *enc, const int16_t *pcm, int32_t frames) {
    Enc *e = (Enc *)enc;
    if (!e) return -1;
    const uint8_t *src = (const uint8_t *)pcm;
    size_t left = (size_t)frames * 2;
    while (left > 0) {
        ssize_t i = AMediaCodec_dequeueInputBuffer(e->codec, 20000);
        if (i < 0) { drain(e, 0); i = AMediaCodec_dequeueInputBuffer(e->codec, 20000); }
        if (i < 0) return -1;     // encoder stalled: drop this frame
        size_t cap = 0;
        uint8_t *buf = AMediaCodec_getInputBuffer(e->codec, (size_t)i, &cap);
        if (!buf || cap < 2) return -1;
        size_t n = left < cap ? left : (cap & ~(size_t)1);
        memcpy(buf, src, n);
        uint64_t pts = (uint64_t)(e->frames * 1000000 / e->rate);
        AMediaCodec_queueInputBuffer(e->codec, (size_t)i, 0, n, pts, 0);
        e->frames += (int64_t)(n / 2);
        src += n; left -= n;
    }
    int64_t before = e->bytes;
    drain(e, 0);
    if (e->bytes != before) fflush(e->file);
    return 0;
}

int64_t bs_aac_bytes(void *enc) { return enc ? ((Enc *)enc)->bytes : 0; }

void bs_aac_close(void *enc) {
    Enc *e = (Enc *)enc;
    if (!e) return;
    ssize_t i = AMediaCodec_dequeueInputBuffer(e->codec, 50000);
    if (i >= 0) {
        uint64_t pts = (uint64_t)(e->frames * 1000000 / e->rate);
        AMediaCodec_queueInputBuffer(e->codec, (size_t)i, 0, 0, pts, AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM);
        for (int k = 0; k < 40 && !e->eos; k++) drain(e, 10000);      // up to ~0.4 s for the last frames
    }
    AMediaCodec_stop(e->codec);
    AMediaCodec_delete(e->codec);
    fclose(e->file);
    free(e);
}
