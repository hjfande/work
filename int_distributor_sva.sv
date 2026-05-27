//===========================================================================
// 中断分发器 - Bit级独立映射检查 SVA + 边沿统计 (VC Formal compatible)
// 无打印输出，无fatal/error/display/final/initial
// 借用edge_detect模块的edge_detect_fpv检查edge中断
//===========================================================================

module int_distributor_high_level_sva (
    input  logic clk,
    input  logic rst_n,
    input  logic high_level_bit,
    input  logic level_bit
);
    property p_eq;
        @(posedge clk) disable iff (!rst_n)
        high_level_bit == level_bit;
    endproperty
    ast_eq: assert property (p_eq);
endmodule

module int_distributor_low_level_sva (
    input  logic clk,
    input  logic rst_n,
    input  logic low_level_bit,
    input  logic level_bit
);
    property p_eq;
        @(posedge clk) disable iff (!rst_n)
        low_level_bit == ~level_bit;
    endproperty
    ast_eq: assert property (p_eq);
endmodule

module int_distributor_merge_sva #(
    parameter int BUS_WIDTH = 32
)(
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 merge_group_bit,
    input  logic                 merge_ic_bit,
    input  logic [BUS_WIDTH-1:0] merge_bus
);

    property p_eq;
        @(posedge clk) disable iff (!rst_n)
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

    parameter int EDGE_DETECT_SYNC_NUM   = 2,
    parameter bit USE_REGBANK_PIN        = 1,

    parameter logic [POS_EDGE_INT_NUM-1:0]   POS_EDGE_INT_BITMAP   = '1,
    parameter logic [NEG_EDGE_INT_NUM-1:0]   NEG_EDGE_INT_BITMAP   = '1,
    parameter logic [HIGH_LEVEL_INT_NUM-1:0] HIGH_LEVEL_INT_BITMAP = '1,
    parameter logic [LOW_LEVEL_INT_NUM-1:0]  LOW_LEVEL_INT_BITMAP  = '1
)(
    input logic                                            apb_clk,
    input logic                                            apb_rstn,
    // 中断输入和输出
    input logic [POS_EDGE_INT_NUM-1:0]                     posedge_int_bus,
    input logic [NEG_EDGE_INT_NUM-1:0]                     negedge_int_bus,
    input logic [HIGH_LEVEL_INT_NUM-1:0]                   high_level_int_bus,
    input logic [LOW_LEVEL_INT_NUM-1:0]                    low_level_int_bus,
    input logic [HIGH_LEVEL_INT_NUM-1:0]                   high_level_enable,
    input logic [HIGH_LEVEL_INT_NUM-1:0]                   high_level_mask,
    input logic [LOW_LEVEL_INT_NUM-1:0]                    low_level_enable,
    input logic [LOW_LEVEL_INT_NUM-1:0]                    low_level_mask,
    input logic [EDGE_INT_TO_IC_WIDTH-1:0]                 edge_int_to_ic,
    input logic [LEVEL_INT_TO_IC_WIDTH-1:0]                level_int_to_ic,
    input logic [MERGE_INT_TO_IC_WIDTH-1:0]                merge_int_to_ic,
    input logic [HIGH_LEVEL_INT_NUM+LOW_LEVEL_INT_NUM-1:0] regbank_merge_int_bus,
    input logic [HIGH_LEVEL_INT_NUM+LOW_LEVEL_INT_NUM-1:0] merge_int_bus,
    input logic                                            dft_dc_scan_clk,
    input logic                                            dft_dc_scan_mode,
    input logic                                            dft_dc_scan_rst_n
);

    localparam int MERGE_BUS_WIDTH = HIGH_LEVEL_INT_NUM + LOW_LEVEL_INT_NUM;
    localparam int MERGE_GROUP_NUM = (MERGE_BUS_WIDTH + 31) / 32;

    logic [MERGE_BUS_WIDTH-1:0] merge_int_bus_seperate;
    logic [MERGE_GROUP_NUM-1:0] merge_int_bus_group;

    assign merge_int_bus_seperate = USE_REGBANK_PIN ? regbank_merge_int_bus : merge_int_bus;

    generate
        for (genvar g = 0; g < MERGE_GROUP_NUM; g++) begin : g_merge_group
            localparam int BASE_IDX = g * 32;
            localparam int END_IDX  = (g == MERGE_GROUP_NUM-1) ? MERGE_BUS_WIDTH-1 : BASE_IDX + 31;
            assign merge_int_bus_group[g] = |merge_int_bus_seperate[END_IDX:BASE_IDX];
        end
    endgenerate

    //===========================================================================
    // SVA: posedge_int_bus → edge_int_to_ic
    //===========================================================================
    generate
        for (genvar i = 0; i < POS_EDGE_INT_NUM; i++) begin : g_posedge_sva
            if (POS_EDGE_INT_BITMAP[i]) begin : g_posedge_valid
                localparam int OUT_IDX = (MERGE_ORDER == 0)
                    ? ($countones(NEG_EDGE_INT_BITMAP) + $countones(POS_EDGE_INT_BITMAP[i:0]) - 1)
                    : ($countones(POS_EDGE_INT_BITMAP[i:0]) - 1);
                edge_detect_fpv #(
                    .SYNC_NUM(EDGE_DETECT_SYNC_NUM)
                ) u_posedge_sva (
                    .clk               (apb_clk),
                    .rst_n             (apb_rstn),
                    .edge_in           (posedge_int_bus[i]),
                    .async_edge        (edge_int_to_ic[OUT_IDX]),
                    .dft_dc_scan_clk   (dft_dc_scan_clk),
                    .dft_dc_scan_mode  (dft_dc_scan_mode),
                    .dft_dc_scan_rst_n (dft_dc_scan_rst_n)
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
                edge_detect_fpv #(
                    .SYNC_NUM(EDGE_DETECT_SYNC_NUM)
                ) u_negedge_sva (
                    .clk               (apb_clk),
                    .rst_n             (apb_rstn),
                    .edge_in           (~negedge_int_bus[i]),
                    .async_edge        (edge_int_to_ic[OUT_IDX]),
                    .dft_dc_scan_clk   (dft_dc_scan_clk),
                    .dft_dc_scan_mode  (dft_dc_scan_mode),
                    .dft_dc_scan_rst_n (dft_dc_scan_rst_n)
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
                    .clk            (apb_clk),
                    .rst_n          (apb_rstn),
                    .high_level_bit (high_level_int_bus[i]),
                    .level_bit      (level_int_to_ic[OUT_IDX])
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
                    .clk           (apb_clk),
                    .rst_n         (apb_rstn),
                    .low_level_bit (low_level_int_bus[i]),
                    .level_bit     (level_int_to_ic[OUT_IDX])
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
                .clk             (apb_clk),
                .rst_n           (apb_rstn),
                .merge_group_bit (merge_int_bus_group[g]),
                .merge_ic_bit    (merge_int_to_ic[g]),
                .merge_bus       (merge_int_bus_seperate[END_IDX:BASE_IDX])
            );
        end
    endgenerate

endmodule
