// Android NDK headers the Quest app uses from Swift (with android_native_app_glue.h, copied here from the NDK by
// quest/tools/build-apk.sh).
#include <android/log.h>
#include <android/native_activity.h>
#include <android/looper.h>
#include <android/asset_manager.h>
#include <aaudio/AAudio.h>
#include <unistd.h>
#include <sys/syscall.h>

// The calling thread's kernel id (gettid() isn't visible to Swift from bionic's headers; syscall is variadic).
static inline unsigned int blocksmith_gettid(void) { return (unsigned int)syscall(__NR_gettid); }
