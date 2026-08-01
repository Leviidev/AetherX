#pragma once
#include <stdbool.h>

// Load the dylib. Must be called before anything else.
bool melonx_load_library(void);

// Lifecycle
bool melonx_initialize(const char* base_path);
bool melonx_device_initialize(void);
bool melonx_device_load(const char* rom_path);

// Graphics
bool melonx_graphics_initialize(int width, int height);
void melonx_graphics_run_loop(void);
void melonx_graphics_set_vsync(bool enabled);

// Input
bool melonx_input_initialize(int width, int height);
void melonx_input_set_client_size(int width, int height);
void melonx_input_set_touch_point(int x, int y);
void melonx_input_release_touch_point(void);
void melonx_input_update(void);
void melonx_input_button_pressed(int button, int player_index);
void melonx_input_button_released(int button, int player_index);
void melonx_input_set_stick_axis(int stick, float x, float y, int player_index);
