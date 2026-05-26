// ESPOverlay - 透视绘制层
// 通过 ImGui/Metal 绘制 ESP 元素
// 从游戏内存读取实体数据并渲染到 HUD 层

#import "ESPOverlay.h"
#import "XPFKernelInterface.h"

// 最大实体数
#define MAX_ENTITIES 64

typedef struct {
    float x, y, z;       // 世界坐标
    float health;         // 生命值 0-100
    int team;             // 队伍
    uint32_t visible;     // 可见性
    char name[64];        // 玩家名
    float head_y;         // 头部高度偏移
    BOOL is_valid;        // 是否有效
} EntityData;

@interface ESPOverlay ()
@property (nonatomic) EntityData entities[MAX_ENTITIES];
@property (nonatomic) int entityCount;
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
    
    // 读取本地玩家
    kern_reading(game_task, entity_list + 0x10, &local_player, sizeof(uint64_t));
    
    int local_team = 0;
    if (local_player) {
        kern_reading(game_task, local_player + g_game_offsets.team_offset, 
                    &local_team, sizeof(int));
    }
    
    // 遍历实体列表
    for (int i = 0; i < MAX_ENTITIES; i++) {
        uint64_t entity = 0;
        kern_reading(game_task, entity_list + i * 8, &entity, sizeof(uint64_t));
        
        if (entity && entity != local_player) {
            EntityData *data = &self.entities[count];
            memset(data, 0, sizeof(EntityData));
            
            // 读取位置
            kern_reading(game_task, entity + g_game_offsets.position_offset, 
                        &data->position, sizeof(float) * 3);
            
            // 读取血量
            kern_reading(game_task, entity + g_game_offsets.health_offset, 
                        &data->health, sizeof(float));
            
            // 读取队伍
            kern_reading(game_task, entity + g_game_offsets.team_offset, 
                        &data->team, sizeof(int));
            
            // 读取可见性
            kern_reading(game_task, entity + g_game_offsets.visible_mask, 
                        &data->visible, sizeof(uint32_t));
            
            // 读取名字
            kern_reading(game_task, entity + 0x100, data->name, 64);
            
            // 头部高度 (UE 角色身高约 180cm)
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
    
    for (int i = 0; i < self.entityCount; i++) {
        EntityData *entity = &self.entities[i];
        if (!entity->is_valid) continue;
        
        // 世界坐标转屏幕坐标
        float screen_pos[2] = {0};
        if (![self worldToScreen:entity->position 
                     viewMatrix:viewMatrix 
                  projectMatrix:projectMatrix 
                          width:screenW height:screenH 
                          out:screen_pos]) {
            continue; // 不在屏幕上
        }
        
        // 计算方框高度 (基于距离)
        float distance = sqrt(entity->position[0]*entity->position[0] + 
                              entity->position[1]*entity->position[1] + 
                              entity->position[2]*entity->position[2]);
        float box_height = 5000.0 / distance;
        float box_width = box_height * 0.6;
        
        // 根据可见性和队伍选择颜色
        ImVec4 color;
        if (entity->team == local_team) {
            color = ImVec4(0.2, 0.8, 0.2, 1.0); // 队友: 绿色
        } else if (entity->visible) {
            color = ImVec4(1.0, 0.2, 0.2, 1.0); // 可见敌人: 红色
        } else {
            color = ImVec4(1.0, 0.8, 0.2, 1.0); // 不可见敌人: 黄色
        }
        
        // 绘制方框
        ImDrawList *dl = ImGui::GetOverlayDrawList();
        dl->AddRect(
            ImVec2(screen_pos[0] - box_width/2, screen_pos[1] - box_height),
            ImVec2(screen_pos[0] + box_width/2, screen_pos[1]),
            ImColor(color.x, color.y, color.z, color.w),
            0.0f, 0, 1.5f
        );
        
        // 绘制血量条
        float health_height = box_height * (entity->health / 100.0f);
        dl->AddRectFilled(
            ImVec2(screen_pos[0] + box_width/2 + 3, screen_pos[1] - health_height),
            ImVec2(screen_pos[0] + box_width/2 + 6, screen_pos[1]),
            ImColor(
                (1.0 - entity->health/100.0) * 2.0,
                entity->health/100.0 * 2.0,
                0.0f, 1.0f
            )
        );
        
        // 绘制名字
        dl->AddText(
            ImVec2(screen_pos[0] - box_width/4, screen_pos[1] - box_height - 14),
            ImColor(1, 1, 1, 1),
            entity->name
        );
        
        // 绘制距离
        char dist_str[32];
        snprintf(dist_str, 32, "%.0fm", distance);
        dl->AddText(
            ImVec2(screen_pos[0] - box_width/4, screen_pos[1] + 2),
            ImColor(0.6, 0.6, 0.6, 1),
            dist_str
        );
    }
}

- (BOOL)worldToScreen:(float *)worldPos 
           viewMatrix:(float *)viewMatrix 
        projectMatrix:(float *)projectMatrix 
                width:(float)width height:(float)height 
                  out:(float *)screenPos {
    
    // 标准 UE 世界到屏幕转换
    float clip[4] = {0};
    
    clip[0] = worldPos[0] * viewMatrix[0] + worldPos[1] * viewMatrix[4] + 
              worldPos[2] * viewMatrix[8] + viewMatrix[12];
    clip[1] = worldPos[0] * viewMatrix[1] + worldPos[1] * viewMatrix[5] + 
              worldPos[2] * viewMatrix[9] + viewMatrix[13];
    clip[2] = worldPos[0] * viewMatrix[2] + worldPos[1] * viewMatrix[6] + 
              worldPos[2] * viewMatrix[10] + viewMatrix[14];
    clip[3] = worldPos[0] * viewMatrix[3] + worldPos[1] * viewMatrix[7] + 
              worldPos[2] * viewMatrix[11] + viewMatrix[15];
    
    if (clip[3] < 0.01f) return NO;
    
    float ndc[3] = {
        clip[0] / clip[3],
        clip[1] / clip[3],
        clip[2] / clip[3]
    };
    
    screenPos[0] = (width / 2) * ndc[0] + (ndc[0] + width / 2);
    screenPos[1] = -(height / 2) * ndc[1] + (ndc[1] + height / 2);
    
    return (ndc[2] < 1.0f);
}

@end
