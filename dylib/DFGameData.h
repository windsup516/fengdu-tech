// DFGameData.h — Shared game data structures for dylib components
// In-process cheat: direct pointer dereference, no Mach VM needed

#ifndef DFGameData_h
#define DFGameData_h

#import <stdint.h>
#import <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// === UE4 Engine Offsets (stable across versions) ===
#define OFFSET_UWORLD_PERSISTENTLEVEL  0x30
#define OFFSET_ULEVEL_ACTORS           0x98
#define OFFSET_AACTOR_ROOTCOMPONENT    0x188
#define OFFSET_AACTOR_MESH             0x2D0
#define OFFSET_AACTOR_PLAYERSTATE      0x290
#define OFFSET_USCENECOMPONENT_TRANSLATION 0x140
#define OFFSET_USKINNEDMESH_BONES      0x6F0
#define OFFSET_USKELETALMESH_COMPONENTTOWORLD 0x1E0
#define OFFSET_VTABLE_OFFSET           0x0

// Game-specific offsets (may need per-version adjustment)
#define OFFSET_AACTOR_HEALTH           0x120
#define OFFSET_AACTOR_MAX_HEALTH       0x124
#define OFFSET_AACTOR_TEAM_ID          0xF0
#define OFFSET_AACTOR_POSE_STATE       0x418
#define OFFSET_PLAYERCONTROLLER_CAMERA 0x3D0
#define OFFSET_PLAYER_CAMERA_MANAGER   0x330
#define OFFSET_WEAPON_RECOIL           0x2B0
#define OFFSET_WEAPON_SPREAD           0x2C0

// Actor name offset (UE4 UObject::NamePrivate)
#define OFFSET_UOBJECT_FNAME           0x18

// TArray structure
#define TARRAY_OFFSET_DATA 0
#define TARRAY_OFFSET_COUNT 8
#define TARRAY_OFFSET_MAX 16

// === Scanned Offsets (runtime) ===
typedef struct {
    uint64_t gworld_ptr;        // Address of GWorld global pointer variable
    uint64_t gname_base;        // GName table base
    uint64_t game_base;         // Game Mach-O base address
    bool gworld_found;
    bool gname_found;
    bool scanned;
} DFScannedOffsets;

extern DFScannedOffsets g_df_offsets;

// === Entity Data ===
#define DF_MAX_ENTITIES 128

typedef struct {
    float position[3];
    float health;
    float max_health;
    int team;
    bool visible;
    bool is_ai;
    bool is_down;
    char name[64];
    float head_pos[3];
    float chest_pos[3];
    float pelvis_pos[3];
    float distance;
    bool is_valid;
    uint64_t actor_ptr;
} DFEntityData;

// === Config ===
typedef struct {
    bool esp_enabled;
    bool esp_box;
    bool esp_health_bar;
    bool esp_distance;
    bool esp_name;
    bool esp_skeleton;
    bool esp_head_dot;
    bool esp_line;
    bool esp_visible_only;
    bool esp_show_ai;
    bool esp_show_team;
    float esp_max_distance;

    bool aimbot_enabled;
    bool aimbot_auto_fire;
    bool aimbot_visibility_check;
    bool aimbot_ignore_down;
    int  aimbot_target_bone;
    float aimbot_fov;
    float aimbot_smooth;
    float aimbot_max_distance;

    bool no_recoil;
    bool no_spread;

    float enemy_color[4];
    float enemy_visible_color[4];
    float team_color[4];
    float ai_color[4];
    float box_thickness;
} DFCheatConfig;

extern DFCheatConfig g_df_config;

// === Logging ===
void df_log(const char *fmt, ...);

#ifdef __cplusplus
}
#endif

#endif
