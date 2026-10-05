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
void *malloc(size_t n) { count++; return __libc_malloc(n); }
void *calloc(size_t a, size_t b) { count++; return __libc_calloc(a, b); }
void *realloc(void *p, size_t n) { count++; return __libc_realloc(p, n); }
void *memalign(size_t a, size_t n) { count++; return __libc_memalign(a, n); }
void *aligned_alloc(size_t a, size_t n) { count++; return __libc_memalign(a, n); }
int posix_memalign(void **out, size_t a, size_t n) { count++; void *p = __libc_memalign(a, n); if (!p) return 12; *out = p; return 0; }
