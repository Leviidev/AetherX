// AetherEmu MeloNX Fork — Libretro Bridge Implementation
// Loads and runs Libretro cores (PCSX ReARMed for PS1, Snes9x for SNES)
// via the standard libretro.h API.

#include "libretro_bridge.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "libretro.h"

#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <OpenGLES/ES3/gl.h>

// ── Hardware Rendering State ──
static struct retro_hw_render_callback hw_render = {0};
static bool hw_render_enabled = false;
static EAGLContext *eagl_context = NULL;
static GLuint hw_fbo = 0;
static GLuint hw_color_cb = 0;
static GLuint hw_depth_cb = 0;
static bool hw_context_reset_called = false;

static uintptr_t get_current_framebuffer(void) {
    return hw_fbo;
}

static retro_proc_address_t get_proc_address(const char *sym) {
    return (retro_proc_address_t)dlsym(RTLD_DEFAULT, sym);
}

// ── Internal state ──
static void* core_handle = NULL;
static bool core_needs_fullpath = false;
static char sys_dir[1024];
static const struct retro_api* api = NULL;

static retro_environment_t environ_cb = NULL;
static retro_video_refresh_t video_cb = NULL;
static retro_audio_sample_t audio_cb = NULL;
static retro_audio_sample_batch_t audio_batch_cb = NULL;
static retro_input_poll_t poll_cb = NULL;
static retro_input_state_t input_cb = NULL;

static uint32_t p1_buttons = 0;
static int16_t p1_analog_x = 0;
static int16_t p1_analog_y = 0;
static enum retro_pixel_format current_pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;
static uint32_t* video_buffer = NULL;
static size_t video_buffer_size = 0;

static LBVideoFrameCallback user_video_callback = NULL;
static LBAudioSampleCallback user_audio_callback = NULL;

static unsigned current_width = 0;
static unsigned current_height = 0;

// ── Core path map ──
static const char* core_path_for_system(LBNESystem system) {
    switch (system) {
        case LBSNES:
            return "snes9x_libretro_ios.core";
        case LBN64:
            return "mupen64plus_next_libretro_ios.core";
        case LBGBA:
            return "mgba_libretro_ios.core";
        case LBGenesis:
            return "genesis_plus_gx_libretro_ios.core";
        case LBNDS:
            return "melonds_libretro_ios.core";
        case LBDreamcast:
            return "flycast_libretro_ios.core";
        case LBPSP:
            return "ppsspp_libretro_ios.core";
        case LBNES:
            return "fceumm_libretro_ios.core";
        case LBGBC:
            return "gambatte_libretro_ios.core";
        case LBArcade:
            return "fbneo_libretro_ios.core";
        case LBSegaCD:
            return "picodrive_libretro_ios.core";
        case LBSystem_PS1:
        default:
            return "pcsx_rearmed_libretro_ios.core";
    }
}

// ── Environment callback ──
static bool environment_cb(unsigned cmd, void* data) {
    switch (cmd) {
        case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: {
            struct retro_system_av_info* av = (struct retro_system_av_info*)data;
            current_width = av->geometry.base_width;
            current_height = av->geometry.base_height;
            return true;
        }
        case RETRO_ENVIRONMENT_GET_VARIABLE: {
            struct retro_variable *var = (struct retro_variable *)data;
            if (!var || !var->key) return false;
            
            return false;
        }
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
            return false;
        case RETRO_ENVIRONMENT_SET_HW_RENDER: {
            struct retro_hw_render_callback *cb = (struct retro_hw_render_callback *)data;
            
            EAGLRenderingAPI apiType = kEAGLRenderingAPIOpenGLES2;
            if (cb->context_type == RETRO_HW_CONTEXT_OPENGLES3) {
                apiType = kEAGLRenderingAPIOpenGLES3;
            } else if (cb->context_type != RETRO_HW_CONTEXT_OPENGLES2 && cb->context_type != RETRO_HW_CONTEXT_OPENGLES_VERSION) {
                return false; // Unsupported context
            }
            
            eagl_context = [[EAGLContext alloc] initWithAPI:apiType];
            if (!eagl_context) return false;
            
            [EAGLContext setCurrentContext:eagl_context];
            
            // We will create the FBO later when dimensions are known (or default size)
            hw_fbo = 0;
            
            hw_render = *cb;
            hw_render.get_current_framebuffer = get_current_framebuffer;
            hw_render.get_proc_address = get_proc_address;
            hw_render_enabled = true;
            
            return true;
        }
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
            enum retro_pixel_format fmt = *(enum retro_pixel_format*)data;
            if (fmt == RETRO_PIXEL_FORMAT_XRGB8888 || 
                fmt == RETRO_PIXEL_FORMAT_RGB565 || 
                fmt == RETRO_PIXEL_FORMAT_0RGB1555) {
                current_pixel_format = fmt;
                return true;
            }
            return false;
        }
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: {
            const char **dir = (const char **)data;
            *dir = sys_dir;
            return true;
        }
        default:
            return false;
    }
}

// ── Video refresh callback (called by Libretro core) ──
static void video_refresh_cb(const void* data, unsigned width, unsigned height, size_t pitch) {
    current_width = width;
    current_height = height;
    
    if (data == RETRO_HW_FRAME_BUFFER_VALID) {
        // The core rendered into our FBO. We must extract it.
        // Handled entirely in lb_run() after retro_run() returns, using glReadPixels.
        return;
    }
    
    if (!data || !user_video_callback) return;
    
    if (current_pixel_format == RETRO_PIXEL_FORMAT_XRGB8888) {
        user_video_callback(data, width, height, pitch);
    } else {
        size_t out_pitch = width * 4;
        size_t required_size = height * out_pitch;
        if (video_buffer_size < required_size) {
            video_buffer = realloc(video_buffer, required_size);
            video_buffer_size = required_size;
        }
        
        if (current_pixel_format == RETRO_PIXEL_FORMAT_0RGB1555) {
            for (unsigned y = 0; y < height; y++) {
                const uint16_t* in_row = (const uint16_t*)((const uint8_t*)data + y * pitch);
                uint32_t* out_row = (uint32_t*)((uint8_t*)video_buffer + y * out_pitch);
                for (unsigned x = 0; x < width; x++) {
                    uint16_t p = in_row[x];
                    uint8_t r = (p >> 10) & 0x1F;
                    uint8_t g = (p >> 5) & 0x1F;
                    uint8_t b = (p & 0x1F);
                    out_row[x] = (255 << 24) | ((r << 3) << 16) | ((g << 3) << 8) | (b << 3);
                }
            }
        } else if (current_pixel_format == RETRO_PIXEL_FORMAT_RGB565) {
            for (unsigned y = 0; y < height; y++) {
                const uint16_t* in_row = (const uint16_t*)((const uint8_t*)data + y * pitch);
                uint32_t* out_row = (uint32_t*)((uint8_t*)video_buffer + y * out_pitch);
                for (unsigned x = 0; x < width; x++) {
                    uint16_t p = in_row[x];
                    uint8_t r = (p >> 11) & 0x1F;
                    uint8_t g = (p >> 5) & 0x3F;
                    uint8_t b = (p & 0x1F);
                    out_row[x] = (255 << 24) | ((r << 3) << 16) | ((g << 2) << 8) | (b << 3);
                }
            }
        }
        
        user_video_callback(video_buffer, width, height, out_pitch);
    }
}

// ── Audio sample callback (called by Libretro core) ──
static void audio_sample_cb(int16_t left, int16_t right) {
    if (user_audio_callback) {
        user_audio_callback(left, right);
    }
}

// ── Audio sample batch callback ──
static size_t audio_sample_batch_cb(const int16_t* data, size_t frames) {
    if (user_audio_callback) {
        for (size_t i = 0; i < frames; i++) {
            user_audio_callback(data[i * 2], data[i * 2 + 1]);
        }
    }
    return frames;
}

// ── Input poll callback ──
static void input_poll_cb(void) {
    // No-op — we push input state directly via lb_set_button_state
}

// ── Input state callback ──
static int16_t input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (port == 0) {
        if (device == RETRO_DEVICE_JOYPAD) {
            return (p1_buttons & (1 << id)) ? 1 : 0;
        } else if (device == RETRO_DEVICE_ANALOG) {
            if (index == RETRO_DEVICE_INDEX_ANALOG_LEFT) {
                if (id == RETRO_DEVICE_ID_ANALOG_X) return p1_analog_x;
                if (id == RETRO_DEVICE_ID_ANALOG_Y) return p1_analog_y;
            }
        }
    }
    return 0;
}

// ── Public API ──

LBError lb_init(LBNESystem system, const char* core_path, const char* system_dir) {
    if (core_handle) {
        lb_destroy();
    }

    const char* path = core_path ? core_path : core_path_for_system(system);
    if (system_dir) {
        strncpy(sys_dir, system_dir, sizeof(sys_dir) - 1);
        sys_dir[sizeof(sys_dir) - 1] = '\0';
    } else { sys_dir[0] = '\0'; }
    
    // Try to load the core dylib
    core_handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!core_handle) {
        const char *err = dlerror();
        fprintf(stderr, "[LibretroBridge] Failed to load core: %s\n", err);
        
        // Also write directly to console.log in Documents to ensure it's captured
        char log_path[1024];
        snprintf(log_path, sizeof(log_path), "%s/../console.log", sys_dir);
        FILE *f = fopen(log_path, "a+");
        if (f) {
            fprintf(f, "[C-BRIDGE] dlopen failed on %s: %s\n", path, err);
            fclose(f);
        }
        
        return LBError_NotFound;
    }

    // Get the retro API
    void (*retro_init_fn)(void) = dlsym(core_handle, "retro_init");
    bool (*retro_load_game_fn)(const struct retro_game_info*) = dlsym(core_handle, "retro_load_game");
    void (*retro_deinit_fn)(void) = dlsym(core_handle, "retro_deinit");
    void (*retro_run_fn)(void) = dlsym(core_handle, "retro_run");
    void (*retro_reset_fn)(void) = dlsym(core_handle, "retro_reset");
    void (*retro_get_system_info_fn)(struct retro_system_info*) = dlsym(core_handle, "retro_get_system_info");
    void (*retro_get_system_av_info_fn)(struct retro_system_av_info*) = dlsym(core_handle, "retro_get_system_av_info");
    void (*retro_set_environment_fn)(retro_environment_t) = dlsym(core_handle, "retro_set_environment");
    void (*retro_set_video_refresh_fn)(retro_video_refresh_t) = dlsym(core_handle, "retro_set_video_refresh");
    void (*retro_set_audio_sample_fn)(retro_audio_sample_t) = dlsym(core_handle, "retro_set_audio_sample");
    void (*retro_set_audio_sample_batch_fn)(retro_audio_sample_batch_t) = dlsym(core_handle, "retro_set_audio_sample_batch");
    void (*retro_set_input_poll_fn)(retro_input_poll_t) = dlsym(core_handle, "retro_set_input_poll");
    void (*retro_set_input_state_fn)(retro_input_state_t) = dlsym(core_handle, "retro_set_input_state");

    if (!retro_init_fn || !retro_load_game_fn || !retro_deinit_fn || !retro_run_fn) {
        fprintf(stderr, "[LibretroBridge] Core missing required symbols\n");
        dlclose(core_handle);
        core_handle = NULL;
        return LBError_LoadFailed;
    }

    // Register callbacks
    if (retro_set_environment_fn) retro_set_environment_fn(environment_cb);
    if (retro_set_video_refresh_fn) retro_set_video_refresh_fn(video_refresh_cb);
    if (retro_set_audio_sample_fn) retro_set_audio_sample_fn(audio_sample_cb);
    if (retro_set_audio_sample_batch_fn) retro_set_audio_sample_batch_fn(audio_sample_batch_cb);
    if (retro_set_input_poll_fn) retro_set_input_poll_fn(input_poll_cb);
    if (retro_set_input_state_fn) retro_set_input_state_fn(input_state_cb);

    // Initialize the core
    retro_init_fn();

    // Get system info
    struct retro_system_info system_info;
    if (retro_get_system_info_fn) {
        retro_get_system_info_fn(&system_info);
        core_needs_fullpath = system_info.need_fullpath;
        printf("[LibretroBridge] Loaded core: %s (%s), needs fullpath: %d\n",
               system_info.library_name ? system_info.library_name : "?",
               system_info.library_version ? system_info.library_version : "?",
               core_needs_fullpath);
    }

    return LBError_None;
}

LBError lb_load_rom(const char* rom_path) {
    if (!core_handle) return LBError_InitFailed;

    bool (*retro_load_game_fn)(const struct retro_game_info*) = dlsym(core_handle, "retro_load_game");
    if (!retro_load_game_fn) return LBError_LoadFailed;

    if (core_needs_fullpath) {
        struct retro_game_info game_info = {
            .path = rom_path,
            .data = NULL,
            .size = 0,
            .meta = NULL,
        };
        
        if (hw_render_enabled && eagl_context) {
            [EAGLContext setCurrentContext:eagl_context];
            if (hw_render.context_reset && !hw_context_reset_called) {
                hw_render.context_reset();
                hw_context_reset_called = true;
            }
        }
        
        bool success = retro_load_game_fn(&game_info);
        if (!success) {
            fprintf(stderr, "[LibretroBridge] retro_load_game (fullpath) failed\n");
            return LBError_InitFailed;
        }
        
        
        void (*retro_get_system_av_info_fn)(struct retro_system_av_info*) = dlsym(core_handle, "retro_get_system_av_info");
        if (retro_get_system_av_info_fn) {
            struct retro_system_av_info av_info;
            retro_get_system_av_info_fn(&av_info);
            current_width = av_info.geometry.base_width;
            current_height = av_info.geometry.base_height;
            printf("[LibretroBridge] AV Info updated: %ux%u\n", current_width, current_height);
        }

        printf("[LibretroBridge] ROM loaded (fullpath): %s\n", rom_path);
        return LBError_None;
    }

    // Read the ROM file into memory if fullpath is not required
    FILE* f = fopen(rom_path, "rb");
    if (!f) {
        fprintf(stderr, "[LibretroBridge] Cannot open ROM: %s\n", rom_path);
        return LBError_InvalidROM;
    }

    fseek(f, 0, SEEK_END);
    size_t size = ftell(f);
    rewind(f);

    void* data = malloc(size);
    if (!data) {
        fclose(f);
        return LBError_Generic;
    }

    size_t read = fread(data, 1, size, f);
    fclose(f);

    if (read != size) {
        free(data);
        return LBError_InvalidROM;
    }

    struct retro_game_info game_info = {
        .path = rom_path,
        .data = data,
        .size = size,
        .meta = NULL,
    };

    if (hw_render_enabled && eagl_context) {
        [EAGLContext setCurrentContext:eagl_context];
        if (hw_render.context_reset && !hw_context_reset_called) {
            hw_render.context_reset();
            hw_context_reset_called = true;
        }
    }
    
    bool success = retro_load_game_fn(&game_info);
    free(data);

    if (!success) {
        fprintf(stderr, "[LibretroBridge] retro_load_game (memory) failed\n");
        return LBError_InitFailed;
    }

    void (*retro_get_system_av_info_fn)(struct retro_system_av_info*) = dlsym(core_handle, "retro_get_system_av_info");
    if (retro_get_system_av_info_fn) {
        struct retro_system_av_info av_info;
        retro_get_system_av_info_fn(&av_info);
        current_width = av_info.geometry.base_width;
        current_height = av_info.geometry.base_height;
        printf("[LibretroBridge] AV Info updated: %ux%u\n", current_width, current_height);
    }

    printf("[LibretroBridge] ROM loaded (memory): %s (%zu bytes)\n", rom_path, size);
    return LBError_None;
}

void lb_run(void) {
    if (!core_handle) return;
    void (*retro_run_fn)(void) = dlsym(core_handle, "retro_run");
    if (retro_run_fn) {
        if (hw_render_enabled && eagl_context) {
            [EAGLContext setCurrentContext:eagl_context];
            
            // Ensure FBO is created
            if (hw_fbo == 0 && current_width > 0 && current_height > 0) {
                glGenFramebuffers(1, &hw_fbo);
                glBindFramebuffer(GL_FRAMEBUFFER, hw_fbo);
                
                glGenRenderbuffers(1, &hw_color_cb);
                glBindRenderbuffer(GL_RENDERBUFFER, hw_color_cb);
                glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8_OES, current_width, current_height);
                glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, hw_color_cb);
                
                if (hw_render.depth) {
                    glGenRenderbuffers(1, &hw_depth_cb);
                    glBindRenderbuffer(GL_RENDERBUFFER, hw_depth_cb);
                    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8_OES, current_width, current_height);
                    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, hw_depth_cb);
                    if (hw_render.stencil) {
                        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, hw_depth_cb);
                    }
                }
            }
            if (hw_fbo != 0) {
                glBindFramebuffer(GL_FRAMEBUFFER, hw_fbo);
            }
        }

        retro_run_fn();

        if (hw_render_enabled && eagl_context && hw_fbo != 0 && user_video_callback) {
            size_t out_pitch = current_width * 4;
            size_t required_size = current_height * out_pitch;
            if (video_buffer_size < required_size) {
                video_buffer = realloc(video_buffer, required_size);
                video_buffer_size = required_size;
            }
            
            glBindFramebuffer(GL_FRAMEBUFFER, hw_fbo);
            glReadPixels(0, 0, current_width, current_height, GL_RGBA, GL_UNSIGNED_BYTE, video_buffer);
            
            // Flip the image vertically (OpenGL reads bottom-up)
            uint8_t *tmp_row = malloc(out_pitch);
            for (unsigned y = 0; y < current_height / 2; y++) {
                uint8_t *row_a = (uint8_t *)video_buffer + y * out_pitch;
                uint8_t *row_b = (uint8_t *)video_buffer + (current_height - 1 - y) * out_pitch;
                memcpy(tmp_row, row_a, out_pitch);
                memcpy(row_a, row_b, out_pitch);
                memcpy(row_b, tmp_row, out_pitch);
            }
            free(tmp_row);
            
            user_video_callback(video_buffer, current_width, current_height, out_pitch);
        }
    }
}

bool lb_run_frame(void) {
    lb_run();
    return true;
}

void lb_reset(void) {
    if (!core_handle) return;
    void (*retro_reset_fn)(void) = dlsym(core_handle, "retro_reset");
    if (retro_reset_fn) retro_reset_fn();
}

void lb_destroy(void) {
    if (!core_handle) return;
    void (*retro_unload_game_fn)(void) = dlsym(core_handle, "retro_unload_game");
    void (*retro_deinit_fn)(void) = dlsym(core_handle, "retro_deinit");
    
    if (retro_unload_game_fn) retro_unload_game_fn();
    if (retro_deinit_fn) retro_deinit_fn();
    
    if (hw_render_enabled && eagl_context) {
        [EAGLContext setCurrentContext:eagl_context];
        if (hw_render.context_destroy && hw_context_reset_called) {
            hw_render.context_destroy();
            hw_context_reset_called = false;
        }
        if (hw_fbo) {
            glDeleteFramebuffers(1, &hw_fbo);
            hw_fbo = 0;
        }
        if (hw_color_cb) {
            glDeleteRenderbuffers(1, &hw_color_cb);
            hw_color_cb = 0;
        }
        if (hw_depth_cb) {
            glDeleteRenderbuffers(1, &hw_depth_cb);
            hw_depth_cb = 0;
        }
        eagl_context = NULL;
        hw_render_enabled = false;
    }
    
    dlclose(core_handle);
    core_handle = NULL;
    user_video_callback = NULL;
    user_audio_callback = NULL;
    current_width = 0;
    current_height = 0;
}

bool lb_save_state(const char* path) {
    if (!core_handle) return false;
    size_t (*retro_serialize_size_fn)(void) = dlsym(core_handle, "retro_serialize_size");
    bool (*retro_serialize_fn)(void *data, size_t size) = dlsym(core_handle, "retro_serialize");
    
    if (!retro_serialize_size_fn || !retro_serialize_fn) return false;
    
    size_t size = retro_serialize_size_fn();
    if (size == 0) return false;
    
    void* data = malloc(size);
    if (!data) return false;
    
    bool ok = retro_serialize_fn(data, size);
    if (ok) {
        FILE* f = fopen(path, "wb");
        if (f) {
            fwrite(data, 1, size, f);
            fclose(f);
        } else {
            ok = false;
        }
    }
    
    free(data);
    return ok;
}

bool lb_load_state(const char* path) {
    if (!core_handle) return false;
    bool (*retro_unserialize_fn)(const void *data, size_t size) = dlsym(core_handle, "retro_unserialize");
    if (!retro_unserialize_fn) return false;
    
    FILE* f = fopen(path, "rb");
    if (!f) return false;
    
    fseek(f, 0, SEEK_END);
    size_t size = ftell(f);
    rewind(f);
    
    void* data = malloc(size);
    if (!data) {
        fclose(f);
        return false;
    }
    
    size_t read = fread(data, 1, size, f);
    fclose(f);
    
    bool ok = false;
    if (read == size) {
        ok = retro_unserialize_fn(data, size);
    }
    
    free(data);
    return ok;
}

bool lb_save_sram(const char* path) {
    if (!core_handle) return false;
    size_t (*retro_get_memory_size_fn)(unsigned id) = dlsym(core_handle, "retro_get_memory_size");
    void* (*retro_get_memory_data_fn)(unsigned id) = dlsym(core_handle, "retro_get_memory_data");
    
    if (!retro_get_memory_size_fn || !retro_get_memory_data_fn) return false;
    
    size_t size = retro_get_memory_size_fn(RETRO_MEMORY_SAVE_RAM);
    if (size == 0) return false;
    
    void* data = retro_get_memory_data_fn(RETRO_MEMORY_SAVE_RAM);
    if (!data) return false;
    
    FILE* f = fopen(path, "wb");
    if (!f) return false;
    
    fwrite(data, 1, size, f);
    fclose(f);
    return true;
}

bool lb_load_sram(const char* path) {
    if (!core_handle) return false;
    size_t (*retro_get_memory_size_fn)(unsigned id) = dlsym(core_handle, "retro_get_memory_size");
    void* (*retro_get_memory_data_fn)(unsigned id) = dlsym(core_handle, "retro_get_memory_data");
    
    if (!retro_get_memory_size_fn || !retro_get_memory_data_fn) return false;
    
    size_t size = retro_get_memory_size_fn(RETRO_MEMORY_SAVE_RAM);
    if (size == 0) return false;
    
    void* data = retro_get_memory_data_fn(RETRO_MEMORY_SAVE_RAM);
    if (!data) return false;
    
    FILE* f = fopen(path, "rb");
    if (!f) return false;
    
    fseek(f, 0, SEEK_END);
    size_t file_size = ftell(f);
    rewind(f);
    
    // Some cores pad SRAM or expect an exact match. We'll only load if sizes match.
    if (file_size != size) {
        fclose(f);
        return false;
    }
    
    fread(data, 1, size, f);
    fclose(f);
    return true;
}

void lb_set_video_callback(LBVideoFrameCallback callback) {
    user_video_callback = callback;
}

void lb_set_audio_callback(LBAudioSampleCallback callback) {
    user_audio_callback = callback;
}

void lb_set_button_state(unsigned port, unsigned button, bool pressed) {
    if (port == 0) {
        if (pressed) p1_buttons |= (1 << button);
        else p1_buttons &= ~(1 << button);
    }
}

void lb_set_analog_state(unsigned port, int16_t x, int16_t y) {
    if (port == 0) {
        p1_analog_x = x;
        p1_analog_y = y;
    }
}

void lb_get_video_dimensions(unsigned* width, unsigned* height) {
    if (width) *width = current_width;
    if (height) *height = current_height;
}

bool lb_is_supported_extension(const char* extension) {
    static const char* supported[] = {
        ".bin", ".cue", ".iso", ".pbp", ".img", ".mdf", ".ps1",  // PS1
        ".sfc", ".smc", ".fig", ".swc", ".bs",  // SNES
        NULL
    };
    if (!extension) return false;
    for (int i = 0; supported[i]; i++) {
        if (strcasecmp(extension, supported[i]) == 0) return true;
    }
    return false;
}

unsigned lb_get_pixel_format(void) {
    return current_pixel_format;
}
