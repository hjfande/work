`ifndef EFUSE_CTRL_CFG_SV
`define EFUSE_CTRL_CFG_SV

//----------------------------------------------------------------------------
// Life cycle state enum
//----------------------------------------------------------------------------
typedef enum bit [3:0] {
  LCS_CM = 4'b0000,
  LCS_DM = 4'b0001,
  LCS_DD = 4'b0011,
  LCS_DR = 4'b0111
} lcs_state_e;

//----------------------------------------------------------------------------
// eFuse initialization type enum
//----------------------------------------------------------------------------
typedef enum bit [1:0] {
  INITIAL_ALL_ZERO = 2'b00,
  INITIAL_RAND     = 2'b01
} initial_type_e;

//----------------------------------------------------------------------------
// eFuse Controller Configuration Object
//----------------------------------------------------------------------------
class efuse_ctrl_cfg extends uvm_object;

  `uvm_object_utils_begin(efuse_ctrl_cfg)
    `uvm_field_int(READ_UPDATE_SRAM,       UVM_ALL_ON)
    `uvm_field_enum(lcs_state_e, lcs_state, UVM_ALL_ON)
    `uvm_field_int(top_region_wr_disable,  UVM_ALL_ON)
    `uvm_field_int(top_region_rd_disable,  UVM_ALL_ON)
    `uvm_field_int(shadow_sram_acc_bit,    UVM_ALL_ON)
    `uvm_field_int(top_acc_sec_region_bit, UVM_ALL_ON)
    `uvm_field_enum(initial_type_e, initial_type, UVM_ALL_ON)
    `uvm_field_int(initial_done,           UVM_ALL_ON)
    `uvm_field_int(mode_key_efuse_data,     UVM_ALL_ON)
    `uvm_field_int(device_key_efuse_data,   UVM_ALL_ON)
    `uvm_field_sarray_int(dcu_en_lock_bit,  UVM_ALL_ON)
    `uvm_field_int(boot_cfg_vld,           UVM_ALL_ON)
    `uvm_field_int(rom_patch_hit,          UVM_ALL_ON)
    `uvm_field_sarray_int(rom_patch_addr,  UVM_ALL_ON)
    `uvm_field_sarray_int(rom_patch_data,  UVM_ALL_ON)
    `uvm_field_int(pslverr_check_enable,   UVM_ALL_ON)
    `uvm_field_int(check_trans_before_load_done_by_single, UVM_ALL_ON)
    `uvm_field_int(dft_mode,               UVM_ALL_ON)
    `uvm_field_int(timeout_load_en,        UVM_ALL_ON)
  `uvm_object_utils_end

  // Update DUT SRAM from fuse read data (default disabled)
  rand bit READ_UPDATE_SRAM = 1'b0;

  // Life cycle state
  rand lcs_state_e lcs_state;

  // Region access disable settings (bit[i] -> region_res_i)
  rand bit [7:0] top_region_wr_disable;
  rand bit [7:0] top_region_rd_disable;

  // 0 = allow shadow SRAM access, 1 = prohibit
  rand bit shadow_sram_acc_bit = 1'b0;

  // eFuse/SRAM initialization type when initial_done == 0
  rand initial_type_e initial_type = INITIAL_RAND;
  // Set to 1 after apply_cfg_to_fuse_sram has initialized the memory array
  bit initial_done = 1'b0;

  // 0 = allow public master secure region access, 1 = prohibit
  rand bit top_acc_sec_region_bit = 1'b0;

  // 128-bit MODE_KEY raw eFuse data stored at APB offsets 0x04/0x08/0x0C/0x10.
  // This is the raw (LFSR-encoded) value held in the fuse; on load to SRAM it is
  // LFSR-decoded (except an all-zero raw word, which loads as 0).
  bit [127:0] mode_key_efuse_data;

  // 128-bit DEVICE_KEY raw eFuse data stored at APB offsets 0x18/0x1C/0x20/0x24.
  // Same raw-in-fuse / LFSR-decoded-to-SRAM semantics as mode_key_efuse_data.
  bit [127:0] device_key_efuse_data;

  // DCU_EN lock bits (32-bit x 4 words) starting at APB offset 0x90
  bit [31:0] dcu_en_lock_bit [4];

  // Boot configuration selection value at APB offset 0xA0 bit[31]
  bit boot_cfg_vld = 1'b0;

  // ROM patch hit vector at APB offset 0x13C
  bit [31:0] rom_patch_hit;

  // ROM patch addresses (16-bit x 32 entries) starting at APB offset 0x140
  bit [15:0] rom_patch_addr [32];

  // ROM patch data (32-bit x 32 entries) starting at APB offset 0x180
  bit [31:0] rom_patch_data [32];

  // 1 = enable PSLVERR checking in scoreboard, 0 = skip PSLVERR checks
  bit pslverr_check_enable = 1'b0;

  // 1 = use current efuse_load_done signal to judge before/after load done (default)
  // 0 = use transaction begin_time vs efuse_load_done_time
  bit check_trans_before_load_done_by_single = 1'b0;

  // LCS_STATE constraint: only CM/DM/DD/DR are valid
  constraint lcs_state_c {
    lcs_state inside {LCS_CM, LCS_DM, LCS_DD, LCS_DR};
  }

  // initial_type constraint: only ALL_ZERO/RAND are valid
  constraint initial_type_c {
    initial_type inside {INITIAL_ALL_ZERO, INITIAL_RAND};
  }

  bit dft_mode = 1'b0;
  bit timeout_load_en = 1'b0;

  parameter BOOT_DBG_PIN_SEL_BIT = 0;


  function new(string name = "efuse_ctrl_cfg");
    super.new(name);
  endfunction

endclass

`endif // EFUSE_CTRL_CFG_SV
