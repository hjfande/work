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
    `uvm_field_sarray_int(non_secure_deny_addr, UVM_ALL_ON)
    `uvm_field_int(boot_cfg_vld,           UVM_ALL_ON)
    `uvm_field_int(rom_patch_hit,          UVM_ALL_ON)
    `uvm_field_sarray_int(rom_patch_addr,  UVM_ALL_ON)
    `uvm_field_sarray_int(rom_patch_data,  UVM_ALL_ON)
    `uvm_field_int(pslverr_check_enable,   UVM_ALL_ON)
    `uvm_field_int(check_trans_before_load_done_by_single, UVM_ALL_ON)
    `uvm_field_int(dft_mode,               UVM_ALL_ON)
    `uvm_field_int(timeout_load_en,        UVM_ALL_ON)
  `uvm_object_utils_end

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

  // 128-bit MODE_KEY raw eFuse data stored at EFUSE_CE_MODEL_KEY_ADDR (0x04/0x08/0x0C/0x10).
  // This is the raw (LFSR-encoded) value held in the fuse; on load to SRAM it is
  // LFSR-decoded (except an all-zero raw word, which loads as 0).
  bit [127:0] mode_key_efuse_data;

  // 128-bit DEVICE_KEY raw eFuse data stored at EFUSE_CE_DEVICE_KEY_ADDR (0x18/0x1C/0x20/0x24).
  // Same raw-in-fuse / LFSR-decoded-to-SRAM semantics as mode_key_efuse_data.
  bit [127:0] device_key_efuse_data;

  // DCU_EN lock bits (32-bit x 4 words) starting at EFUSE_TOP_REGION_RES_2_ADDR (0x88)
  bit [31:0] dcu_en_lock_bit [4];

  // APB public master non-eFuse register addresses that deny NON_SECURE access.
  // Read returns 0 with pslverr=0; writes are ignored.
  bit [31:0] non_secure_deny_addr [9];

  // Boot config valid bit (alias of boot_sel_pin valid) at REGION_RES_3
  // APB offset EFUSE_TOP_REGION_RES_3_ADDR, bit[BOOT_CFG_VLD_BIT_MAP]
  bit boot_cfg_vld = 1'b0;

  // ROM patch hit vector at EFUSE_TOP_REGION_RES_7_ADDR (0x13C)
  bit [31:0] rom_patch_hit;

  // ROM patch addresses (16-bit x 32 entries) starting at EFUSE_TOP_REGION_RES_7_ADDR + 0x4 (0x140)
  bit [15:0] rom_patch_addr [32];

  // ROM patch data (32-bit x 32 entries) starting at EFUSE_TOP_REGION_RES_7_ADDR + 0x44 (0x180)
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
    non_secure_deny_addr = '{32'h0, 32'h10, 32'h14, 32'h1c,
                             32'h20, 32'h24, 32'h28, 32'h2c,
                             32'h44};
  endfunction

  //--------------------------------------------------------------------------
  // addr_hit: return 1 if the word-aligned offset hits a region that holds a
  // cfg-controlled field (see cfg_efuse_bit_unchange for the address map).
  //   efuse_offset : eFuse logical byte offset (relative to EFUSE_BASE_ADDR).
  //--------------------------------------------------------------------------
  function bit addr_hit(bit [31:0] efuse_offset);
    bit [31:0] word_addr;
    word_addr = {efuse_offset[31:2], 2'b00};  // 4-byte align
    return (word_addr inside {EFUSE_CE_LCS_STATE_ADDR,
                              EFUSE_TOP_WR_ACC_DIS_ADDR,
                              EFUSE_TOP_RD_ACC_DIS_ADDR,
                              EFUSE_TOP_REGION_RES_2_ADDR,
                              EFUSE_TOP_REGION_RES_3_ADDR,
                              EFUSE_TOP_REGION_RES_4_ADDR + 32'h08});
  endfunction

  //--------------------------------------------------------------------------
  // cfg_efuse_bit_unchange: force the cfg-controlled bits to their cfg values.
  //   efuse_offset : eFuse logical byte offset (relative to EFUSE_BASE_ADDR).
  //   data         : the 32-bit word to be patched.
  // When the word-aligned offset hits a region holding a cfg-controlled field,
  // the corresponding bit(s) in data are overwritten with the cfg value so they
  // stay consistent with cfg; all other bits are left unchanged. Returns the
  // patched data.
  //
  // Offset / bit map (logical byte offset, sourced from efuse_mapping.xlsx):
  //   0x48 [3:0]                         lcs_state
  //   0x74 [7:0]                         top_region_wr_disable
  //   0x78 [7:0]                         top_region_rd_disable
  //   0x88 [0]                           dcu_en_lock_bit[0][0]
  //   0x98 [15]                          boot_cfg_vld
  //   0xA4 [1]  (feature_cfg bit[65])    shadow_sram_acc_bit
  //   0xA4 [0]  (feature_cfg bit[64])    top_acc_sec_region_bit
  //--------------------------------------------------------------------------
  function bit [31:0] cfg_efuse_bit_unchange(bit [31:0] efuse_offset, bit [31:0] data);
    bit [31:0] word_addr;
    bit [31:0] result;

    result = data;
    if (!addr_hit(efuse_offset)) begin
      return result;  // not a cfg-controlled region: leave data unchanged
    end

    word_addr = {efuse_offset[31:2], 2'b00};  // 4-byte align

    case (word_addr)
      EFUSE_CE_LCS_STATE_ADDR:
        result[3:0]  = 4'(lcs_state);
      EFUSE_TOP_WR_ACC_DIS_ADDR:
        result[7:0]  = top_region_wr_disable;
      EFUSE_TOP_RD_ACC_DIS_ADDR:
        result[7:0]  = top_region_rd_disable;
      EFUSE_TOP_REGION_RES_2_ADDR:
        result[0]    = dcu_en_lock_bit[0][0];
      EFUSE_TOP_REGION_RES_3_ADDR:
        result[15]   = boot_cfg_vld;
      EFUSE_TOP_REGION_RES_4_ADDR + 32'h08:  // word 2 of feature_cfg = eFuse Feature CFG
        begin
          result[1] = shadow_sram_acc_bit;     // bit[65] -> word 2 bit[1]
          result[0] = top_acc_sec_region_bit;  // bit[64] -> word 2 bit[0]
        end
      default: ; // unreachable (addr_hit already filtered)
    endcase

    return result;
  endfunction

  //--------------------------------------------------------------------------
  // is_non_secure_deny_reg: return 1 if addr is in non_secure_deny_addr list
  //--------------------------------------------------------------------------
  function bit is_non_secure_deny_reg(bit [31:0] addr);
    foreach (non_secure_deny_addr[i]) begin
      if (addr == non_secure_deny_addr[i]) begin
        return 1'b1;
      end
    end
    return 1'b0;
  endfunction

endclass

`endif // EFUSE_CTRL_CFG_SV
