// ESPOverlay - 透视绘制层 (完整实现)
// 单透 ESP: 方框, 血量, 距离, 名字, 骨骼线

#import "ESPOverlay.h"
#import "GameHooks.h"
#import "XPFKernelInterface.h"
#import "imgui.h"
#import <math.h>

@interface ESPOverlay () {
    EntityData _entities[MAX_ENTITIES];
    int _entityCount;
    int _localTeam;
}
@end

@implementation ESPOverlay

+ (instancetype)shared {
    static ESPOverlay *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[ESPOverlay alloc] init]; });
    return shared;
}

- (void)updateEntitiesFromGameMemory:(mach_port_t)gameTask {
    if (gameTask == MACH_PORT_NULL) return;

    int count = 0;
    _localTeam = 0;
    uint64_t entityList = g_game_offsets.entity_list;

    // 读本地玩家
    uint64_t localPlayer = 0;
    size_t lpSz = sizeof(localPlayer);
    if (kern_reading(gameTask, entityList + 0x10, &localPlayer, &lpSz) != KERN_SUCCESS) return;

    if (localPlayer) {
        size_t ltSz = sizeof(_localTeam);
        kern_reading(gameTask, localPlayer + g_game_offsets.team_offset, &_localTeam, &ltSz);
    }

    // 遍历实体列表
    for (int i = 0; i < MAX_ENTITIES && count < MAX_ENTITIES; i++) {
        uint64_t entity = 0;
        size_t enSz = sizeof(entity);
        if (kern_reading(gameTask, entityList + i * 8, &entity, &enSz) != KERN_SUCCESS) continue;
        if (!entity || entity == localPlayer) continue;

        // 健康值有效性检查
        int hp = 0;
        size_t hpSz = sizeof(hp);
        kern_reading(gameTask, entity + g_game_offsets.health_offset, &hp, &hpSz);
        if (hp <= 0 || hp > 1000) continue;

        EntityData *data = &_entities[count];
        memset(data, 0, sizeof(EntityData));

        kern_reading(gameTask, entity + g_game_offsets.position_offset, data->position, (size_t[]){sizeof(data->position)});
        data->health = (float)hp;
        kern_reading(gameTask, entity + g_game_offsets.team_offset, &data->team, (size_t[]){sizeof(data->team)});
        kern_reading(gameTask, entity + g_game_offsets.visible_mask, &data->visible, (size_t[]){sizeof(data->visible)});
        size_t nmSz = sizeof(data->name);
        kern_reading(gameTask, entity + 0x100, data->name, &nmSz);

        data->head_y = 2.0f;  // 默认头部高度
        data->is_valid = (data->team != _localTeam); // 只显示敌人
        count++;
    }
    _entityCount = count;
}

// 4x4 矩阵 * 4x1 向量
static inline void mat4_mul_vec4(const float m[16], const float v[4], float out[4]) {
    out[0] = m[0]*v[0] + m[4]*v[1] + m[8]*v[2]  + m[12]*v[3];
    out[1] = m[1]*v[0] + m[5]*v[1] + m[9]*v[2]  + m[13]*v[3];
    out[2] = m[2]*v[0] + m[6]*v[1] + m[10]*v[2] + m[14]*v[3];
    out[3] = m[3]*v[0] + m[7]*v[1] + m[11]*v[2] + m[15]*v[3];
}

- (BOOL)worldToScreen:(float *)worldPos
           viewMatrix:(float *)viewMatrix
        projectMatrix:(float *)projMatrix
                width:(float)width height:(float)height
                  out:(float *)screenPos {
    // 组合 ViewProj = Projection * View
    float vp[16];
    for (int r = 0; r < 4; r++) {
        for (int c = 0; c < 4; c++) {
            float sum = 0;
            for (int k = 0; k < 4; k++) {
                sum += projMatrix[r*4 + k] * viewMatrix[k*4 + c];
            }
            vp[r*4 + c] = sum;
        }
    }

    float clip[4];
    float world[4] = {worldPos[0], worldPos[1], worldPos[2], 1.0f};
    mat4_mul_vec4(vp, world, clip);

    if (clip[3] < 0.001f) return NO;

    float ndcX = clip[0] / clip[3];
    float ndcY = clip[1] / clip[3];

    screenPos[0] = (ndcX + 1.0f) * 0.5f * width;
    screenPos[1] = (1.0f - ndcY) * 0.5f * height;
    screenPos[2] = clip[3]; // depth

    return (screenPos[0] >= 0 && screenPos[0] <= width &&
            screenPos[1] >= 0 && screenPos[1] <= height);
}

// 从游戏内存读取 ViewMatrix 和 ProjectionMatrix
- (BOOL)readGameMatrices:(mach_port_t)gameTask
              viewMatrix:(float[16])viewMatrix
           projectMatrix:(float[16])projMatrix {
    if (gameTask == MACH_PORT_NULL) return NO;

    // 相机管理器偏移 (游戏特定, 需要运行时扫描)
    uint64_t camMgr = g_game_offsets.camera_manager;
    if (!camMgr) return NO;

    size_t sz = 16 * sizeof(float);

    // 读取 ViewMatrix (4x4, column-major)
    if (kern_reading(gameTask, camMgr + 0x10, viewMatrix, &sz) != KERN_SUCCESS) return NO;

    // 读取 ProjectionMatrix
    sz = 16 * sizeof(float);
    if (kern_reading(gameTask, camMgr + 0x50, projMatrix, &sz) != KERN_SUCCESS) return NO;

    return YES;
}

- (void)renderESPWithViewMatrix:(float *)viewMatrix
                  projectMatrix:(float *)projMatrix
                           width:(float)screenW
                          height:(float)screenH {
    if (!viewMatrix || !projMatrix) return;

    ImDrawList *drawList = ImGui::GetForegroundDrawList();

    for (int i = 0; i < _entityCount; i++) {
        EntityData *ent = &_entities[i];
        if (!ent->is_valid || ent->health <= 0) continue;

        float screenPos[3];
        if (![self worldToScreen:ent->position
                      viewMatrix:viewMatrix
                   projectMatrix:projMatrix
                           width:screenW height:screenH
                             out:screenPos]) continue;

        // ESP 颜色: 可见=黄色, 不可见=红色
        ImU32 color = ent->visible ? IM_COL32(255, 200, 0, 255) : IM_COL32(255, 50, 50, 255);

        // 方框高度基于距离
        float dist = screenPos[2];
        float boxH = (2000.0f / (dist + 1.0f)) * (screenH / 1080.0f);
        float boxW = boxH * 0.5f;

        float x = screenPos[0];
        float y = screenPos[1];
        float x1 = x - boxW / 2;
        float y1 = y - boxH;
        float x2 = x + boxW / 2;
        float y2 = y;

        // === 方框 (2px 边框 + 1px 外轮廓) ===
        drawList->AddRect(ImVec2(x1-1, y1-1), ImVec2(x2+1, y2+1),
                          IM_COL32(0,0,0,180), 0, 0, 1.5f);
        drawList->AddRect(ImVec2(x1, y1), ImVec2(x2, y2), color, 0, 0, 2.0f);

        // === 血条 ===
        float hpPercent = ent->health / 100.0f;
        if (hpPercent > 1.0f) hpPercent = 1.0f;
        float barX = x1 - 8;
        float barH = boxH * hpPercent;
        drawList->AddRectFilled(ImVec2(barX-2, y1-1), ImVec2(barX+2, y2+1),
                                IM_COL32(0,0,0,120));
        ImU32 hpColor = hpPercent > 0.6f ? IM_COL32(0,255,100,220) :
                        hpPercent > 0.3f ? IM_COL32(255,200,0,220) :
                                           IM_COL32(255,50,50,220);
        drawList->AddRectFilled(ImVec2(barX-1.5f, y2 - barH),
                                ImVec2(barX+1.5f, y2), hpColor);

        // === 距离标签 ===
        char distText[32];
        snprintf(distText, sizeof(distText), "%.0fm", dist / 100.0f);
        drawList->AddText(ImVec2(x, y2 + 2), IM_COL32(255,255,255,200), distText);

        // === 名字 (如果有) ===
        if (strlen(ent->name) > 0 && strlen(ent->name) < 63) {
            drawList->AddText(ImVec2(x, y1 - 16), IM_COL32(255,255,255,200), ent->name);
        }

        // === 血量数字 ===
        char hpText[16];
        snprintf(hpText, sizeof(hpText), "%dHP", (int)ent->health);
        drawList->AddText(ImVec2(x, y1 - 28), color, hpText);

        // === 头部瞄准线 ===
        float headY = y1 + boxH * 0.15f;
        float lineLen = boxW * 0.6f;
        drawList->AddLine(ImVec2(x, headY), ImVec2(x - lineLen, headY - lineLen * 0.5f),
                          color, 1.0f);
        drawList->AddLine(ImVec2(x, headY), ImVec2(x + lineLen, headY - lineLen * 0.5f),
                          color, 1.0f);
    }
}

- (int)entityCount { return _entityCount; }
- (EntityData *)entities { return _entities; }

@end
