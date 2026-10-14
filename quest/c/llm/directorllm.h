// P266 (d): the Director's on-device model (directorllm.c). Loaded at run time with dlopen by DirectorLLM.swift.
#pragma once
#ifdef __cplusplus
extern "C" {
#endif
int dllm_load(const char *path, int n_ctx, int n_threads);
void dllm_unload(void);
int dllm_loaded(void);
int dllm_generate(const char *system, const char *user, const char *grammar, int max_tokens, unsigned seed,
                  char *out, int cap);
void dllm_heartbeat(void);
int dllm_quiet(void);
void dllm_lower_priority(void);
#ifdef __cplusplus
}
#endif
