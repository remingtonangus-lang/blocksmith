// Per-thread heap allocation counter for questcheck (glibc, LD_PRELOAD): counts malloc / calloc / realloc / memalign
// calls on the calling thread; questcheck looks up bs_alloc_count to report allocations per game tick and per frame.
//   clang -O2 -shared -fPIC quest/tools/alloccount.c -o build/quest-linux/alloccount.so
//   LD_PRELOAD=build/quest-linux/alloccount.so build/quest-linux/questcheck ...
#include <stddef.h>
extern void *__libc_malloc(size_t);
extern void *__libc_calloc(size_t, size_t);
extern void *__libc_realloc(void *, size_t);
extern void *__libc_memalign(size_t, size_t);
static __thread long count __attribute__((tls_model("initial-exec")));
long bs_alloc_count(void) { return count; }
static void rec(void);
void *malloc(size_t n) { count++; rec(); return __libc_malloc(n); }
void *calloc(size_t a, size_t b) { count++; rec(); return __libc_calloc(a, b); }
void *realloc(void *p, size_t n) { count++; rec(); return __libc_realloc(p, n); }
void *memalign(size_t a, size_t n) { count++; rec(); return __libc_memalign(a, n); }
void *aligned_alloc(size_t a, size_t n) { count++; rec(); return __libc_memalign(a, n); }
int posix_memalign(void **out, size_t a, size_t n) { count++; rec(); void *p = __libc_memalign(a, n); if (!p) return 12; *out = p; return 0; }

// Tracing (profiling only): while armed on a thread, each allocation's call stack (12 frames) is recorded; dump writes
// them with /proc/self/maps for llvm-symbolizer (quest/tools/alloctrace.py).
#include <execinfo.h>
#include <stdio.h>
#include <string.h>
#define TR_MAX 8192
#define TR_DEPTH 12
static void *trace[TR_MAX][TR_DEPTH];
static int traceN;
static __thread int armed __attribute__((tls_model("initial-exec")));
static __thread int inside __attribute__((tls_model("initial-exec")));
void bs_alloc_arm(int on) { if (on) { void *b[2]; backtrace(b, 2); } armed = on; }
static void rec(void) {
    if (!armed || inside || traceN >= TR_MAX) return;
    inside = 1;
    void *b[TR_DEPTH + 2];
    int n = backtrace(b, TR_DEPTH + 2);
    memset(trace[traceN], 0, sizeof(trace[0]));
    for (int i = 2; i < n; i++) trace[traceN][i - 2] = b[i];
    traceN++;
    inside = 0;
}
void bs_alloc_dump(const char *path) {
    inside = 1;
    FILE *f = fopen(path, "w");
    if (!f) { inside = 0; return; }
    FILE *m = fopen("/proc/self/maps", "r");
    char line[512];
    while (m && fgets(line, sizeof line, m)) fprintf(f, "M %s", line);
    if (m) fclose(m);
    for (int i = 0; i < traceN; i++) {
        fprintf(f, "T");
        for (int k = 0; k < TR_DEPTH && trace[i][k]; k++) fprintf(f, " %p", trace[i][k]);
        fprintf(f, "\n");
    }
    fclose(f);
    traceN = 0;
    inside = 0;
}
