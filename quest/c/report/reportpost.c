// P480: the in-game bug and idea reporter's HTTPS POST on the Quest, through java.net.HttpURLConnection over JNI (the
// app is a NativeActivity with no Java code; java.* classes load on any attached thread). The receiver (a Google Apps
// Script web app) answers a POST with a 302 whose Location is read with a GET.
#include "reportpost.h"
#include <jni.h>
#include <string.h>
#include <android/log.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "Blocksmith", __VA_ARGS__)

static int cleared(JNIEnv *env) {
    if ((*env)->ExceptionCheck(env)) { (*env)->ExceptionClear(env); return 1; }
    return 0;
}

// Opens `url` as an HttpURLConnection with timeouts and no automatic redirects (NULL on failure).
static jobject open_conn(JNIEnv *env, const char *url) {
    jclass cURL = (*env)->FindClass(env, "java/net/URL");
    if (cleared(env) || !cURL) return NULL;
    jmethodID init = (*env)->GetMethodID(env, cURL, "<init>", "(Ljava/lang/String;)V");
    jmethodID openC = (*env)->GetMethodID(env, cURL, "openConnection", "()Ljava/net/URLConnection;");
    jstring jurl = (*env)->NewStringUTF(env, url);
    jobject u = (*env)->NewObject(env, cURL, init, jurl);
    (*env)->DeleteLocalRef(env, jurl);
    if (cleared(env) || !u) return NULL;
    jobject c = (*env)->CallObjectMethod(env, u, openC);
    (*env)->DeleteLocalRef(env, u);
    (*env)->DeleteLocalRef(env, cURL);
    if (cleared(env) || !c) return NULL;
    jclass cH = (*env)->FindClass(env, "java/net/HttpURLConnection");
    if (cleared(env) || !cH) return NULL;
    (*env)->CallVoidMethod(env, c, (*env)->GetMethodID(env, cH, "setConnectTimeout", "(I)V"), 15000);
    (*env)->CallVoidMethod(env, c, (*env)->GetMethodID(env, cH, "setReadTimeout", "(I)V"), 20000);
    (*env)->CallVoidMethod(env, c, (*env)->GetMethodID(env, cH, "setInstanceFollowRedirects", "(Z)V"), JNI_FALSE);
    (*env)->DeleteLocalRef(env, cH);
    if (cleared(env)) return NULL;
    return c;
}

static void set_string(JNIEnv *env, jobject c, const char *method, const char *a, const char *b) {
    jclass cH = (*env)->FindClass(env, "java/net/HttpURLConnection");
    jstring ja = (*env)->NewStringUTF(env, a);
    if (b) {
        jstring jb = (*env)->NewStringUTF(env, b);
        (*env)->CallVoidMethod(env, c, (*env)->GetMethodID(env, cH, method, "(Ljava/lang/String;Ljava/lang/String;)V"), ja, jb);
        (*env)->DeleteLocalRef(env, jb);
    } else {
        (*env)->CallVoidMethod(env, c, (*env)->GetMethodID(env, cH, method, "(Ljava/lang/String;)V"), ja);
    }
    cleared(env);
    (*env)->DeleteLocalRef(env, ja);
    (*env)->DeleteLocalRef(env, cH);
}

// The reply body (or the error body) into out; returns the bytes read.
static int read_body(JNIEnv *env, jobject c, int status, char *out, int outLen) {
    jclass cH = (*env)->FindClass(env, "java/net/HttpURLConnection");
    jobject in = (*env)->CallObjectMethod(env, c, (*env)->GetMethodID(env, cH, status < 400 ? "getInputStream" : "getErrorStream",
                                                                      "()Ljava/io/InputStream;"));
    (*env)->DeleteLocalRef(env, cH);
    if (cleared(env) || !in) return 0;
    jclass cIn = (*env)->FindClass(env, "java/io/InputStream");
    jmethodID readM = (*env)->GetMethodID(env, cIn, "read", "([B)I");
    jbyteArray buf = (*env)->NewByteArray(env, 1024);
    int n = 0;
    while (n < outLen - 1) {
        jint got = (*env)->CallIntMethod(env, in, readM, buf);
        if (cleared(env) || got <= 0) break;
        if (got > outLen - 1 - n) got = outLen - 1 - n;
        (*env)->GetByteArrayRegion(env, buf, 0, got, (jbyte *)(out + n));
        n += got;
    }
    out[n] = 0;
    (*env)->CallVoidMethod(env, in, (*env)->GetMethodID(env, cIn, "close", "()V"));
    cleared(env);
    (*env)->DeleteLocalRef(env, buf);
    (*env)->DeleteLocalRef(env, cIn);
    (*env)->DeleteLocalRef(env, in);
    return n;
}

static int status_of(JNIEnv *env, jobject c) {
    jclass cH = (*env)->FindClass(env, "java/net/HttpURLConnection");
    jint s = (*env)->CallIntMethod(env, c, (*env)->GetMethodID(env, cH, "getResponseCode", "()I"));
    (*env)->DeleteLocalRef(env, cH);
    return cleared(env) ? -1 : s;
}

// The Location header of a redirect, into loc (0: none).
static int location(JNIEnv *env, jobject c, char *loc, int len) {
    jclass cH = (*env)->FindClass(env, "java/net/HttpURLConnection");
    jstring key = (*env)->NewStringUTF(env, "Location");
    jstring v = (jstring)(*env)->CallObjectMethod(env, c, (*env)->GetMethodID(env, cH, "getHeaderField", "(Ljava/lang/String;)Ljava/lang/String;"), key);
    (*env)->DeleteLocalRef(env, key);
    (*env)->DeleteLocalRef(env, cH);
    if (cleared(env) || !v) return 0;
    const char *s = (*env)->GetStringUTFChars(env, v, NULL);
    int ok = s && strncmp(s, "https://", 8) == 0 && (int)strlen(s) < len;
    if (ok) strcpy(loc, s);
    if (s) (*env)->ReleaseStringUTFChars(env, v, s);
    (*env)->DeleteLocalRef(env, v);
    return ok;
}

static void disconnect(JNIEnv *env, jobject c) {
    jclass cH = (*env)->FindClass(env, "java/net/HttpURLConnection");
    (*env)->CallVoidMethod(env, c, (*env)->GetMethodID(env, cH, "disconnect", "()V"));
    cleared(env);
    (*env)->DeleteLocalRef(env, cH);
    (*env)->DeleteLocalRef(env, c);
}

int bs_report_post(ANativeActivity *a, const char *url, const char *json, char *out, int outLen) {
    if (outLen > 0) out[0] = 0;
    JNIEnv *env = NULL;
    int attached = 0;
    jint r = (*a->vm)->GetEnv(a->vm, (void **)&env, JNI_VERSION_1_6);
    if (r == JNI_EDETACHED) {
        if ((*a->vm)->AttachCurrentThread(a->vm, &env, NULL) != JNI_OK) return -1;
        attached = 1;
    } else if (r != JNI_OK) return -1;
    (*env)->PushLocalFrame(env, 64);
    int status = -1;
    jobject c = open_conn(env, url);
    if (c) {
        set_string(env, c, "setRequestMethod", "POST", NULL);
        set_string(env, c, "setRequestProperty", "Content-Type", "application/json");
        jclass cH = (*env)->FindClass(env, "java/net/HttpURLConnection");
        (*env)->CallVoidMethod(env, c, (*env)->GetMethodID(env, cH, "setDoOutput", "(Z)V"), JNI_TRUE);
        cleared(env);
        jobject os = (*env)->CallObjectMethod(env, c, (*env)->GetMethodID(env, cH, "getOutputStream", "()Ljava/io/OutputStream;"));
        (*env)->DeleteLocalRef(env, cH);
        if (!cleared(env) && os) {
            jsize n = (jsize)strlen(json);
            jbyteArray b = (*env)->NewByteArray(env, n);
            (*env)->SetByteArrayRegion(env, b, 0, n, (const jbyte *)json);
            jclass cOs = (*env)->FindClass(env, "java/io/OutputStream");
            (*env)->CallVoidMethod(env, os, (*env)->GetMethodID(env, cOs, "write", "([B)V"), b);
            (*env)->CallVoidMethod(env, os, (*env)->GetMethodID(env, cOs, "close", "()V"));
            (*env)->DeleteLocalRef(env, cOs);
            (*env)->DeleteLocalRef(env, b);
            (*env)->DeleteLocalRef(env, os);
            if (!cleared(env)) status = status_of(env, c);
        }
        // The reply is behind the redirect: GET the Location (up to 3 hops).
        char loc[2048];
        for (int hop = 0; hop < 3 && (status == 301 || status == 302 || status == 303 || status == 307 || status == 308); hop++) {
            if (!location(env, c, loc, sizeof loc)) break;
            disconnect(env, c);
            c = open_conn(env, loc);
            if (!c) { status = -1; break; }
            status = status_of(env, c);
        }
        if (c) {
            if (status > 0) read_body(env, c, status, out, outLen);
            disconnect(env, c);
        }
    }
    (*env)->PopLocalFrame(env, NULL);
    LOGI("report: HTTP %d", status);
    if (attached) (*a->vm)->DetachCurrentThread(a->vm);
    return status;
}
