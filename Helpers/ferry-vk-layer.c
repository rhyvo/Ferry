
#include <stdint.h>
#include <string.h>

typedef uint32_t VkBool32;
typedef int32_t VkResult;
typedef void (*PFN_vkVoidFunction)(void);
typedef struct VkInstance_T *VkInstance;
typedef struct VkPhysicalDevice_T *VkPhysicalDevice;
typedef struct VkDevice_T *VkDevice;
typedef PFN_vkVoidFunction (*PFN_vkGetInstanceProcAddr)(VkInstance, const char *);
typedef PFN_vkVoidFunction (*PFN_vkGetDeviceProcAddr)(VkDevice, const char *);

enum {
    STYPE_PHYSICAL_DEVICE_FEATURES_2 = 1000059000,
    STYPE_LOADER_INSTANCE_CREATE_INFO = 47,
    STYPE_LOADER_DEVICE_CREATE_INFO = 48,
    LAYER_LINK_INFO = 0,
    VK_ERROR_INITIALIZATION_FAILED = -3,
};

#define FEATURE_COUNT 55
#define GEOMETRY_SHADER 4
#define CULL_DISTANCE 38

typedef struct { int32_t sType; void *pNext; } BaseStructure;
typedef struct { int32_t sType; void *pNext; VkBool32 features[FEATURE_COUNT]; } Features2;
typedef struct {
    int32_t sType; const void *pNext; uint32_t flags, queueCreateInfoCount; const void *pQueueCreateInfos;
    uint32_t enabledLayerCount; const char *const *ppEnabledLayerNames;
    uint32_t enabledExtensionCount; const char *const *ppEnabledExtensionNames;
    const VkBool32 *pEnabledFeatures;
} DeviceCreateInfo;

typedef struct InstanceLink { struct InstanceLink *pNext; PFN_vkGetInstanceProcAddr nextGetInstanceProcAddr; void *nextGetPhysicalDeviceProcAddr; } InstanceLink;
typedef struct { int32_t sType; const void *pNext; int32_t function; InstanceLink *link; } InstanceChainInfo;
typedef struct DeviceLink { struct DeviceLink *pNext; PFN_vkGetInstanceProcAddr nextGetInstanceProcAddr; PFN_vkGetDeviceProcAddr nextGetDeviceProcAddr; } DeviceLink;
typedef struct { int32_t sType; const void *pNext; int32_t function; DeviceLink *link; } DeviceChainInfo;

#define EXPORT __attribute__((visibility("default")))

static PFN_vkGetInstanceProcAddr nextInstanceProcAddr;
static PFN_vkGetDeviceProcAddr nextDeviceProcAddr;
static VkInstance lastInstance;

static void hide(VkBool32 *features) {
    features[GEOMETRY_SHADER] = 0;
    features[CULL_DISTANCE] = 0;
}

typedef VkResult (*PFN_CreateInstance)(const void *, const void *, VkInstance *);
static VkResult createInstance(const void *info, const void *allocator, VkInstance *out) {
    InstanceChainInfo *chain = (InstanceChainInfo *)((const BaseStructure *)info)->pNext;
    while (chain && !(chain->sType == STYPE_LOADER_INSTANCE_CREATE_INFO && chain->function == LAYER_LINK_INFO))
        chain = (InstanceChainInfo *)chain->pNext;
    if (!chain || !chain->link) return VK_ERROR_INITIALIZATION_FAILED;
    nextInstanceProcAddr = chain->link->nextGetInstanceProcAddr;
    chain->link = chain->link->pNext;
    PFN_CreateInstance next = (PFN_CreateInstance)nextInstanceProcAddr(NULL, "vkCreateInstance");
    if (!next) return VK_ERROR_INITIALIZATION_FAILED;
    VkResult result = next(info, allocator, out);
    if (result == 0) lastInstance = *out;
    return result;
}

typedef void (*PFN_GetFeatures)(VkPhysicalDevice, VkBool32 *);
static void getFeatures(VkPhysicalDevice gpu, VkBool32 *features) {
    PFN_GetFeatures next = (PFN_GetFeatures)nextInstanceProcAddr(lastInstance, "vkGetPhysicalDeviceFeatures");
    if (next) next(gpu, features);
    hide(features);
}

typedef void (*PFN_GetFeatures2)(VkPhysicalDevice, Features2 *);
static void getFeatures2(VkPhysicalDevice gpu, Features2 *features) {
    PFN_GetFeatures2 next = (PFN_GetFeatures2)nextInstanceProcAddr(lastInstance, "vkGetPhysicalDeviceFeatures2");
    if (!next) next = (PFN_GetFeatures2)nextInstanceProcAddr(lastInstance, "vkGetPhysicalDeviceFeatures2KHR");
    if (next) next(gpu, features);
    hide(features->features);
}

typedef VkResult (*PFN_CreateDevice)(VkPhysicalDevice, const void *, const void *, VkDevice *);
static VkResult createDevice(VkPhysicalDevice gpu, const void *info, const void *allocator, VkDevice *out) {
    DeviceChainInfo *chain = (DeviceChainInfo *)((const BaseStructure *)info)->pNext;
    while (chain && !(chain->sType == STYPE_LOADER_DEVICE_CREATE_INFO && chain->function == LAYER_LINK_INFO))
        chain = (DeviceChainInfo *)chain->pNext;
    if (!chain || !chain->link) return VK_ERROR_INITIALIZATION_FAILED;
    PFN_vkGetInstanceProcAddr instanceProcAddr = chain->link->nextGetInstanceProcAddr;
    nextDeviceProcAddr = chain->link->nextGetDeviceProcAddr;
    chain->link = chain->link->pNext;
    PFN_CreateDevice next = (PFN_CreateDevice)instanceProcAddr(lastInstance, "vkCreateDevice");
    if (!next) return VK_ERROR_INITIALIZATION_FAILED;

    DeviceCreateInfo copy = *(const DeviceCreateInfo *)info;
    VkBool32 plain[FEATURE_COUNT];
    if (copy.pEnabledFeatures) {
        memcpy(plain, copy.pEnabledFeatures, sizeof plain);
        hide(plain);
        copy.pEnabledFeatures = plain;
    }
    for (BaseStructure *s = (BaseStructure *)copy.pNext; s; s = (BaseStructure *)s->pNext)
        if (s->sType == STYPE_PHYSICAL_DEVICE_FEATURES_2) hide(((Features2 *)s)->features);
    return next(gpu, &copy, allocator, out);
}

EXPORT PFN_vkVoidFunction vkGetDeviceProcAddr(VkDevice device, const char *name);

EXPORT PFN_vkVoidFunction vkGetInstanceProcAddr(VkInstance instance, const char *name) {
    if (!strcmp(name, "vkGetInstanceProcAddr")) return (PFN_vkVoidFunction)vkGetInstanceProcAddr;
    if (!strcmp(name, "vkGetDeviceProcAddr")) return (PFN_vkVoidFunction)vkGetDeviceProcAddr;
    if (!strcmp(name, "vkCreateInstance")) return (PFN_vkVoidFunction)createInstance;
    if (!strcmp(name, "vkCreateDevice")) return (PFN_vkVoidFunction)createDevice;
    if (!strcmp(name, "vkGetPhysicalDeviceFeatures")) return (PFN_vkVoidFunction)getFeatures;
    if (!strcmp(name, "vkGetPhysicalDeviceFeatures2") || !strcmp(name, "vkGetPhysicalDeviceFeatures2KHR"))
        return (PFN_vkVoidFunction)getFeatures2;
    return nextInstanceProcAddr ? nextInstanceProcAddr(instance, name) : NULL;
}

EXPORT PFN_vkVoidFunction vkGetDeviceProcAddr(VkDevice device, const char *name) {
    if (!strcmp(name, "vkGetDeviceProcAddr")) return (PFN_vkVoidFunction)vkGetDeviceProcAddr;
    return nextDeviceProcAddr ? nextDeviceProcAddr(device, name) : NULL;
}
