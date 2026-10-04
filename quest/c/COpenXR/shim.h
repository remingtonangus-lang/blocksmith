// OpenXR with the Vulkan graphics binding (and the Android platform structs on Android). The openxr/*.h headers come
// from the Khronos loader AAR (quest/tools/fetch-deps.sh) and are found through -I.
#if defined(__ANDROID__)
#define XR_USE_PLATFORM_ANDROID 1
#include <jni.h>
#endif
#define XR_USE_GRAPHICS_API_VULKAN 1
#include <vulkan/vulkan.h>
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>
