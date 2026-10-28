// P480: the in-game bug and idea reporter's HTTPS POST on the Quest (java.net through JNI; the app has no Java code).
#include <android/native_activity.h>

// Blocking (call it off the game thread): POSTs `json` to `url`, follows up to 3 redirects with a GET and copies the
// reply body (cut to outLen - 1 bytes) into `out`. Returns the final HTTP status, or -1 when nothing came back.
int bs_report_post(ANativeActivity *activity, const char *url, const char *json, char *out, int outLen);
