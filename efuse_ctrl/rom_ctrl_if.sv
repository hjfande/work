interface rom_ctrl_if();

    logic                          rom_ctrl_clk        ;
    logic                          rom_ctrl_rst_n      ;

    //region7:rom patch
    logic  [31:0]                         rom_ctrl_addr       ;
    logic                                 rom_ctrl_addr_vld   ;
    logic  [3:0]                          rom_patch_hit       ;
    logic  [4*32-1:0]                     rom_patch_data      ;
    logic                                 rom_patch_data_vld  ;

    clocking drv_cb@(posedge rom_ctrl_clk);
        input rom_patch_hit, rom_patch_data, rom_patch_data_vld;
        output rom_ctrl_addr, rom_ctrl_addr_vld;
    endclocking

    clocking mon_cb@(posedge rom_ctrl_clk);
        input rom_ctrl_addr, rom_ctrl_addr_vld, rom_patch_hit, rom_patch_data, rom_patch_data_vld;
    endclocking

endinterface //rom_ctrl_if
