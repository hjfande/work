//----------------------------------------------------------------------------
// Generated expect calculation functions for efuse_ctrl_scoreboard
// Replaces read_word calls in update_vif_sva_expect_val with direct vif.fuse_data calls
//----------------------------------------------------------------------------

  //==========================================================================
  // Helper: read a 32-bit word from DUT_SRAM via efuse_ctrl_vif.sram_data
  // addr_offset is the logical offset relative to EFUSE_BASE_ADDR
  // SRAM is word-addressable, no primary/shadow split, no LFSR
  //==========================================================================
  function bit [31:0] read_dut_sram_word_via_vif(bit [31:0] addr_offset);
    return efuse_ctrl_vif.sram_data(addr_offset[8:2]);
  endfunction

  //==========================================================================
  // expect_device_id_bit: DUT_SRAM offset 0x8C, 32bit
  //==========================================================================
  function void calc_expect_device_id_bit();
    efuse_ctrl_vif.expect_device_id_bit = read_dut_sram_word_via_vif(32'h8C);
  endfunction

  //==========================================================================
  // expect_feature_cfg_bit: DUT_SRAM offset 0xA4 ~ 0xA8, 64bit
  //==========================================================================
  function void calc_expect_feature_cfg_bit();
    bit [31:0] w0;
    bit [31:0] w1;
    w0 = read_dut_sram_word_via_vif(32'hA4);
    w1 = read_dut_sram_word_via_vif(32'hA8);
    efuse_ctrl_vif.expect_feature_cfg_bit = {w1, w0};
  endfunction

  //==========================================================================
  // expect_memory_cfg_bit: DUT_SRAM offset 0xAC ~ 0xB4, 96bit
  //==========================================================================
  function void calc_expect_memory_cfg_bit();
    bit [31:0] w0;
    bit [31:0] w1;
    bit [31:0] w2;
    w0 = read_dut_sram_word_via_vif(32'hAC);
    w1 = read_dut_sram_word_via_vif(32'hB0);
    w2 = read_dut_sram_word_via_vif(32'hB4);
    efuse_ctrl_vif.expect_memory_cfg_bit = {w2, w1, w0};
  endfunction

  //==========================================================================
  // expect_analog_calibre_bit: DUT_SRAM offset 0xB8 ~ 0xD4, 256bit
  //==========================================================================
  function void calc_expect_analog_calibre_bit();
    bit [31:0] w0;
    bit [31:0] w1;
    bit [31:0] w2;
    bit [31:0] w3;
    bit [31:0] w4;
    bit [31:0] w5;
    bit [31:0] w6;
    bit [31:0] w7;
    w0 = read_dut_sram_word_via_vif(32'hB8);
    w1 = read_dut_sram_word_via_vif(32'hBC);
    w2 = read_dut_sram_word_via_vif(32'hC0);
    w3 = read_dut_sram_word_via_vif(32'hC4);
    w4 = read_dut_sram_word_via_vif(32'hC8);
    w5 = read_dut_sram_word_via_vif(32'hCC);
    w6 = read_dut_sram_word_via_vif(32'hD0);
    w7 = read_dut_sram_word_via_vif(32'hD4);
    efuse_ctrl_vif.expect_analog_calibre_bit = {w7, w6, w5, w4, w3, w2, w1, w0};
  endfunction

  //==========================================================================
  // expect_dcu_en_bit: based on LCS_STATE
  // LCS_DD: efuse_dcu_en | vif.dcu_en_dd & ~DUT_SRAM[0x90:0x9C]
  // Others: vif.dcu_en_xx
  //==========================================================================
  function void calc_expect_dcu_en_bit();
    bit [3:0]  lcs_state;
    bit [31:0] lcs_state_word;
    bit [127:0] dcu_en_src;
    bit [127:0] dcu_en_sram_mask;
    bit [31:0] w0;
    bit [31:0] w1;
    bit [31:0] w2;
    bit [31:0] w3;

    localparam bit [3:0] LCS_CM = 4'b0000;
    localparam bit [3:0] LCS_DM = 4'b0001;
    localparam bit [3:0] LCS_DD = 4'b0011;
    localparam bit [3:0] LCS_DR = 4'b0111;

    lcs_state_word = read_dut_sram_word_via_vif(LCS_STATE_START);
    lcs_state = lcs_state_word[3:0];

    if (lcs_state == LCS_DD) begin
      dcu_en_src = reg_model.efuse_dcu_en.get();
      w0 = read_dut_sram_word_via_vif(32'h90);
      w1 = read_dut_sram_word_via_vif(32'h94);
      w2 = read_dut_sram_word_via_vif(32'h98);
      w3 = read_dut_sram_word_via_vif(32'h9C);
      dcu_en_sram_mask = {w3, w2, w1, w0};
      efuse_ctrl_vif.expect_dcu_en_bit = (dcu_en_src | efuse_ctrl_vif.dcu_en_dd) & ~dcu_en_sram_mask;
    end
    else if (lcs_state == LCS_CM) begin
      efuse_ctrl_vif.expect_dcu_en_bit = efuse_ctrl_vif.dcu_en_cm;
    end
    else if (lcs_state == LCS_DM) begin
      efuse_ctrl_vif.expect_dcu_en_bit = efuse_ctrl_vif.dcu_en_dm;
    end
    else if (lcs_state == LCS_DR) begin
      efuse_ctrl_vif.expect_dcu_en_bit = efuse_ctrl_vif.dcu_en_dr;
    end
    else begin
      `uvm_warning(get_type_name(), $sformatf("calc_expect_dcu_en_bit: unknown LCS_STATE=0x%0x", lcs_state))
      efuse_ctrl_vif.expect_dcu_en_bit = '0;
    end
  endfunction

  //==========================================================================
  // expect_boot_latch_pin: assigned directly to vif signal
  // [BOOT_PIN_NUM-1:8] = vif.boot_strap_pin[BOOT_PIN_NUM-1:8]
  // [7:0] = boot_cfg_bit[7:0] if ~dcu_en[0] & boot_cfg_bit[31], else boot_strap_pin[7:0]
  //==========================================================================
  task calc_expect_boot_latch_pin();
    bit [31:0] boot_cfg_bit;

    boot_cfg_bit = read_dut_sram_word_via_vif(32'hA0);

    efuse_ctrl_vif.expect_boot_latch_pin[efuse_ctrl_vif.BOOT_PIN_NUM-1:8] =
      efuse_ctrl_vif.boot_strap_pin[efuse_ctrl_vif.BOOT_PIN_NUM-1:8];
    if (~efuse_ctrl_vif.expect_dcu_en_bit[0] & boot_cfg_bit[31]) begin
      efuse_ctrl_vif.expect_boot_latch_pin[7:0] = boot_cfg_bit[7:0];
    end else begin
      efuse_ctrl_vif.expect_boot_latch_pin[7:0] = efuse_ctrl_vif.boot_strap_pin[7:0];
    end
  endtask

  //==========================================================================
  // Refactored update_vif_sva_expect_val using generated functions
  //==========================================================================
  task update_vif_sva_expect_val_refactored();
    if (reg_model == null) begin
      `uvm_fatal(get_type_name(), "update_vif_sva_expect_val_refactored: reg_model is null")
    end
    if (efuse_ctrl_vif == null) begin
      `uvm_fatal(get_type_name(), "update_vif_sva_expect_val_refactored: efuse_ctrl_vif is null")
    end

    calc_expect_device_id_bit();
    calc_expect_feature_cfg_bit();
    calc_expect_memory_cfg_bit();
    calc_expect_analog_calibre_bit();
    calc_expect_dcu_en_bit();
    calc_expect_boot_latch_pin();

    `uvm_info(get_type_name(), $sformatf(
      "update_vif_sva_expect_val_refactored: device_id=0x%08x feature_cfg=0x%016x memory_cfg=0x%024x analog=0x%064x dcu_en=0x%032x boot_latch=%p",
      efuse_ctrl_vif.expect_device_id_bit, efuse_ctrl_vif.expect_feature_cfg_bit, efuse_ctrl_vif.expect_memory_cfg_bit,
      efuse_ctrl_vif.expect_analog_calibre_bit, efuse_ctrl_vif.expect_dcu_en_bit, efuse_ctrl_vif.expect_boot_latch_pin
    ), UVM_HIGH)
  endtask
