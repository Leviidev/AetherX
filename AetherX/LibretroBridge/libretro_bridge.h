// AetherEmu MeloNX Fork — Libretro Bridge
// Loads and runs Libretro cores (PCSX ReARMed, Snes9x) for PS1/SNES emulation

#ifndef libretro_bridge_h
#define libretro_bridge_h

#include <stdint.h>
#include <stdbool.h>

// ── Core types ──
typedef enum {
    LBSystem_PS1,
    LBNES,
    LBSNES,
    LBN64,
    LBGBA,
    LBGenesis,
    LBNDS,
    LBDreamcast,
    LBPSP,
    LBGBC,
    LBArcade,
    LBSegaCD
} LBNESystem;

typedef enum {
    LBError_None,
    LBError_NotFound,
    LBError_LoadFailed,
    LBError_InitFailed,
    LBError_InvalidROM,
    LBError_Generic,
} LBError;

// Video frame callback (called from Libretro core on the emulation thread)
typedef void (*LBVideoFrameCallback)(const void* data, unsigned width, unsigned height, size_t pitch);

// Audio sample callback (called from Libretro core)
typedef void (*LBAudioSampleCallback)(int16_t left, int16_t right);

// ── Public API ──

// Initialize the Libretro bridge for a given system
LBError lb_init(LBNESystem system, const char* core_path, const char* system_dir);

// Load a ROM file
LBError lb_load_rom(const char* rom_path);

// Run a single frame (returns false if the core has finished/exited)
bool lb_run_frame(void);

// Reset the emulation
void lb_reset(void);

// Shutdown and unload the core
void lb_destroy(void);

// Save / Load State
bool lb_save_state(const char* path);
bool lb_load_state(const char* path);

// Save / Load SRAM
bool lb_save_sram(const char* path);
bool lb_load_sram(const char* path);

// Set video frame callback
void lb_set_video_callback(LBVideoFrameCallback callback);

// Set audio sample callback  
void lb_set_audio_callback(LBAudioSampleCallback callback);

// Input: set button state (0 = released, 1 = pressed)
void lb_set_button_state(unsigned port, unsigned button, bool pressed);

// Input: set analog stick state (x and y between -32768 and 32767)
void lb_set_analog_state(unsigned port, int16_t x, int16_t y);

// Get the last rendered frame dimensions
void lb_get_video_dimensions(unsigned* width, unsigned* height);

// Check if a ROM file extension is supported
bool lb_is_supported_extension(const char* extension);

#endif /* libretro_bridge_h */

// Get the current pixel format (retro_pixel_format enum)
unsigned lb_get_pixel_format(void);
