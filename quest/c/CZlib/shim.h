#include <zlib.h>
#include <stdint.h>
#include <stdbool.h>

// Ledger 128 (Sources/WeakLink.swift): one compare-and-swap and one load on a 64-bit word, here because every Quest
// and host build already imports this header and Swift has no atomics without another library in the APK.
static inline bool bs_cas64(void *word, uint64_t expected, uint64_t desired) {
    return __atomic_compare_exchange_n((uint64_t *)word, &expected, desired, false, __ATOMIC_SEQ_CST, __ATOMIC_RELAXED);
}
static inline uint64_t bs_load64(const void *word) { return __atomic_load_n((const uint64_t *)word, __ATOMIC_RELAXED); }
