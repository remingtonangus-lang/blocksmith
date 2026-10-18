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
} VEnc;

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
    e->track = -1; e->base = -1;
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

int bs_venc_begin(void *enc, const char *path) {
    VEnc *e = (VEnc *)enc;
    if (!e || !e->outFormat) return -1;
    if (e->mux) bs_venc_end(enc);
    FILE *file = fopen(path, "w+b");
    if (!file) return -1;
    AMediaMuxer *m = AMediaMuxer_new(fileno(file), AMEDIAMUXER_OUTPUT_FORMAT_MPEG_4);
    if (!m) { fclose(file); return -1; }
    ssize_t t = AMediaMuxer_addTrack(m, e->outFormat);
    if (t < 0 || AMediaMuxer_start(m) != AMEDIA_OK) { AMediaMuxer_delete(m); fclose(file); return -1; }
    e->mux = m; e->file = file; e->track = t; e->base = -1; e->last = -1; e->clipBytes = 0;
    for (int k = 0; k < e->count; k++) {           // the buffered seconds before the note
        Pkt *p = &e->ring[(e->head + k) % RING];
        writePkt(e, p->data, p->size, p->pts, p->key);
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
    e->mux = NULL; e->file = NULL; e->track = -1;
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
    free(e);
}
