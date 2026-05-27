//===========================================================================
// 中断分发器 - Bit级独立映射检查 SVA + 边沿统计 (VC Formal compatible)
//   无打印输出，无fatal/error/display/final/initial
//===========================================================================

module int_distributor_posedge_sva #(
    parameter int INT_VALID_MIN_DELAY = 5
)(
    input  logic        clk,
    input  logic        rstn,
    input  logic        posedge_bit,
    input  logic        edge_bit,
    input  logic [63:0] posedge_rise_cnt,
    input  logic [63:0] posedge_fall_cnt,
    input  logic [63:0] edge_rise_cnt,
    input  logic [63:0] edge_fall_cnt
);
    // 约束: 两个有效中断(上升沿)之间的间隔大于 INT_VALID_MIN_DELAY
    property p_min_delay;
        @(posedge clk) disable iff (!rstn)
        $rose(posedge_bit) |-> ##1 (!($rose(posedge_bit)) [*INT_VALID_MIN_DELAY-1]);
    endproperty
    asm_min_delay: assume property (p_min_delay);

    property p_rise;
        @(posedge clk) disable iff (!rstn)
        $rose(posedge_bit) |-> $rose(edge_bit);
    endproperty
    ast_rise: assert property (p_rise);

    property p_rise_count;
        @(posedge clk) disable iff (!rstn)
        posedge_rise_cnt == edge_rise_cnt;
    endproperty
    ast_rise_count: assert property (p_rise_count);

    cov_rise: cover property (@(posedge clk) disable iff (!rstn) $rose(posedge_bit));
    cov_fall: cover property (@(posedge clk) disable iff (!rstn) $fell(posedge_bit));
endmodule

module int_distributor_negedge_sva #(
    parameter int INT_VALID_MIN_DELAY = 5
)(
    input  logic        clk,
    input  logic        rstn,
    input  logic        negedge_bit,
    input  logic        edge_bit,
    input  logic [63:0] negedge_rise_cnt,
    input  logic [63:0] negedge_fall_cnt,
    input  logic [63:0] edge_rise_cnt,
    input  logic [63:0] edge_fall_cnt
);
    // 约束: 两个有效中断(下降沿)之间的间隔大于 INT_VALID_MIN_DELAY
    property p_min_delay;
        @(posedge clk) disable iff (!rstn)
        $fell(negedge_bit) |-> ##1 (!($fell(negedge_bit)) [*INT_VALID_MIN_DELAY-1]);
    endproperty
    asm_min_delay: assume property (p_min_delay);

    property p_fall_to_rise;
        @(posedge clk) disable iff (!rstn)
        $fell(negedge_bit) |-> $rose(edge_bit);
    endproperty
    ast_fall_to_rise: assert property (p_fall_to_rise);

    property p_fall_count;
        @(posedge clk) disable iff (!rstn)
        negedge_fall_cnt == edge_rise_cnt;
    endproperty
    ast_fall_count: assert property (p_fall_count);

    cov_rise: cover property (@(posedge clk) disable iff (!rstn) $rose(negedge_bit));
    cov_fall: cover property (@(posedge clk) disable iff (!rstn) $fell(negedge_bit));
endmodule

module int_distributor_high_level_sva (
    input  logic        clk,
    input  logic        rstn,
    input  logic        high_level_bit,
    input  logic        level_bit
);
    property p_eq;
        @(posedge clk) disable iff (!rstn)
        high_level_bit == level_bit;
    endproperty
    ast_eq: assert property (p_eq);

    cov_rise: cover property (@(posedge clk) disable iff (!rstn) $rose(high_level_bit));
    cov_fall: cover property (@(posedge clk) disable iff (!rstn) $fell(high_level_bit));
endmodule

module int_distributor_low_level_sva (
    input  logic        clk,
    input  logic        rstn,
    input  logic        low_level_bit,
    input  logic        level_bit
);
    property p_eq;
        @(posedge clk) disable iff (!rstn)
        low_level_bit == ~level_bit;
    endproperty
    ast_eq: assert property (p_eq);

    cov_rise: cover property (@(posedge clk) disable iff (!rstn) $rose(low_level_bit));
    cov_fall: cover property (@(posedge clk) disable iff (!rstn) $fell(low_level_bit));
endmodule

module int_distributor_merge_sva #(
    parameter int BUS_WIDTH = 32
)(
    input  logic        clk,
    input  logic        rstn,
    input  logic        merge_group_bit,
    input  logic        merge_ic_bit,
    input  logic [BUS_WIDTH-1:0] merge_bus
);

    property p_eq;
        @(posedge clk) disable iff (!rstn)
        merge_group_bit == merge_ic_bit;
    endproperty
    ast_eq: assert property (p_eq);

endmodule

module int_distributor_sva #(
    parameter int POS_EDGE_INT_NUM   = 32,
    parameter int NEG_EDGE_INT_NUM   = 32,
    parameter int HIGH_LEVEL_INT_NUM = 32,
    parameter int LOW_LEVEL_INT_NUM  = 32,

    parameter int EDGE_INT_TO_IC_WIDTH  = POS_EDGE_INT_NUM + NEG_EDGE_INT_NUM,
    parameter int LEVEL_INT_TO_IC_WIDTH = HIGH_LEVEL_INT_NUM + LOW_LEVEL_INT_NUM,
    parameter int MERGE_INT_TO_IC_WIDTH = (HIGH_LEVEL_INT_NUM + LOW_LEVEL_INT_NUM + 31) / 32,

    parameter int MERGE_ORDER = 0,

    parameter int POS_EDGE_INT_VALID_MIN_DELAY   = 5,
    parameter int NEG_EDGE_INT_VALID_MIN_DELAY   = 5,
    parameter int HIGH_LEVEL_INT_VALID_MIN_DELAY = 5,
    parameter int LOW_LEVEL_INT_VALID_MIN_DELAY  = 5,
    parameter int MERGE_INT_VALID_MIN_DELAY      = 5,
    parameter bit USE_REGBANK_PIN  = 0,

    parameter logic [POS_EDGE_INT_NUM-1:0]   POS_EDGE_INT_BITMAP   = '1,
    parameter logic [NEG_EDGE_INT_NUM-1:0]   NEG_EDGE_INT_BITMAP   = '1,
    parameter logic [HIGH_LEVEL_INT_NUM-1:0] HIGH_LEVEL_INT_BITMAP = '1,
    parameter logic [LOW_LEVEL_INT_NUM-1:0]  LOW_LEVEL_INT_BITMAP  = '1
)(
    input logic                           apb_clk,
    input logic                           apb_rstn,
    // 中断输入和输出
    input logic [POS_EDGE_INT_NUM-1:0]    posedge_int_bus,
    input logic [NEG_EDGE_INT_NUM-1:0]    negedge_int_bus,
    input logic [HIGH_LEVEL_INT_NUM-1:0]  high_level_int_bus,
    input logic [LOW_LEVEL_INT_NUM-1:0]   low_level_int_bus,
    input logic [HIGH_LEVEL_INT_NUM-1:0]  high_level_enable,
    input logic [HIGH_LEVEL_INT_NUM-1:0]  high_level_mask,
    input logic [LOW_LEVEL_INT_NUM-1:0]   low_level_enable,
    input logic [LOW_LEVEL_INT_NUM-1:0]   low_level_mask,
    input logic [EDGE_INT_TO_IC_WIDTH-1:0]  edge_int_to_ic,
    input logic [LEVEL_INT_TO_IC_WIDTH-1:0] level_int_to_ic,
    input logic [MERGE_INT_TO_IC_WIDTH-1:0] merge_int_to_ic,
    input logic [HIGH_LEVEL_INT_NUM+LOW_LEVEL_INT_NUM-1:0] regbank_merge_int_bus,
    input logic [HIGH_LEVEL_INT_NUM+LOW_LEVEL_INT_NUM-1:0] merge_int_bus
);

    localparam int MERGE_BUS_WIDTH   = HIGH_LEVEL_INT_NUM + LOW_LEVEL_INT_NUM;
    localparam int MERGE_GROUP_NUM   = (MERGE_BUS_WIDTH + 31) / 32;

    logic [MERGE_BUS_WIDTH-1:0]    merge_int_bus_seperate;
    logic [MERGE_GROUP_NUM-1:0]    merge_int_bus_group;

    assign merge_int_bus_seperate = USE_REGBANK_PIN ? regbank_merge_int_bus : merge_int_bus;

    generate
        for (genvar g = 0; g < MERGE_GROUP_NUM; g++) begin : g_merge_group
            localparam int BASE_IDX = g * 32;
            localparam int END_IDX  = (g == MERGE_GROUP_NUM-1) ? MERGE_BUS_WIDTH-1 : BASE_IDX + 31;
            assign merge_int_bus_group[g] = |merge_int_bus_seperate[END_IDX:BASE_IDX];
        end
    endgenerate

    //===========================================================================
    // 边沿统计模块实例化
    //===========================================================================
    logic [63:0] posedge_int_bus_rise_cnt [POS_EDGE_INT_NUM-1:0];
    logic [63:0] posedge_int_bus_fall_cnt [POS_EDGE_INT_NUM-1:0];
    edge_counter #(.WIDTH(POS_EDGE_INT_NUM)) u_posedge_cnt (.clk(apb_clk),.rstn(apb_rstn),.signal(posedge_int_bus),.rise_cnt(posedge_int_bus_rise_cnt),.fall_cnt(posedge_int_bus_fall_cnt));

    logic [63:0] negedge_int_bus_rise_cnt [NEG_EDGE_INT_NUM-1:0];
    logic [63:0] negedge_int_bus_fall_cnt [NEG_EDGE_INT_NUM-1:0];
    edge_counter #(.WIDTH(NEG_EDGE_INT_NUM)) u_negedge_cnt (.clk(apb_clk),.rstn(apb_rstn),.signal(negedge_int_bus),.rise_cnt(negedge_int_bus_rise_cnt),.fall_cnt(negedge_int_bus_fall_cnt));

    logic [63:0] edge_int_to_ic_rise_cnt [EDGE_INT_TO_IC_WIDTH-1:0];
    logic [63:0] edge_int_to_ic_fall_cnt [EDGE_INT_TO_IC_WIDTH-1:0];
    edge_counter #(.WIDTH(EDGE_INT_TO_IC_WIDTH)) u_edge_ic_cnt (.clk(apb_clk),.rstn(apb_rstn),.signal(edge_int_to_ic),.rise_cnt(edge_int_to_ic_rise_cnt),.fall_cnt(edge_int_to_ic_fall_cnt));

    //===========================================================================
    // SVA: posedge_int_bus → edge_int_to_ic
    //===========================================================================
    generate
        for (genvar i = 0; i < POS_EDGE_INT_NUM; i++) begin : g_posedge_sva
            if (POS_EDGE_INT_BITMAP[i]) begin : g_posedge_valid
                localparam int OUT_IDX = (MERGE_ORDER == 0)
                    ? ($countones(NEG_EDGE_INT_BITMAP) + $countones(POS_EDGE_INT_BITMAP[i:0]) - 1)
                    : ($countones(POS_EDGE_INT_BITMAP[i:0]) - 1);
                int_distributor_posedge_sva #(
                    .INT_VALID_MIN_DELAY(POS_EDGE_INT_VALID_MIN_DELAY)
                ) u_posedge_sva (
                    .clk             (apb_clk),
                    .rstn            (apb_rstn),
                    .posedge_bit     (posedge_int_bus[i]),
                    .edge_bit        (edge_int_to_ic[OUT_IDX]),
                    .posedge_rise_cnt(posedge_int_bus_rise_cnt[i]),
                    .posedge_fall_cnt(posedge_int_bus_fall_cnt[i]),
                    .edge_rise_cnt   (edge_int_to_ic_rise_cnt[OUT_IDX]),
                    .edge_fall_cnt   (edge_int_to_ic_fall_cnt[OUT_IDX])
                );
            end
        end
    endgenerate

    //===========================================================================
    // SVA: negedge_int_bus → edge_int_to_ic (反转)
    //===========================================================================
    generate
        for (genvar i = 0; i < NEG_EDGE_INT_NUM; i++) begin : g_negedge_sva
            if (NEG_EDGE_INT_BITMAP[i]) begin : g_negedge_valid
                localparam int OUT_IDX = (MERGE_ORDER == 0)
                    ? ($countones(NEG_EDGE_INT_BITMAP[i:0]) - 1)
                    : ($countones(POS_EDGE_INT_BITMAP) + $countones(NEG_EDGE_INT_BITMAP[i:0]) - 1);
                int_distributor_negedge_sva #(
                    .INT_VALID_MIN_DELAY(NEG_EDGE_INT_VALID_MIN_DELAY)
                ) u_negedge_sva (
                    .clk             (apb_clk),
                    .rstn            (apb_rstn),
                    .negedge_bit     (negedge_int_bus[i]),
                    .edge_bit        (edge_int_to_ic[OUT_IDX]),
                    .negedge_rise_cnt(negedge_int_bus_rise_cnt[i]),
                    .negedge_fall_cnt(negedge_int_bus_fall_cnt[i]),
                    .edge_rise_cnt   (edge_int_to_ic_rise_cnt[OUT_IDX]),
                    .edge_fall_cnt   (edge_int_to_ic_fall_cnt[OUT_IDX])
                );
            end
        end
    endgenerate

    //===========================================================================
    // SVA: high_level_int_bus → level_int_to_ic
    //===========================================================================
    generate
        for (genvar i = 0; i < HIGH_LEVEL_INT_NUM; i++) begin : g_high_level_sva
            if (HIGH_LEVEL_INT_BITMAP[i]) begin : g_high_level_valid
                localparam int OUT_IDX = (MERGE_ORDER == 0)
                    ? ($countones(LOW_LEVEL_INT_BITMAP) + $countones(HIGH_LEVEL_INT_BITMAP[i:0]) - 1)
                    : ($countones(HIGH_LEVEL_INT_BITMAP[i:0]) - 1);
                int_distributor_high_level_sva u_high_level_sva (
                    .clk                (apb_clk),
                    .rstn               (apb_rstn),
                    .high_level_bit     (high_level_int_bus[i]),
                    .level_bit          (level_int_to_ic[OUT_IDX])
                );
            end
        end
    endgenerate

    //===========================================================================
    // SVA: low_level_int_bus → level_int_to_ic (反转)
    //===========================================================================
    generate
        for (genvar i = 0; i < LOW_LEVEL_INT_NUM; i++) begin : g_low_level_sva
            if (LOW_LEVEL_INT_BITMAP[i]) begin : g_low_level_valid
                localparam int OUT_IDX = (MERGE_ORDER == 0)
                    ? ($countones(LOW_LEVEL_INT_BITMAP[i:0]) - 1)
                    : ($countones(HIGH_LEVEL_INT_BITMAP) + $countones(LOW_LEVEL_INT_BITMAP[i:0]) - 1);
                int_distributor_low_level_sva u_low_level_sva (
                    .clk                (apb_clk),
                    .rstn               (apb_rstn),
                    .low_level_bit      (low_level_int_bus[i]),
                    .level_bit          (level_int_to_ic[OUT_IDX])
                );
            end
        end
    endgenerate

    //===========================================================================
    // SVA: merge_int_bus_group → merge_int_to_ic
    //===========================================================================
    generate
        for (genvar g = 0; g < MERGE_GROUP_NUM; g++) begin : g_merge_sva
            localparam int BASE_IDX = g * 32;
            localparam int END_IDX  = (g == MERGE_GROUP_NUM-1) ? MERGE_BUS_WIDTH-1 : BASE_IDX + 31;
            localparam int WIDTH    = END_IDX - BASE_IDX + 1;
            int_distributor_merge_sva #(
                .BUS_WIDTH(WIDTH)
            ) u_merge_sva (
                .clk                 (apb_clk),
                .rstn                (apb_rstn),
                .merge_group_bit     (merge_int_bus_group[g]),
                .merge_ic_bit        (merge_int_to_ic[g]),
                .merge_bus           (merge_int_bus_seperate[END_IDX:BASE_IDX])
            );
        end
    endgenerate

endmodule

//===========================================================================
// 边沿计数器子模块
//===========================================================================
module edge_counter #(
    parameter int WIDTH = 1
)(
    input  logic              clk,
    input  logic              rstn,
    input  logic [WIDTH-1:0]  signal,
    output logic [63:0]       rise_cnt [WIDTH-1:0],
    output logic [63:0]       fall_cnt [WIDTH-1:0]
);

    always_ff @(posedge clk) begin
        if (!rstn) begin
            foreach (rise_cnt[i]) rise_cnt[i] <= '0;
            foreach (fall_cnt[i]) fall_cnt[i] <= '0;
        end else begin
            for (int i = 0; i < WIDTH; i++) begin
                if ($rose(signal[i])) rise_cnt[i] <= rise_cnt[i] + 1;
                if ($fell(signal[i])) fall_cnt[i] <= fall_cnt[i] + 1;
            end
        end
    end

endmodule

//===========================================================================
// 绑定模块 (Bind Interface)
//===========================================================================
bind int_distributor int_distributor_sva #(
    .POS_EDGE_INT_NUM      (POS_EDGE_INT_NUM),
    .NEG_EDGE_INT_NUM      (NEG_EDGE_INT_NUM),
    .HIGH_LEVEL_INT_NUM    (HIGH_LEVEL_INT_NUM),
    .LOW_LEVEL_INT_NUM     (LOW_LEVEL_INT_NUM),
    .EDGE_INT_TO_IC_WIDTH  (POS_EDGE_INT_NUM + NEG_EDGE_INT_NUM),
    .LEVEL_INT_TO_IC_WIDTH (HIGH_LEVEL_INT_NUM + LOW_LEVEL_INT_NUM),
    .MERGE_INT_TO_IC_WIDTH ((HIGH_LEVEL_INT_NUM + LOW_LEVEL_INT_NUM + 31) / 32),
    .MERGE_ORDER           (0)
) u_int_distributor_sva (
    .apb_clk            (apb_clk),
    .apb_rstn           (apb_rstn),
    .posedge_int_bus    (posedge_int_bus),
    .negedge_int_bus    (negedge_int_bus),
    .high_level_int_bus (high_level_int_bus),
    .low_level_int_bus  (low_level_int_bus),
    .high_level_enable  (high_level_enable),
    .high_level_mask    (high_level_mask),
    .low_level_enable   (low_level_enable),
    .low_level_mask     (low_level_mask),
    .edge_int_to_ic     (edge_int_to_ic),
    .level_int_to_ic    (level_int_to_ic),
    .merge_int_to_ic    (merge_int_to_ic),
    .merge_int_bus      ()
);
