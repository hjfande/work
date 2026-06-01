//===========================================================================
// Cover Property Example: IDLE → preset_n low → preset_n high → IDLE
//===========================================================================

typedef enum logic [1:0] {
    IDLE = 2'b00,
    BUSY = 2'b01,
    DONE = 2'b10
} state_t;

module cover_example (
    input logic clk,
    input logic preset_n,   // active-low reset
    input state_t state
);

    //-----------------------------------------------------------------------
    // 方案1：基本版 — 检测 preset_n 低电平再恢复，状态保持/回到 IDLE
    //-----------------------------------------------------------------------
    cov_preset_n_pulse_idle : cover property (@(posedge clk)
        // 初始在 IDLE
        (state == IDLE) ##1
        // preset_n 拉低（低电平有效复位）
        (!preset_n) ##[*1:$]
        // preset_n 恢复高电平
        (preset_n) ##1
        // 状态回到 IDLE
        (state == IDLE)
    );

    //-----------------------------------------------------------------------
    // 方案2：严格边沿版 — 使用 $fell/$rose 检测同步后的 preset_n
    // （仅当 preset_n 已同步到 clk 域时使用）
    //-----------------------------------------------------------------------
    cov_preset_n_edge_idle : cover property (@(posedge clk)
        (state == IDLE) ##1
        $fell(preset_n) ##[*1:$]
        $rose(preset_n) ##1
        (state == IDLE)
    );

    //-----------------------------------------------------------------------
    // 方案3：带最大延迟约束 — 限制复位脉冲宽度在 1~10 个周期内
    //-----------------------------------------------------------------------
    cov_preset_n_pulse_bounded : cover property (@(posedge clk)
        (state == IDLE) ##1
        (!preset_n) ##[1:10]
        (preset_n) ##1
        (state == IDLE)
    );

    //-----------------------------------------------------------------------
    // 方案4：多时钟版 — 异步 preset_n 用多时钟 property
    // （更精确地捕获异步边沿）
    //-----------------------------------------------------------------------
    cov_preset_n_async : cover property (
        @(posedge preset_n)            // 在 preset_n 上升沿触发
        1 ##0 @(posedge clk)          // 同步到 clk 域
        (state == IDLE)
    );

    //-----------------------------------------------------------------------
    // 方案5：完整复位序列 — 从 IDLE 开始，经历复位，确认回到 IDLE
    // 包含 BUSY 状态被中断后复位回到 IDLE 的场景
    //-----------------------------------------------------------------------
    cov_reset_from_busy : cover property (@(posedge clk)
        (state == IDLE) ##1
        (!preset_n) ##[*1:5]
        (preset_n) ##1
        (state == IDLE)
    );

endmodule
