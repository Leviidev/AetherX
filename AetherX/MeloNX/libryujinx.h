#pragma once
#include <stdbool.h>
#include <stdint.h>

// ── Structs ─────────────────────────────────────────────────────────────────

typedef struct {
    float  res_scale;
    float  max_anisotropy;
    bool   fast_gpu_time;
    bool   fast_2d_copy;
    bool   enable_macro_jit;
    bool   enable_macro_hle;
    bool   enable_shader_cache;
    bool   enable_texture_recompression;
    int    backend_threading; // 0=disabled,1=auto,2=enabled
    int    aspect_ratio;     // 0=fixed4x3,1=fixed16x9,2=stretched
} GraphicsConfiguration;

typedef struct {
    void*  gl_get_proc_address;
    void*  vk_native_context_loader;
    void*  vk_create_surface;
    void** vk_required_extensions;
    int    vk_required_extensions_count;
} NativeGraphicsInterop;

// ── Lifecycle ────────────────────────────────────────────────────────────────
bool initialize(const char* base_path);

// ── Device ───────────────────────────────────────────────────────────────────
bool device_initialize(
    bool is_host_mapped,
    bool use_nce,
    int  system_language,
    int  region_code,
    bool enable_vsync,
    bool enable_docked_mode,
    bool enable_ptc,
    bool enable_internet_access,
    const char* time_zone,
    bool ignore_missing_services
);
bool device_load(int descriptor, const char* extension);
bool device_install_firmware(int descriptor);
const char* device_get_installed_firmware_version(void);
void device_reloadFilesystem(void);

// ── Graphics ─────────────────────────────────────────────────────────────────
bool graphics_initialize(GraphicsConfiguration config);
bool graphics_initialize_renderer(int backend, NativeGraphicsInterop interop);
void graphics_renderer_set_size(int width, int height);
void graphics_renderer_run_loop(void);
void graphics_renderer_set_vsync(bool enabled);
void graphics_renderer_set_swap_buffer_callback(void* callback);

// ── Input ────────────────────────────────────────────────────────────────────
bool input_initialize(int width, int height);
void input_set_client_size(int width, int height);
void input_set_touch_point(int x, int y);
void input_release_touch_point(void);
void input_update(void);
void input_set_button_pressed(int button, int player_index);
void input_set_button_released(int button, int player_index);
void input_set_stick_axis(int stick, float x, float y, int player_index);
int  input_connect_gamepad(int player_index);
