// ESPOverlay - 透视绘制层
// 通过 ImGui/Metal 绘制 ESP 元素

#import "ESPOverlay.h"
#import "XPFKernelInterface.h"

#define MAX_ENTITIES 64

typedef struct {
    float position[3];    // 世界坐标 [x, y, z]
    float health;
    int team;
    uint32_t visible;
    char name[64];
    float head_y;
    BOOL is_valid;
} EntityData;

@interface ESPOverlay ()
@property (nonatomic) EntityData entities[MAX_ENTITIES];
@property (nonatomic) int entityCount;
@property (nonatomic) int localTeam;
@end

@implementation ESPOverlay

+ (instancetype)shared {
    static ESPOverlay *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ESPOverlay alloc] init];
    });
    return shared;
}

- (void)updateEntitiesFromGameMemory:(mach_port_t)game_task {
    if (game_task == MACH_PORT_NULL) return;
    
    int count = 0;
    uint64_t entity_list = g_game_offsets.entity_list;
    uint64_t local_player = 0;

    size_t lp_sz = sizeof(local_player);
    kern_reading(game_task, entity_list + 0x10, &local_player, &lp_sz);

    self.localTeam = 0;
    if (local_player) {
        size_t lt_sz = sizeof(self.localTeam);
        kern_reading(game_task, local_player + g_game_offsets.team_offset,
                    &self.localTeam, &lt_sz);
    }

    for (int i = 0; i < MAX_ENTITIES; i++) {
        uint64_t entity = 0;
        size_t en_sz = sizeof(entity);
        kern_reading(game_task, entity_list + i * 8, &entity, &en_sz);

        if (entity && entity != local_player) {
            EntityData *data = &self.entities[count];
            memset(data, 0, sizeof(EntityData));

            size_t pos_sz = sizeof(data->position);
            kern_reading(game_task, entity + g_game_offsets.position_offset,
                        data->position, &pos_sz);

            size_t hl_sz = sizeof(data->health);
            kern_reading(game_task, entity + g_game_offsets.health_offset,
                        &data->health, &hl_sz);

            size_t tm_sz = sizeof(data->team);
            kern_reading(game_task, entity + g_game_offsets.team_offset,
                        &data->team, &tm_sz);

            size_t vs_sz = sizeof(data->visible);
            kern_reading(game_task, entity + g_game_offsets.visible_mask,
                        &data->visible, &vs_sz);

            size_t nm_sz = 64;
            kern_reading(game_task, entity + 0x100, data->name, &nm_sz);

            data->head_y = 1.8f;
            data->is_valid = YES;
            count++;
        }
    }
    self.entityCount = count;
}

- (void)renderESPWithViewMatrix:(float *)viewMatrix 
                    projectMatrix:(float *)projectMatrix
                           width:(float)screenW 
                          height:(float)screenH {
    (void)viewMatrix;
    (void)projectMatrix;
    (void)screenW;
    (void)screenH;
}

- (BOOL)worldToScreen:(float *)worldPos
           viewMatrix:(float *)viewMatrix
        projectMatrix:(float *)projectMatrix
                width:(float)width height:(float)height
                  out:(float *)screenPos {
    (void)worldPos;
    (void)viewMatrix;
    (void)projectMatrix;
    (void)width;
    (void)height;
    (void)screenPos;
    return NO;
}

@end
