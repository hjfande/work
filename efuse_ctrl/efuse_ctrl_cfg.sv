`ifndef EFUSE_CTRL_CFG_SV
`define EFUSE_CTRL_CFG_SV

//----------------------------------------------------------------------------
// eFuse Controller Configuration Object
//----------------------------------------------------------------------------
class efuse_ctrl_cfg extends uvm_object;

  `uvm_object_utils_begin(efuse_ctrl_cfg)
    `uvm_field_int(READ_UPDATE_SRAM,       UVM_ALL_ON)
    `uvm_field_int(lcs_state,              UVM_ALL_ON)
    `uvm_field_int(top_region_wr_disable,  UVM_ALL_ON)
    `uvm_field_int(top_region_rd_disable,  UVM_ALL_ON)
    `uvm_field_int(shadow_sram_acc_bit,    UVM_ALL_ON)
    `uvm_field_int(top_acc_sec_region_bit, UVM_ALL_ON)
    `uvm_field_int(pslverr_check_enable,   UVM_ALL_ON)
  `uvm_object_utils_end

  // Update DUT SRAM from fuse read data (default disabled)
  rand bit READ_UPDATE_SRAM = 1'b0;

  // Life cycle state
  rand bit [3:0] lcs_state;

  // Region access disable settings (bit[i] -> region_res_i)
  rand bit [7:0] top_region_wr_disable;
  rand bit [7:0] top_region_rd_disable;

  // 0 = allow shadow SRAM access, 1 = prohibit
  rand bit shadow_sram_acc_bit = 1'b0;

  // 0 = allow public master secure region access, 1 = prohibit
  rand bit top_acc_sec_region_bit = 1'b0;

  // 1 = enable PSLVERR checking in scoreboard, 0 = skip PSLVERR checks
  bit pslverr_check_enable = 1'b0;

  // LCS_STATE constraint: only CM/DM/DD/DR are valid
  constraint lcs_state_c {
    lcs_state inside {4'b0000, 4'b0001, 4'b0011, 4'b0111};
  }

  function new(string name = "efuse_ctrl_cfg");
    super.new(name);
  endfunction

endclass

`endif // EFUSE_CTRL_CFG_SV
