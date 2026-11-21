// Video for the Quest's voice bug notes (P368; dev builds only: quest/tools/build-apk.sh copies this into the
// CAndroidGlue module unless STORE=1). The game hands in a small NV12 picture of the left eye about 30 times a second
// (QuestVideoNotes.swift); the hardware H.264 encoder turns it into packets kept in memory for the last ~10 s (from a
// keyframe on). Nothing touches storage until a clip begins: then the buffered packets go into an MP4 (AMediaMuxer)
// and every new packet follows until the clip ends. All calls come from one serial queue.
#include "voicevideo.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <media/NdkMediaCodec.h>
#include <media/NdkMediaFormat.h>
#include <media/NdkMediaMuxer.h>
#include <android/log.h>
#include <pthread.h>
#include <stdatomic.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "blocksmith", __VA_ARGS__)

typedef struct {
    uint8_t *data;
    int32_t size;
    int64_t pts;            // microseconds
    int key;
} Pkt;

#define RING 1024           // packets kept at most (34 s at 30 fps)

typedef struct {
    AMediaCodec *codec;
    AMediaFormat *outFormat;    // the encoder's output format (SPS/PPS), for the muxer's track
    int32_t w, h, stride, slice;
    int64_t window;             // microseconds of packets kept
    Pkt ring[RING];
    int head, count;            // oldest at head
    int64_t ringBytes;
    AMediaMuxer *mux;
    FILE *file;
    ssize_t track;
    int64_t base, last;         // the clip's first pts, the last pts written
    int64_t clipBytes;
    // Ledger 406: the sound (AAC, game mix + microphone), its packets kept like the pictures'.
    AMediaCodec *acodec;
    AMediaFormat *aformat;
    int32_t arate;
    int64_t aNext;              // pts of the next sample fed to the encoder (-1: not started)
    Pkt aring[RING * 2];
    int ahead, acount;
    ssize_t atrack;
    int64_t alast;
} VEnc;

// MARK: sound in (ledger 406)

#define GRING (48000 * 2 * 4)               // game ring: 4 s of interleaved stereo
#define MRING (48000 * 4)                   // microphone ring: 4 s mono
static float gRing[GRING];
static atomic_long gWrite = 0, gRead = 0;   // samples (floats) ever written / read
static atomic_llong gPts0 = -1;             // pts of the sample at gRing index 0 of the stream (gWrite counts from it)
static atomic_int gRate = 0;
static atomic_int audioOn = 0;
static atomic_flag gBusy = ATOMIC_FLAG_INIT;
static int16_t mRing[MRING];
static atomic_llong mTotal = 0;             // microphone samples ever written
static atomic_llong mPtsEnd = -1;           // pts just past the last microphone sample
static atomic_int mRate = 0;
static pthread_mutex_t mLock = PTHREAD_MUTEX_INITIALIZER;

void bs_vaudio_enable(int on) { atomic_store(&audioOn, on); }

void bs_vaudio_game(const float *lr, int32_t frames, int32_t rate, int64_t ptsUs) {
    if (!atomic_load(&audioOn) || frames <= 0 || rate <= 0) return;
    if (atomic_flag_test_and_set(&gBusy)) return;
    long w = atomic_load(&gWrite), r = atomic_load(&gRead);
    if (atomic_load(&gPts0) < 0 || atomic_load(&gRate) != rate) {
        atomic_store(&gRate, rate); atomic_store(&gPts0, ptsUs); w = 0; r = 0;
        atomic_store(&gRead, 0);
    } else {
        // a gap (the stream paused or restarted): start the stream's clock again from here
        int64_t expect = atomic_load(&gPts0) + (int64_t)(w / 2) * 1000000 / rate;
        if (ptsUs - expect > 250000 || expect - ptsUs > 250000) {
            atomic_store(&gPts0, ptsUs - (int64_t)(w / 2) * 1000000 / rate);
        }
    }
    long n = (long)frames * 2;
    if (w + n - r > GRING) { atomic_flag_clear(&gBusy); return; }     // (the queue is behind: dropped)
    for (long i = 0; i < n; i++) gRing[(w + i) % GRING] = lr[i];
    atomic_store(&gWrite, w + n);
    atomic_flag_clear(&gBusy);
}

void bs_vaudio_mic(const int16_t *pcm, int32_t frames, int32_t rate, int64_t ptsUs) {
    if (!atomic_load(&audioOn) || frames <= 0 || rate <= 0) return;
    pthread_mutex_lock(&mLock);
    long long t = atomic_load(&mTotal);
    if (atomic_load(&mRate) != rate) { atomic_store(&mRate, rate); t = 0; }
    for (int32_t i = 0; i < frames; i++) mRing[(t + i) % MRING] = pcm[i];
    atomic_store(&mTotal, t + frames);
    atomic_store(&mPtsEnd, ptsUs + (int64_t)frames * 1000000 / rate);
    pthread_mutex_unlock(&mLock);
}

// The microphone at wall-clock time t (0 when it has nothing there).
static float micAt(int64_t t, long long total, int64_t end, int rate) {
    if (rate <= 0 || end < 0) return 0;
    long long back = (end - t) * rate / 1000000;
    if (back < 1 || back > total || back >= MRING - rate / 10) return 0;
    return (float)mRing[(total - back) % MRING] / 32768.0f;
}

static void dropOldest(VEnc *e) {
    Pkt *p = &e->ring[e->head];
    e->ringBytes -= p->size;
    free(p->data);
    p->data = NULL;
    e->head = (e->head + 1) % RING;
    e->count--;
}

// Keep at least `window` behind the newest packet, starting at a keyframe: drop a whole group of pictures once the
// keyframe after it is itself old enough.
static void prune(VEnc *e) {
    if (e->count == RING) dropOldest(e);
    if (e->count < 2) return;
    int64_t newest = e->ring[(e->head + e->count - 1) % RING].pts;
    for (;;) {
        int next = -1;
        for (int k = 1; k < e->count; k++) {
            if (e->ring[(e->head + k) % RING].key) { next = k; break; }
        }
        if (next < 0 || e->ring[(e->head + next) % RING].pts > newest - e->window) break;
        for (int k = 0; k < next; k++) dropOldest(e);
    }
    while (e->count > 0 && !e->ring[e->head].key) dropOldest(e);     // never start on a partial group
}

static void writePkt(VEnc *e, const uint8_t *data, int32_t size, int64_t pts, int key) {
    if (!e->mux || e->track < 0) return;
    if (e->base < 0) {
        if (!key) return;            // a clip opens on a keyframe
        e->base = pts;
    }
    int64_t t = pts - e->base;
    if (t <= e->last) t = e->last + 1;
    e->last = t;
    AMediaCodecBufferInfo info = { .offset = 0, .size = size, .presentationTimeUs = t,
                                   .flags = key ? AMEDIACODEC_BUFFER_FLAG_KEY_FRAME : 0 };
    if (AMediaMuxer_writeSampleData(e->mux, (size_t)e->track, data, &info) == AMEDIA_OK) e->clipBytes += size;
}

static void drain(VEnc *e) {
    for (;;) {
        AMediaCodecBufferInfo info;
        ssize_t i = AMediaCodec_dequeueOutputBuffer(e->codec, &info, 0);
        if (i == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED) {
            if (e->outFormat) AMediaFormat_delete(e->outFormat);
            e->outFormat = AMediaCodec_getOutputFormat(e->codec);
            continue;
        }
        if (i == AMEDIACODEC_INFO_OUTPUT_BUFFERS_CHANGED) continue;
        if (i < 0) return;
        size_t cap = 0;
        uint8_t *buf = AMediaCodec_getOutputBuffer(e->codec, (size_t)i, &cap);
        if (buf && info.size > 0 && !(info.flags & AMEDIACODEC_BUFFER_FLAG_CODEC_CONFIG)) {
            int key = (info.flags & AMEDIACODEC_BUFFER_FLAG_KEY_FRAME) != 0;
            uint8_t *copy = malloc((size_t)info.size);
            if (copy) {
                memcpy(copy, buf + info.offset, (size_t)info.size);
                if (e->count == RING) dropOldest(e);
                Pkt *p = &e->ring[(e->head + e->count) % RING];
                p->data = copy; p->size = info.size; p->pts = info.presentationTimeUs; p->key = key;
                e->count++;
                e->ringBytes += info.size;
                writePkt(e, copy, info.size, info.presentationTimeUs, key);
                prune(e);
            }
        }
        AMediaCodec_releaseOutputBuffer(e->codec, (size_t)i, false);
    }
}

// MARK: sound out (ledger 406)

static void aDropOldest(VEnc *e) {
    Pkt *p = &e->aring[e->ahead];
    e->ringBytes -= p->size;
    free(p->data); p->data = NULL;
    e->ahead = (e->ahead + 1) % (RING * 2);
    e->acount--;
}

static void writeAudio(VEnc *e, const uint8_t *data, int32_t size, int64_t pts) {
    if (!e->mux || e->atrack < 0 || e->base < 0) return;           // (the clip starts with its first picture)
    int64_t t = pts - e->base;
    if (t < 0) return;
    if (t <= e->alast) t = e->alast + 1;
    e->alast = t;
    AMediaCodecBufferInfo info = { .offset = 0, .size = size, .presentationTimeUs = t, .flags = 0 };
    if (AMediaMuxer_writeSampleData(e->mux, (size_t)e->atrack, data, &info) == AMEDIA_OK) e->clipBytes += size;
}

static void aDrain(VEnc *e) {
    for (;;) {
        AMediaCodecBufferInfo info;
        ssize_t i = AMediaCodec_dequeueOutputBuffer(e->acodec, &info, 0);
        if (i == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED) {
            if (e->aformat) AMediaFormat_delete(e->aformat);
            e->aformat = AMediaCodec_getOutputFormat(e->acodec);
            continue;
        }
        if (i == AMEDIACODEC_INFO_OUTPUT_BUFFERS_CHANGED) continue;
        if (i < 0) return;
        size_t cap = 0;
        uint8_t *buf = AMediaCodec_getOutputBuffer(e->acodec, (size_t)i, &cap);
        if (buf && info.size > 0 && !(info.flags & AMEDIACODEC_BUFFER_FLAG_CODEC_CONFIG)) {
            uint8_t *copy = malloc((size_t)info.size);
            if (copy) {
                memcpy(copy, buf + info.offset, (size_t)info.size);
                if (e->acount == RING * 2) aDropOldest(e);
                Pkt *p = &e->aring[(e->ahead + e->acount) % (RING * 2)];
                p->data = copy; p->size = info.size; p->pts = info.presentationTimeUs; p->key = 1;
                e->acount++;
                e->ringBytes += info.size;
                writeAudio(e, copy, info.size, info.presentationTimeUs);
                // keep the sound from the oldest picture kept on
                int64_t oldest = e->count > 0 ? e->ring[e->head].pts : info.presentationTimeUs;
                while (e->acount > 1 && e->aring[e->ahead].pts < oldest - 100000) aDropOldest(e);
            }
        }
        AMediaCodec_releaseOutputBuffer(e->acodec, (size_t)i, false);
    }
}

// What the game played (and the microphone heard) up to 150 ms ago goes to the AAC encoder, mixed, as 16-bit stereo.
static void aPump(VEnc *e, int64_t nowUs) {
    if (!e->acodec) return;
    int rate = atomic_load(&gRate);
    if (rate != e->arate) { atomic_store(&gRead, atomic_load(&gWrite)); e->aNext = -1; return; }   // (another rate: not this encoder's)
    long r = atomic_load(&gRead), w = atomic_load(&gWrite);
    int64_t pts0 = atomic_load(&gPts0);
    if (pts0 < 0 || w <= r) return;
    long long mt; int64_t mend; int mr;
    pthread_mutex_lock(&mLock); mt = atomic_load(&mTotal); mend = atomic_load(&mPtsEnd); mr = atomic_load(&mRate); pthread_mutex_unlock(&mLock);
    for (;;) {
        long avail = w - r;
        int64_t rPts = pts0 + (int64_t)(r / 2) * 1000000 / rate;
        if (avail < 2 || rPts > nowUs - 150000) break;
        ssize_t i = AMediaCodec_dequeueInputBuffer(e->acodec, 0);
        if (i < 0) { aDrain(e); break; }
        size_t cap = 0;
        uint8_t *buf = AMediaCodec_getInputBuffer(e->acodec, (size_t)i, &cap);
        long frames = avail / 2;
        if ((long)(cap / 4) < frames) frames = (long)(cap / 4);
        if (frames > 1024) frames = 1024;
        int16_t *out = (int16_t *)buf;
        for (long f = 0; f < frames; f++) {
            float m = micAt(rPts + (int64_t)f * 1000000 / rate, mt, mend, mr) * 1.6f;
            for (int ch = 0; ch < 2; ch++) {
                float v = gRing[(r + f * 2 + ch) % GRING] + m;
                v = v > 1 ? 1 : (v < -1 ? -1 : v);
                out[f * 2 + ch] = (int16_t)(v * 32767.0f);
            }
        }
        AMediaCodec_queueInputBuffer(e->acodec, (size_t)i, 0, (size_t)frames * 4, (uint64_t)rPts, 0);
        r += frames * 2;
        atomic_store(&gRead, r);
    }
    aDrain(e);
}

static void aOpen(VEnc *e) {
    int rate = atomic_load(&gRate);
    if (rate <= 0) rate = 48000;
    AMediaCodec *c = AMediaCodec_createEncoderByType("audio/mp4a-latm");
    if (!c) { LOGI("voicevideo: no AAC encoder: clips without sound"); return; }
    AMediaFormat *f = AMediaFormat_new();
    AMediaFormat_setString(f, AMEDIAFORMAT_KEY_MIME, "audio/mp4a-latm");
    AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_SAMPLE_RATE, rate);
    AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_CHANNEL_COUNT, 2);
    AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_BIT_RATE, 128000);
    AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_AAC_PROFILE, 2);          // AAC LC
    AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_MAX_INPUT_SIZE, 1024 * 4 * 2);
    media_status_t st = AMediaCodec_configure(c, f, NULL, NULL, AMEDIACODEC_CONFIGURE_FLAG_ENCODE);
    AMediaFormat_delete(f);
    if (st != AMEDIA_OK || AMediaCodec_start(c) != AMEDIA_OK) { LOGI("voicevideo: AAC encoder setup failed (%d)", (int)st); AMediaCodec_delete(c); return; }
    e->acodec = c; e->arate = rate; e->aNext = -1;
    atomic_store(&gRead, atomic_load(&gWrite));
    LOGI("voicevideo: sound %d Hz stereo AAC", rate);
}

void *bs_venc_open(int32_t width, int32_t height, int32_t fps, int32_t bitrate, int32_t keySeconds, int32_t windowSeconds) {
    AMediaCodec *c = AMediaCodec_createEncoderByType("video/avc");
    if (!c) { LOGI("voicevideo: no H.264 encoder"); return NULL; }
    AMediaFormat *f = AMediaFormat_new();
    AMediaFormat_setString(f, AMEDIAFORMAT_KEY_MIME, "video/avc");
    AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_WIDTH, width);
    AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_HEIGHT, height);
    AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_COLOR_FORMAT, 21);       // COLOR_FormatYUV420SemiPlanar (NV12)
    AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_BIT_RATE, bitrate);
    AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_FRAME_RATE, fps);
    AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_I_FRAME_INTERVAL, keySeconds);
    AMediaFormat_setInt32(f, "priority", 1);                            // below realtime: the game's frames come first
    media_status_t st = AMediaCodec_configure(c, f, NULL, NULL, AMEDIACODEC_CONFIGURE_FLAG_ENCODE);
    AMediaFormat_delete(f);
    if (st != AMEDIA_OK || AMediaCodec_start(c) != AMEDIA_OK) {
        LOGI("voicevideo: H.264 encoder setup failed (%d)", (int)st);
        AMediaCodec_delete(c);
        return NULL;
    }
    VEnc *e = calloc(1, sizeof(VEnc));
    e->codec = c; e->w = width; e->h = height; e->stride = width; e->slice = height;
    e->window = (int64_t)windowSeconds * 1000000;
    e->track = -1; e->base = -1; e->atrack = -1;
    aOpen(e);
    // The encoder's own row stride and plane height when it asks for padding.
    AMediaFormat *in = AMediaCodec_getInputFormat(c);
    if (in) {
        int32_t v = 0;
        if (AMediaFormat_getInt32(in, "stride", &v) && v >= width) e->stride = v;
        if (AMediaFormat_getInt32(in, "slice-height", &v) && v >= height) e->slice = v;
        AMediaFormat_delete(in);
    }
    LOGI("voicevideo: encoder %dx%d stride %d slice %d, %d b/s, %d fps", width, height, e->stride, e->slice, bitrate, fps);
    return e;
}

int bs_venc_frame(void *enc, const uint8_t *nv12, int64_t ptsUs) {
    VEnc *e = (VEnc *)enc;
    if (!e) return -1;
    ssize_t i = AMediaCodec_dequeueInputBuffer(e->codec, 0);
    if (i < 0) { drain(e); i = AMediaCodec_dequeueInputBuffer(e->codec, 2000); }
    if (i < 0) return -1;               // the encoder is behind: this picture is dropped
    size_t cap = 0;
    uint8_t *buf = AMediaCodec_getInputBuffer(e->codec, (size_t)i, &cap);
    size_t need = (size_t)e->stride * e->slice + (size_t)e->stride * (e->h / 2);
    if (!buf || cap < need) { AMediaCodec_queueInputBuffer(e->codec, (size_t)i, 0, 0, (uint64_t)ptsUs, 0); return -1; }
    for (int y = 0; y < e->h; y++) memcpy(buf + (size_t)y * e->stride, nv12 + (size_t)y * e->w, (size_t)e->w);
    uint8_t *uv = buf + (size_t)e->stride * e->slice;
    const uint8_t *suv = nv12 + (size_t)e->w * e->h;
    for (int y = 0; y < e->h / 2; y++) memcpy(uv + (size_t)y * e->stride, suv + (size_t)y * e->w, (size_t)e->w);
    AMediaCodec_queueInputBuffer(e->codec, (size_t)i, 0, need, (uint64_t)ptsUs, 0);
    drain(e);
    return 0;
}

#if defined(__aarch64__)
#include <arm_neon.h>
#endif

// Nov 13 (ledger 120, "I want it at max resolution"): RGBA8 rows (rowBytes apart) straight into the encoder's NV12
// input (BT.601, limited range; chroma from each 2x2 block's mean), 8 pixels a step on the headset's NEON. At the full
// eye this is ~3 million pixels a picture: the Swift loop it replaces took a quarter-size picture's 160 thousand.
static void rgbaToNV12(const uint8_t *px, size_t rowBytes, int w, int h, uint8_t *yPlane, uint8_t *uvPlane, size_t stride) {
    for (int y = 0; y < h; y++) {
        const uint8_t *s = px + (size_t)y * rowBytes;
        uint8_t *d = yPlane + (size_t)y * stride;
        int x = 0;
#if defined(__aarch64__)
        const uint8x8_t c66 = vdup_n_u8(66), c129 = vdup_n_u8(129), c25 = vdup_n_u8(25), c16 = vdup_n_u8(16);
        for (; x + 8 <= w; x += 8) {
            uint8x8x4_t p = vld4_u8(s + (size_t)x * 4);
            uint16x8_t t = vmull_u8(p.val[0], c66);
            t = vmlal_u8(t, p.val[1], c129);
            t = vmlal_u8(t, p.val[2], c25);
            vst1_u8(d + x, vadd_u8(vrshrn_n_u16(t, 8), c16));
        }
#endif
        for (; x < w; x++) {
            int r = s[x * 4], g = s[x * 4 + 1], b = s[x * 4 + 2];
            d[x] = (uint8_t)(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
        }
    }
    for (int y = 0; y < h / 2; y++) {
        const uint8_t *a = px + (size_t)(2 * y) * rowBytes, *c = a + rowBytes;
        uint8_t *d = uvPlane + (size_t)y * stride;
        int x = 0;                                  // (chroma samples)
#if defined(__aarch64__)
        const uint8x8_t k112 = vdup_n_u8(112), k38 = vdup_n_u8(38), k74 = vdup_n_u8(74), k94 = vdup_n_u8(94), k18 = vdup_n_u8(18);
        const uint8x8_t lo = vdup_n_u8(16), hi = vdup_n_u8(240);
        const int16x8_t mid = vdupq_n_s16(128);
        for (; x + 8 <= w / 2; x += 8) {
            uint8x16x4_t pa = vld4q_u8(a + (size_t)x * 8), pc = vld4q_u8(c + (size_t)x * 8);
            uint8x8_t r = vrshrn_n_u16(vaddq_u16(vpaddlq_u8(pa.val[0]), vpaddlq_u8(pc.val[0])), 2);
            uint8x8_t g = vrshrn_n_u16(vaddq_u16(vpaddlq_u8(pa.val[1]), vpaddlq_u8(pc.val[1])), 2);
            uint8x8_t b = vrshrn_n_u16(vaddq_u16(vpaddlq_u8(pa.val[2]), vpaddlq_u8(pc.val[2])), 2);
            int16x8_t u = vreinterpretq_s16_u16(vmull_u8(b, k112));
            u = vsubq_s16(u, vreinterpretq_s16_u16(vmull_u8(r, k38)));
            u = vsubq_s16(u, vreinterpretq_s16_u16(vmull_u8(g, k74)));
            int16x8_t v = vreinterpretq_s16_u16(vmull_u8(r, k112));
            v = vsubq_s16(v, vreinterpretq_s16_u16(vmull_u8(g, k94)));
            v = vsubq_s16(v, vreinterpretq_s16_u16(vmull_u8(b, k18)));
            uint8x8x2_t o;
            o.val[0] = vmin_u8(hi, vmax_u8(lo, vqmovun_s16(vaddq_s16(vrshrq_n_s16(u, 8), mid))));
            o.val[1] = vmin_u8(hi, vmax_u8(lo, vqmovun_s16(vaddq_s16(vrshrq_n_s16(v, 8), mid))));
            vst2_u8(d + (size_t)x * 2, o);
        }
#endif
        for (; x < w / 2; x++) {
            int k = x * 8;
            int r = (a[k] + a[k + 4] + c[k] + c[k + 4] + 2) >> 2;
            int g = (a[k + 1] + a[k + 5] + c[k + 1] + c[k + 5] + 2) >> 2;
            int b = (a[k + 2] + a[k + 6] + c[k + 2] + c[k + 6] + 2) >> 2;
            int u = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128, v = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
            d[x * 2] = (uint8_t)(u < 16 ? 16 : (u > 240 ? 240 : u));
            d[x * 2 + 1] = (uint8_t)(v < 16 ? 16 : (v > 240 ? 240 : v));
        }
    }
}

int bs_venc_frame_rgba(void *enc, const uint8_t *rgba, int32_t rowBytes, int64_t ptsUs) {
    VEnc *e = (VEnc *)enc;
    if (!e) return -1;
    ssize_t i = AMediaCodec_dequeueInputBuffer(e->codec, 0);
    if (i < 0) { drain(e); i = AMediaCodec_dequeueInputBuffer(e->codec, 2000); }
    if (i < 0) return -1;               // the encoder is behind: this picture is dropped
    size_t cap = 0;
    uint8_t *buf = AMediaCodec_getInputBuffer(e->codec, (size_t)i, &cap);
    size_t need = (size_t)e->stride * e->slice + (size_t)e->stride * (e->h / 2);
    if (!buf || cap < need) { AMediaCodec_queueInputBuffer(e->codec, (size_t)i, 0, 0, (uint64_t)ptsUs, 0); return -1; }
    rgbaToNV12(rgba, (size_t)rowBytes, e->w, e->h, buf, buf + (size_t)e->stride * e->slice, (size_t)e->stride);
    AMediaCodec_queueInputBuffer(e->codec, (size_t)i, 0, need, (uint64_t)ptsUs, 0);
    drain(e);
    aPump(e, ptsUs);
    return 0;
}

int bs_venc_begin(void *enc, const char *path) {
    VEnc *e = (VEnc *)enc;
    if (!e || !e->outFormat) return -1;
    if (e->mux) bs_venc_end(enc);
    FILE *file = fopen(path, "w+b");
    if (!file) return -1;
    AMediaMuxer *m = AMediaMuxer_new(fileno(file), AMEDIAMUXER_OUTPUT_FORMAT_MPEG_4);
    if (!m) { fclose(file); return -1; }
    ssize_t t = AMediaMuxer_addTrack(m, e->outFormat);
    ssize_t at = e->aformat ? AMediaMuxer_addTrack(m, e->aformat) : -1;          // ledger 406: the sound
    if (t < 0 || AMediaMuxer_start(m) != AMEDIA_OK) { AMediaMuxer_delete(m); fclose(file); return -1; }
    e->mux = m; e->file = file; e->track = t; e->base = -1; e->last = -1; e->clipBytes = 0;
    e->atrack = at; e->alast = -1;
    for (int k = 0; k < e->count; k++) {           // the buffered seconds before the note
        Pkt *p = &e->ring[(e->head + k) % RING];
        writePkt(e, p->data, p->size, p->pts, p->key);
    }
    for (int k = 0; k < e->acount; k++) {
        Pkt *p = &e->aring[(e->ahead + k) % (RING * 2)];
        writeAudio(e, p->data, p->size, p->pts);
    }
    return 0;
}

int64_t bs_venc_end(void *enc) {
    VEnc *e = (VEnc *)enc;
    if (!e || !e->mux) return -1;
    drain(e);
    if (e->base >= 0) AMediaMuxer_stop(e->mux);
    AMediaMuxer_delete(e->mux);
    fclose(e->file);
    e->mux = NULL; e->file = NULL; e->track = -1; e->atrack = -1;
    return e->base >= 0 ? e->clipBytes : 0;
}

int64_t bs_venc_buffered(void *enc) { return enc ? ((VEnc *)enc)->ringBytes : 0; }

void bs_venc_close(void *enc) {
    VEnc *e = (VEnc *)enc;
    if (!e) return;
    if (e->mux) bs_venc_end(enc);
    AMediaCodec_stop(e->codec);
    AMediaCodec_delete(e->codec);
    if (e->outFormat) AMediaFormat_delete(e->outFormat);
    while (e->count > 0) dropOldest(e);
    if (e->acodec) { AMediaCodec_stop(e->acodec); AMediaCodec_delete(e->acodec); }
    if (e->aformat) AMediaFormat_delete(e->aformat);
    while (e->acount > 0) aDropOldest(e);
    free(e);
}
