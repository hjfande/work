module high_checker (
    input  logic clk,
    input  logic rst_n,
    input  logic high_level_bit,
    input  logic level_bit
);
    property p_eq;
        @(high_level_bit) disable iff (!rst_n)
        high_level_bit == level_bit;
    endproperty
    ast_eq: assert property (p_eq);

    property p_rose;
        @(posedge high_level_bit) disable iff (!rst_n)
        1;
    endproperty
    cov_rose: cover property (p_rose);

    property p_fell;
        @(negedge high_level_bit) disable iff (!rst_n)
        1;
    endproperty
    cov_fell: cover property (p_fell);
endmodule

module low_checker (
    input  logic clk,
    input  logic rst_n,
    input  logic low_level_bit,
    input  logic level_bit
);
    property p_eq;
        @(low_level_bit) disable iff (!rst_n)
        low_level_bit == ~level_bit;
    endproperty
    ast_eq: assert property (p_eq);

    property p_rose;
        @(posedge low_level_bit) disable iff (!rst_n)
        1;
    endproperty
    cov_rose: cover property (p_rose);

    property p_fell;
        @(negedge low_level_bit) disable iff (!rst_n)
        1;
    endproperty
    cov_fell: cover property (p_fell);
endmodule

module merge_sva #(
    parameter int BUS_WIDTH = 32
)(
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 merge_ic_bit,
    input  logic [BUS_WIDTH-1:0] merge_bus,
    input  logic [BUS_WIDTH-1:0] merge_bus_enable,
    input  logic [BUS_WIDTH-1:0] merge_bus_mask,
    input  logic [BUS_WIDTH-1:0] merge_bus_set,
    input  logic [BUS_WIDTH-1:0] merge_bus_regbank
);

    logic merge_regbank_group_bit;
    assign merge_regbank_group_bit = |merge_bus_regbank;
    property p_eq(in,out);
        @(in) disable iff (!rst_n)
        in == out;
    endproperty

    property p_rose(in);
        @(posedge in) disable iff (!rst_n)
        1;
    endproperty

    property p_fell(in);
        @(negedge in) disable iff (!rst_n)
        1;
    endproperty

    ast_regbank_to_ic_eq: assert property (p_eq(merge_regbank_group_bit, merge_ic_bit));
    cov_regbank_rose: cover property (p_rose(merge_regbank_group_bit));
    cov_regbank_fell: cover property (p_fell(merge_regbank_group_bit));
endmodule