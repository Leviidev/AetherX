// melonx_bridge.m  –  Objective-C bridge between AetherX Swift and LibRyujinx
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#include "libryujinx.h"

// ── Dylib handle ─────────────────────────────────────────────────────────────
static void* _libHandle = NULL;

// ── Function pointer typedefs ─────────────────────────────────────────────────
typedef bool  (*fn_initialize)(const char*);
typedef bool  (*fn_device_initialize)(bool,bool,int,int,bool,bool,bool,bool,const char*,bool);
typedef bool  (*fn_device_load)(int, const char*);
typedef bool  (*fn_graphics_initialize)(GraphicsConfiguration);
typedef bool  (*fn_graphics_initialize_renderer)(int, NativeGraphicsInterop);
typedef void  (*fn_graphics_renderer_set_size)(int, int);
typedef void  (*fn_graphics_renderer_run_loop)(void);
typedef void  (*fn_graphics_renderer_set_vsync)(bool);
typedef void  (*fn_graphics_renderer_set_swap_buffer_callback)(void*);
typedef bool  (*fn_input_initialize)(int, int);
typedef void  (*fn_input_set_client_size)(int, int);
typedef void  (*fn_input_set_touch_point)(int, int);
typedef void  (*fn_input_release_touch_point)(void);
typedef void  (*fn_input_update)(void);
typedef void  (*fn_input_set_button_pressed)(int, int);
typedef void  (*fn_input_set_button_released)(int, int);
typedef void  (*fn_input_set_stick_axis)(int, float, float, int);

// ── Load helper ──────────────────────────────────────────────────────────────
static void* sym(const char* name) {
    void* fn = dlsym(_libHandle, name);
    if (!fn) {
        NSLog(@"[MeloNX] Missing symbol: %s – %s", name, dlerror());
    }
    return fn;
}

// ── Public Objective-C API ───────────────────────────────────────────────────
bool melonx_load_library(void) {
    if (_libHandle) return true;
    
    NSString* frameworkPath = [[NSBundle mainBundle] pathForResource:@"LibRyujinx"
                                                              ofType:@"dylib"];
    if (!frameworkPath) {
        // Fallback: look next to the binary
        NSString* bundlePath = [NSBundle mainBundle].bundlePath;
        frameworkPath = [bundlePath stringByAppendingPathComponent:@"LibRyujinx.dylib"];
    }
    
    _libHandle = dlopen(frameworkPath.UTF8String, RTLD_LAZY | RTLD_GLOBAL);
    if (!_libHandle) {
        NSLog(@"[MeloNX] dlopen failed: %s", dlerror());
        return false;
    }
    NSLog(@"[MeloNX] LibRyujinx loaded successfully from %@", frameworkPath);
    return true;
}

bool melonx_initialize(const char* base_path) {
    fn_initialize fn = sym("initialize");
    return fn ? fn(base_path) : false;
}

bool melonx_device_initialize(void) {
    fn_device_initialize fn = sym("device_initialize");
    if (!fn) return false;
    return fn(
        false,  // is_host_mapped
        false,  // use_nce (no NCE on iOS without kernel patch)
        1,      // system_language (AmericanEnglish)
        0,      // region_code (USA)
        true,   // enable_vsync
        true,   // enable_docked_mode
        true,   // enable_ptc
        false,  // enable_internet_access
        "UTC",  // time_zone
        true    // ignore_missing_services
    );
}

bool melonx_device_load(const char* rom_path) {
    // LibRyujinx device_load takes a file descriptor and extension
    int fd = open(rom_path, O_RDONLY);
    if (fd < 0) {
        NSLog(@"[MeloNX] Cannot open ROM: %s", rom_path);
        return false;
    }
    
    NSString* path = [NSString stringWithUTF8String:rom_path];
    NSString* ext  = path.pathExtension.lowercaseString;
    
    fn_device_load fn = sym("device_load");
    bool result = fn ? fn(fd, ext.UTF8String) : false;
    close(fd);
    return result;
}

bool melonx_graphics_initialize(int width, int height) {
    GraphicsConfiguration cfg = {
        .res_scale                  = 1.0f,
        .max_anisotropy             = -1.0f,
        .fast_gpu_time              = true,
        .fast_2d_copy               = true,
        .enable_macro_jit           = false,
        .enable_macro_hle           = true,
        .enable_shader_cache        = true,
        .enable_texture_recompression = false,
        .backend_threading          = 1,  // Auto
        .aspect_ratio               = 1,  // 16:9
    };
    
    fn_graphics_initialize fn = sym("graphics_initialize");
    if (!fn || !fn(cfg)) return false;
    
    fn_graphics_renderer_set_size set_size = sym("graphics_renderer_set_size");
    if (set_size) set_size(width, height);
    
    return true;
}

void melonx_graphics_run_loop(void) {
    fn_graphics_renderer_run_loop fn = sym("graphics_renderer_run_loop");
    if (fn) fn();
}

void melonx_graphics_set_vsync(bool enabled) {
    fn_graphics_renderer_set_vsync fn = sym("graphics_renderer_set_vsync");
    if (fn) fn(enabled);
}

bool melonx_input_initialize(int width, int height) {
    fn_input_initialize fn = sym("input_initialize");
    return fn ? fn(width, height) : false;
}

void melonx_input_set_client_size(int width, int height) {
    fn_input_set_client_size fn = sym("input_set_client_size");
    if (fn) fn(width, height);
}

void melonx_input_set_touch_point(int x, int y) {
    fn_input_set_touch_point fn = sym("input_set_touch_point");
    if (fn) fn(x, y);
}

void melonx_input_release_touch_point(void) {
    fn_input_release_touch_point fn = sym("input_release_touch_point");
    if (fn) fn();
}

void melonx_input_update(void) {
    fn_input_update fn = sym("input_update");
    if (fn) fn();
}

void melonx_input_button_pressed(int button, int player_index) {
    fn_input_set_button_pressed fn = sym("input_set_button_pressed");
    if (fn) fn(button, player_index);
}

void melonx_input_button_released(int button, int player_index) {
    fn_input_set_button_released fn = sym("input_set_button_released");
    if (fn) fn(button, player_index);
}

void melonx_input_set_stick_axis(int stick, float x, float y, int player_index) {
    fn_input_set_stick_axis fn = sym("input_set_stick_axis");
    if (fn) fn(stick, x, y, player_index);
}
