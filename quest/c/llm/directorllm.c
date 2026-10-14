// P266 (d): the Director's on-device language model, a thin C layer over llama.cpp. Built for Android arm64 by
// quest/tools/build-director-llm.sh into libdirectorllm.so (llama.cpp linked in statically); the game loads it at run
// time with dlopen (DirectorLLM.swift), so a build or a headset without it still plays (the rules director takes over).
//
// It never costs a frame: the game calls dllm_heartbeat() every frame of active play, and generation only runs while
// no heartbeat came for QUIET_MS (paused, a menu open, asleep, loading, idle in a safe place, the app in the
// background). A heartbeat during generation aborts it within one token (and inside a decode, through llama.cpp's
// abort callback); the game simply asks again at the next quiet moment. The worker thread lowers its own priority.
//
// API (all return < 0 on failure):
//   dllm_load(path, n_ctx, n_threads)    load a GGUF model (mmap, CPU only)
//   dllm_generate(system, user, grammar, max_tokens, seed, out, cap)
//                                        chat-formats the prompt with the model's own template, samples under the GBNF
//                                        grammar, writes the reply (NUL-terminated) to out; -2 when aborted, -3 too long
//   dllm_unload()                        frees the model (memory pressure, the Director switched off)
//   dllm_heartbeat(), dllm_quiet()       the frame heartbeat; 1 when generation may run
//   dllm_lower_priority()                nice +10 for the calling thread
#define _GNU_SOURCE
#include "directorllm.h"
#include "llama.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/resource.h>
#include <sys/syscall.h>

#define QUIET_MS 300

static struct llama_model *g_model = NULL;
static struct llama_context *g_ctx = NULL;
static _Atomic long long g_beat = 0;
static int g_backend = 0;

static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

void dllm_heartbeat(void) { atomic_store(&g_beat, now_ms()); }
int dllm_quiet(void) { return now_ms() - atomic_load(&g_beat) > QUIET_MS; }

static bool abort_cb(void *data) { (void)data; return !dllm_quiet(); }

void dllm_lower_priority(void) {
#ifdef SYS_gettid
    setpriority(PRIO_PROCESS, (id_t)syscall(SYS_gettid), 10);
#endif
}

static void quiet_log(enum ggml_log_level level, const char *text, void *data) { (void)level; (void)text; (void)data; }

int dllm_load(const char *path, int n_ctx, int n_threads) {
    if (g_model) return 0;
    if (!g_backend) { llama_log_set(quiet_log, NULL); llama_backend_init(); g_backend = 1; }
    struct llama_model_params mp = llama_model_default_params();
    mp.n_gpu_layers = 0;
    g_model = llama_model_load_from_file(path, mp);
    if (!g_model) return -1;
    struct llama_context_params cp = llama_context_default_params();
    cp.n_ctx = (uint32_t)n_ctx;
    cp.n_batch = (uint32_t)n_ctx;
    cp.n_threads = n_threads;
    cp.n_threads_batch = n_threads;
    cp.abort_callback = abort_cb;
    cp.abort_callback_data = NULL;
    g_ctx = llama_init_from_model(g_model, cp);
    if (!g_ctx) { llama_model_free(g_model); g_model = NULL; return -1; }
    return 0;
}

void dllm_unload(void) {
    if (g_ctx) { llama_free(g_ctx); g_ctx = NULL; }
    if (g_model) { llama_model_free(g_model); g_model = NULL; }
}

int dllm_loaded(void) { return g_model != NULL; }

int dllm_generate(const char *system, const char *user, const char *grammar, int max_tokens, unsigned seed,
                  char *out, int cap) {
    if (!g_model || !g_ctx || cap < 2) return -1;
    out[0] = 0;
    const struct llama_vocab *vocab = llama_model_get_vocab(g_model);
    // The prompt in the model's own chat format.
    llama_chat_message msgs[2] = { { "system", system }, { "user", user } };
    const char *tmpl = llama_model_chat_template(g_model, NULL);
    int plen = (int)(strlen(system) + strlen(user)) * 2 + 256;
    char *prompt = (char *)malloc((size_t)plen);
    if (!prompt) return -1;
    int n = llama_chat_apply_template(tmpl, msgs, 2, true, prompt, plen);
    if (n > plen) {
        char *bigger = (char *)realloc(prompt, (size_t)n + 1);
        if (!bigger) { free(prompt); return -1; }
        prompt = bigger; plen = n + 1;
        n = llama_chat_apply_template(tmpl, msgs, 2, true, prompt, plen);
    }
    if (n < 0) { free(prompt); return -1; }
    prompt[n < plen ? n : plen - 1] = 0;
    int nt = -llama_tokenize(vocab, prompt, n, NULL, 0, true, true);
    if (nt <= 0 || nt + max_tokens > (int)llama_n_ctx(g_ctx)) { free(prompt); return -3; }
    llama_token *toks = (llama_token *)malloc(sizeof(llama_token) * (size_t)nt);
    if (!toks) { free(prompt); return -1; }
    llama_tokenize(vocab, prompt, n, toks, nt, true, true);
    free(prompt);
    llama_memory_clear(llama_get_memory(g_ctx), true);

    struct llama_sampler *smpl = llama_sampler_chain_init(llama_sampler_chain_default_params());
    struct llama_sampler *gram = grammar && grammar[0] ? llama_sampler_init_grammar(vocab, grammar, "root") : NULL;
    if (grammar && grammar[0] && !gram) { llama_sampler_free(smpl); free(toks); return -1; }
    if (gram) llama_sampler_chain_add(smpl, gram);
    llama_sampler_chain_add(smpl, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.92f, 1));
    llama_sampler_chain_add(smpl, llama_sampler_init_temp(0.8f));
    llama_sampler_chain_add(smpl, llama_sampler_init_dist(seed));

    int len = 0, rc = 0;
    struct llama_batch batch = llama_batch_get_one(toks, nt);
    llama_token tok = 0;
    for (int i = 0; i < max_tokens; i++) {
        if (!dllm_quiet()) { rc = -2; break; }
        int d = llama_decode(g_ctx, batch);
        if (d != 0) { rc = d == 2 ? -2 : -1; break; }      // 2: aborted by the heartbeat
        tok = llama_sampler_sample(smpl, g_ctx, -1);
        if (llama_vocab_is_eog(vocab, tok)) break;
        char piece[64];
        int pl = llama_token_to_piece(vocab, tok, piece, (int)sizeof piece, 0, false);
        if (pl < 0) { rc = -1; break; }
        if (len + pl >= cap) { rc = -3; break; }
        memcpy(out + len, piece, (size_t)pl);
        len += pl;
        out[len] = 0;
        batch = llama_batch_get_one(&tok, 1);
    }
    llama_sampler_free(smpl);
    free(toks);
    return rc < 0 ? rc : len;
}
