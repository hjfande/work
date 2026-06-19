`ifndef EFUSE_CTRL_SCOREBOARD_SV
`define EFUSE_CTRL_SCOREBOARD_SV

// Macro: check_data_match
// Compares expected_data vs actual_data at the given addr.
`define CHECK_DATA_MATCH(addr, expected_data, actual_data, reason) \
  if ((actual_data) !== (expected_data)) begin \
    `uvm_error("efuse_ctrl_scoreboard", $sformatf( \
      "BACKDOOR MISMATCH! addr=0x%08x exp=0x%08x act=0x%08x (%s)", \
      (addr), (expected_data), (actual_data), (reason) \
    )) \
  end else begin \
    `uvm_info("efuse_ctrl_scoreboard", $sformatf( \
      "BACKDOOR PASS: addr=0x%08x data=0x%08x (%s)", \
      (addr), (actual_data), (reason) \
    ), UVM_HIGH) \
  end


class efuse_ctrl_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(efuse_ctrl_scoreboard)

  ral_block_regbank_cfg_efuse_ctrl reg_model;

  // Configuration object
  efuse_ctrl_cfg cfg;

  // Ports to receive transactions from monitors
  uvm_blocking_get_port #(svt_apb_transaction) apbs_port;
  uvm_blocking_get_port #(svt_apb_transaction) apbp_port;

  // Interface for backdoor access to efuse memory
  virtual efuse_ctrl_if efuse_ctrl_vif;

  // eFuse macro geometry parameters
  localparam int fuse_size       = 8192;

  // eFuse memory model (fuse_size bits physical)
  // Stores physical eFuse bit data directly
  logic ref_fuse_data [fuse_size-1:0];
  // SRAM memory model: word-addressable, no primary/shadow split, no LFSR
  // Depth = efuse_size/32/2 = 128 words of 32 bits each
  logic [31:0] ref_sram_data [fuse_size/32/2-1:0];

  localparam int fuse_addr_size  = 13;
  localparam int out_addr_size   = 5;
  localparam int out_size        = 32;
  localparam int read_addr_size  = fuse_addr_size - out_addr_size;

  // Memory type selection for backdoor access wrappers
  typedef enum { REF_FUSE, DUT_FUSE, REF_SRAM, DUT_SRAM } mem_type_enum;
  typedef enum { FORCE_WRITE, BURN_WRITE } write_type_enum;

  // Test row/column registers
  localparam int test_row_size = out_size;
  localparam int test_col_size = 64;

  logic [test_row_size - 1 : 0] ref_test_row    [3:0];
  logic [test_row_size - 1 : 0] ref_test_row_2  [3:0];
  logic [test_col_size - 1 : 0] ref_test_column [1:0];

  // Track whether the efuse_dcu_en register has been written by software.
  // vif.expect_dcu_en_bit only factors in the efuse_dcu_en register value after this flag is set.
  bit                             efuse_dcu_en_written;

  // eFuse base address offset
  localparam bit [31:0] EFUSE_BASE_ADDR = 32'h1000;

  // eFuse logical address range: [0x00, 0x200)
  localparam bit [31:0] SECURE_REGION_END = 32'h7C;
  localparam bit [31:0] EFUSE_SIZE        = 32'h200;

  // WR_RD_ACC_DIS region byte start address
  localparam bit [31:0] WR_RD_ACC_DIS_START = 32'h7C;

  // LCS_STATE region byte start address
  localparam bit [31:0] LCS_STATE_START = 32'h48;

  function new(string name = "efuse_ctrl_scoreboard", uvm_component parent);
    super.new(name, parent);
  endfunction

  extern virtual function void build_phase(uvm_phase phase);

  //==========================================================================
  // Reset phase: initialize ref_fuse_data via backdoor
  //==========================================================================
  extern virtual task reset_phase(uvm_phase phase);

  //==========================================================================
  // Utility: Read a 32-bit word by eFuse logical offset (via ReadFuse)
  //   addr is the logical offset relative to EFUSE_BASE_ADDR.
  //   A_i = addr[8:2]          -> primary
  //   A_i = {1'b1, addr[8:2]}  -> shadow
  //==========================================================================
  extern task read_word(
    input bit [31:0]    addr,
    output bit [31:0]   word_data,
    output bit [31:0]   pri_data,
    output bit [31:0]   shd_data,
    input mem_type_enum mem_type = DUT_FUSE,
    input bit           force_normal_mode = 1'b0
  );

  //==========================================================================
  // Utility: Write a 32-bit word by eFuse logical offset (via WriteFuse)
  //   addr is the logical offset relative to EFUSE_BASE_ADDR.
  //==========================================================================
  extern task write_word(
    input bit [31:0]      addr,
    input bit [31:0]      word_data,
    input mem_type_enum   mem_type,
    input write_type_enum write_type = FORCE_WRITE,
    input bit             force_normal_mode = 1'b0
  );

  //==========================================================================
  // Utility: Write independent raw 32-bit words to FUSE primary and shadow planes
  //   pri_word_data / shd_word_data are the raw (LFSR-encoded) words to write.
  //==========================================================================
  extern task write_fuse_word_by_pri_sdh(
    input bit [31:0]      addr,
    input bit [31:0]      pri_word_data,
    input bit [31:0]      shd_word_data,
    input mem_type_enum   mem_type,
    input write_type_enum write_type = FORCE_WRITE,
    input bit             force_normal_mode = 1'b0
  );

  //==========================================================================
  // Apply cfg values to DUT_FUSE in reset_phase
  //==========================================================================
  extern task apply_cfg_to_fuse_sram();

  //==========================================================================
  // Backdoor access wrappers: FUSE vs SRAM
  //==========================================================================
  extern function logic fuse_data(logic [fuse_addr_size - 1 : 0] A, mem_type_enum mem_type);
  extern function logic test_row(logic [1 : 0] A_7_6, logic [out_addr_size - 1 : 0] k, mem_type_enum mem_type);
  extern function logic test_row_2(logic [1 : 0] A_7_6, logic [out_addr_size - 1 : 0] k, mem_type_enum mem_type);
  extern function logic test_column(logic AT_0, logic [5 : 0] test_col_A, mem_type_enum mem_type);
  extern function void write_fuse_data(logic [fuse_addr_size - 1 : 0] A, logic d, mem_type_enum mem_type);
  extern function void write_test_row(logic [1 : 0] A_7_6, logic [out_addr_size - 1 : 0] k, logic d, mem_type_enum mem_type);
  extern function void write_test_row_2(logic [1 : 0] A_7_6, logic [out_addr_size - 1 : 0] k, logic d, mem_type_enum mem_type);
  extern function void write_test_column(logic AT_0, logic [5 : 0] test_col_A, logic d, mem_type_enum mem_type);

  //==========================================================================
  // High-level fuse read/write tasks with test mode support
  //==========================================================================
  extern task ReadFuse(
    input logic [fuse_addr_size - 1 : 0] A_i,
    output logic [out_size - 1 : 0]      Q_d,
    input mem_type_enum                  mem_type,
    input bit                            force_normal_mode = 1'b0
  );
  extern task WriteFuse(
    input logic [fuse_addr_size - 1 : 0] A_i,
    input logic                          D,
    input mem_type_enum                  mem_type,
    input write_type_enum                write_type = FORCE_WRITE,
    input bit                            force_normal_mode = 1'b0
  );

  //==========================================================================
  // High-level SRAM read/write tasks (word-addressable, no LFSR, no test mode)
  //==========================================================================
  extern task ReadSram(
    input bit [31:0]    addr,
    output bit [31:0]   word_data,
    input mem_type_enum mem_type
  );
  extern task WriteSram(
    input bit [31:0]    addr,
    input bit [31:0]    word_data,
    input mem_type_enum mem_type
  );

  //==========================================================================
  // Utility: Check PSLVERR enable flag on transaction
  //==========================================================================
  extern function void check_pslverr(svt_apb_transaction tr, bit expected_err);

  //==========================================================================
  // Utility: Check read data matches expected value
  //==========================================================================
  extern function void check_read_data(svt_apb_transaction tr, bit [31:0] expected_data, string reason);

  //==========================================================================
  // Utility: Check raw fuse data against expected logical data
  //   Encodes expected_data with wr_lfsr_translate before comparing, because
  //   the fuse backdoor returns raw (LFSR-encoded) primary/shadow bits.
  //==========================================================================
  extern function void check_fuse_raw_match(
    input bit [31:0] addr,
    input bit [31:0] expected_data,
    input bit [31:0] actual_data,
    input string     reason
  );

  //==========================================================================
  // Utility: Update VIF/SVA expected values from eFuse data
  //
  // Call locations:
  //   1. reset_phase                       : called once after DUT_FUSE cfg applied
  //   2. auto_load_check / software_load_check : called once after load verify
  //   3. good_trans_checker_and_ref_update     : called once after each good SRAM write
  //   4. apbp_reg_checker                      : called when efuse_dcu_en or efuse_ctrl_acc_cfg is written
  //==========================================================================
  extern task update_vif_sva_expect_val();

  //==========================================================================
  // Utility: read lfsr data translate via interface
  //   Calls efuse_ctrl_vif.rd_lfsr_out_data with current efuse_test_mode.
  //==========================================================================
  extern function bit [31:0] rd_lfsr_translate(
    input bit [31:0] addr,
    input bit [31:0] data
  );

  //==========================================================================
  // Utility: write lfsr data translate via interface
  //   Calls efuse_ctrl_vif.wr_lfsr_out_data with current efuse_test_mode.
  //==========================================================================
  extern function bit [31:0] wr_lfsr_translate(
    input bit [31:0] addr,
    input bit [31:0] data
  );

  //==========================================================================
  // Utility: Check good transactions and update reference model
  //   logic_addr is the pre-computed eFuse macro offset (relative to EFUSE_BASE_ADDR)
  //   to use for all read_word/write_word calls.
  //==========================================================================
  extern task good_trans_checker_and_ref_update(
    input svt_apb_transaction tr,
    input bit [31:0]          logic_addr,
    input string              reason
  );

  //==========================================================================
  // Utility: Check good transactions in test mode (no SRAM check)
  //   logic_addr is the pre-computed eFuse macro offset (relative to EFUSE_BASE_ADDR)
  //   to use for all read_word/write_word calls.
  //==========================================================================
  extern task test_mode_good_trans_checker_and_ref_update(
    input svt_apb_transaction tr,
    input bit [31:0]          logic_addr,
    input string              reason
  );

  //==========================================================================
  // Utility: Get region_res index from logical address (-1 if not region_res)
  //==========================================================================
  extern function int get_region_res_index(bit [31:0] logic_addr);

  //==========================================================================
  // Utility: Check if write/read is disabled for given region_res index
  //==========================================================================
  extern task is_write_disabled(bit [31:0] logic_addr, output bit disabled);
  extern task is_read_disabled(bit [31:0] logic_addr, output bit disabled);

  //==========================================================================
  // Utility: Get region-4 control bits from REF_SRAM (1=prohibit, 0=allow)
  // shadow_sram_acc_bit    : region 4 bit 41 -> APB 0xA8 bit[9]
  // top_acc_sec_region_bit : region 4 bit 42 -> APB 0xA8 bit[10]
  //==========================================================================
  extern task get_shadow_sram_acc_bit(output bit val);
  extern task get_top_acc_sec_region_bit(output bit val);

  //==========================================================================
  // Utility: Check if address is within secure region
  //==========================================================================
  extern function bit is_secure_region(bit [31:0] addr);

  //==========================================================================
  // Utility: Check if address is within valid eFuse range
  //==========================================================================
  extern function bit is_valid_efuse_addr(bit [31:0] addr);

  //==========================================================================
  // APB Secure Master Checker
  //==========================================================================
  extern task apbs_checker();
  extern task apbs_reg_checker(svt_apb_transaction tr);
  extern task apbs_test_mode_checker(svt_apb_transaction tr);
  extern task apbs_efuse_access_checker(svt_apb_transaction tr);
  extern task apbs_efuse_accessible_check(svt_apb_transaction tr);
  extern task apbs_efuse_access_deny_check(svt_apb_transaction tr);
  extern task apbs_efuse_reverse_check(svt_apb_transaction tr);
  extern task apbs_efuse_load_not_done_check(svt_apb_transaction tr);

  //==========================================================================
  // APB Public Master Checker for non-eFuse registers (addr < EFUSE_BASE_ADDR)
  //==========================================================================
  extern task apbp_reg_checker(svt_apb_transaction tr);

  //==========================================================================
  // APB Public Master Checker
  //==========================================================================
  extern task apbp_checker();
  extern task apbp_test_mode_checker(svt_apb_transaction tr);
  extern task apbp_efuse_access_checker(svt_apb_transaction tr);
  extern task apbp_efuse_accessible_check(svt_apb_transaction tr);
  extern task apbp_efuse_access_deny_check(svt_apb_transaction tr);
  extern task apbp_efuse_reverse_check(svt_apb_transaction tr);
  extern task apbp_efuse_load_not_done_check(svt_apb_transaction tr);

  //==========================================================================
  // Load check: auto load & software load
  //==========================================================================
  extern task load_checker();
  extern task auto_load_check();
  extern task software_load_check();
  extern task do_load_verify(string reason);

  // Event triggered by apbp_reg_checker when efuse_done_status bit becomes 1
  event software_load_done_event;

  // Real time when efuse_load_done rising edge was observed.
  // Used to determine whether an APB transaction started before or after load done.
  realtime efuse_load_done_time;
  bit      efuse_load_done_recorded;

  // Track whether apply_cfg_to_fuse_sram is running, so write_word can suppress
  // the force_normal_mode warning during backdoor cfg initialization.
  bit backdoor_cfg_efuse;

  //==========================================================================
  // Utility: Check if transaction started before efuse_load_done rising edge
  //==========================================================================
  extern function bit is_before_efuse_load_done(svt_apb_transaction tr);

  extern virtual task run_phase(uvm_phase phase);

endclass

//----------------------------------------------------------------------------
// Utility function/task implementations
//----------------------------------------------------------------------------
function void efuse_ctrl_scoreboard::build_phase(uvm_phase phase);
  super.build_phase(phase);
  apbs_port = new("apbs_port", this);
  apbp_port = new("apbp_port", this);

  if (!uvm_config_db#(virtual efuse_ctrl_if)::get(this, "", "efuse_ctrl_vif", efuse_ctrl_vif)) begin
    `uvm_fatal("build_phase", "Failed to get virtual interface from config DB")
  end

  if (!uvm_config_db#(ral_block_regbank_cfg_efuse_ctrl)::get(this, "", "reg_model", reg_model)) begin
    `uvm_fatal("build_phase", "Failed to get reg_model from config DB")
  end

  if (!uvm_config_db#(efuse_ctrl_cfg)::get(this, "", "cfg", cfg)) begin
    cfg = new("cfg");
    `uvm_info("build_phase", "No efuse_ctrl_cfg found in config DB, using default", UVM_MEDIUM)
  end

  foreach (ref_fuse_data[i]) ref_fuse_data[i] = 1'b0;
  foreach (ref_sram_data[i]) ref_sram_data[i] = '0;

  foreach (ref_test_row[i])    ref_test_row[i]    = '0;
  foreach (ref_test_row_2[i])  ref_test_row_2[i]  = '0;
  foreach (ref_test_column[i]) ref_test_column[i] = '0;

  efuse_dcu_en_written = 1'b0;

  efuse_load_done_time     = 0;
  efuse_load_done_recorded = 1'b0;
  backdoor_cfg_efuse       = 1'b0;
endfunction

task efuse_ctrl_scoreboard::reset_phase(uvm_phase phase);
  super.reset_phase(phase);
  phase.raise_objection(this);

  if (efuse_ctrl_vif == null) begin
    `uvm_fatal(get_type_name(), "efuse_ctrl_vif is null in reset_phase")
  end

  // Wait 1 time unit, then update DUT_FUSE according to cfg
  #1;
  `uvm_info(get_type_name(), "Applying cfg to DUT_FUSE", UVM_MEDIUM)
  apply_cfg_to_fuse_sram();

  // Copy DUT_FUSE to reference model
  `uvm_info(get_type_name(), "Copying DUT_FUSE to ref_fuse_data", UVM_MEDIUM)
  foreach (ref_fuse_data[i]) begin
    ref_fuse_data[i] = fuse_data(i, DUT_FUSE);
  end

  // Reset software-write tracking for efuse_dcu_en register
  efuse_dcu_en_written = 1'b0;

  update_vif_sva_expect_val();

  phase.drop_objection(this);
endtask

task efuse_ctrl_scoreboard::read_word(
  input bit [31:0]    addr,
  output bit [31:0]   word_data,
  output bit [31:0]   pri_data,
  output bit [31:0]   shd_data,
  input mem_type_enum mem_type,
  input bit           force_normal_mode
);
  logic [fuse_addr_size - 1 : 0] pri_A;
  logic [fuse_addr_size - 1 : 0] shd_A;

  // SRAM is word-addressable, has no primary/shadow split, and bypasses LFSR
  if (mem_type == DUT_SRAM || mem_type == REF_SRAM) begin
    ReadSram(addr, word_data, mem_type);
    pri_data = word_data;
    shd_data = word_data;
    `uvm_info(get_type_name(), $sformatf(
      "Read word (%s): addr=0x%08x data=0x%08x", mem_type.name(), addr, word_data
    ), UVM_HIGH)
    return;
  end

  pri_A = {{(fuse_addr_size - 7){1'b0}}, addr[8:2]};
  shd_A = {{(fuse_addr_size - 8){1'b0}}, 1'b1, addr[8:2]};

  ReadFuse(pri_A, pri_data, mem_type, force_normal_mode);
  ReadFuse(shd_A, shd_data, mem_type, force_normal_mode);

  // LFSR decode is applied to the combined primary|shadow word.
  // pri_data/shd_data remain raw encoded fuse bits; word_data is the logical value.
  word_data = rd_lfsr_translate(addr, pri_data | shd_data);

  `uvm_info(get_type_name(), $sformatf(
    "Read word: addr=0x%08x mem_type=%s force_normal_mode=%0b pri=0x%08x shd=0x%08x data=0x%08x",
    addr, mem_type.name(), force_normal_mode, pri_data, shd_data, word_data
  ), UVM_HIGH)
endtask

//----------------------------------------------------------------------------
// write_word: Write a 32-bit word by APB address via WriteFuse
// test_mode / AT_i are obtained from reg_model.efuse_ctrl_acc_cfg
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::write_word(
  input bit [31:0]      addr,
  input bit [31:0]      word_data,
  input mem_type_enum   mem_type,
  input write_type_enum write_type,
  input bit             force_normal_mode
);
  logic [fuse_addr_size - 1 : 0] pri_A;
  logic [fuse_addr_size - 1 : 0] shd_A;
  logic [fuse_addr_size - 1 : 0] bit_A;
  logic                          bit_data;
  bit [31:0]                     efuse_word_data;

  // SRAM is word-addressable, has no primary/shadow split, and bypasses LFSR
  if (mem_type == DUT_SRAM || mem_type == REF_SRAM) begin
    WriteSram(addr, word_data, mem_type);
    `uvm_info(get_type_name(), $sformatf(
      "Write word (%s): addr=0x%08x data=0x%08x", mem_type.name(), addr, word_data
    ), UVM_HIGH)
    return;
  end

  pri_A = {{(fuse_addr_size - 7){1'b0}}, addr[8:2]};
  shd_A = {{(fuse_addr_size - 8){1'b0}}, 1'b1, addr[8:2]};

  if (force_normal_mode && !backdoor_cfg_efuse) begin
    `uvm_warning(get_type_name(), $sformatf(
      "Write word with force_normal_mode=1: addr=0x%08x mem_type=%s write_type=%s data=0x%08x",
      addr, mem_type.name(), write_type.name(), word_data
    ))
  end

  efuse_word_data = wr_lfsr_translate(addr, word_data);

  for (int i = 0; i < out_size; i++) begin
    bit_data = efuse_word_data[i];

    bit_A = {i[out_addr_size-1:0], pri_A[read_addr_size-1:0]};
    WriteFuse(bit_A, bit_data, mem_type, write_type, force_normal_mode);

    bit_A = {i[out_addr_size-1:0], shd_A[read_addr_size-1:0]};
    WriteFuse(bit_A, bit_data, mem_type, write_type, force_normal_mode);
  end

  `uvm_info(get_type_name(), $sformatf(
    "Write word: addr=0x%08x mem_type=%s write_type=%s force_normal_mode=%0b apb_data=0x%08x efuse_data=0x%08x",
    addr, mem_type.name(), write_type.name(), force_normal_mode, word_data, efuse_word_data
  ), UVM_HIGH)
endtask

//----------------------------------------------------------------------------
// write_fuse_word_by_pri_sdh: Write independent raw words to primary and shadow planes
//   pri_word_data / shd_word_data are raw (already LFSR-encoded) 32-bit words.
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::write_fuse_word_by_pri_sdh(
  input bit [31:0]      addr,
  input bit [31:0]      pri_word_data,
  input bit [31:0]      shd_word_data,
  input mem_type_enum   mem_type,
  input write_type_enum write_type,
  input bit             force_normal_mode
);
  logic [fuse_addr_size - 1 : 0] pri_A;
  logic [fuse_addr_size - 1 : 0] shd_A;
  logic [fuse_addr_size - 1 : 0] bit_A;
  logic                          bit_data;

  pri_A = {{(fuse_addr_size - 7){1'b0}}, addr[8:2]};
  shd_A = {{(fuse_addr_size - 8){1'b0}}, 1'b1, addr[8:2]};

  for (int i = 0; i < out_size; i++) begin
    bit_data = pri_word_data[i];

    bit_A = {i[out_addr_size-1:0], pri_A[read_addr_size-1:0]};
    WriteFuse(bit_A, bit_data, mem_type, write_type, force_normal_mode);

    bit_data = shd_word_data[i];

    bit_A = {i[out_addr_size-1:0], shd_A[read_addr_size-1:0]};
    WriteFuse(bit_A, bit_data, mem_type, write_type, force_normal_mode);
  end

  `uvm_info(get_type_name(), $sformatf(
    "Write fuse word planes: addr=0x%08x mem_type=%s write_type=%s force_normal_mode=%0b pri=0x%08x shd=0x%08x",
    addr, mem_type.name(), write_type.name(), force_normal_mode, pri_word_data, shd_word_data
  ), UVM_HIGH)
endtask

//----------------------------------------------------------------------------
// apply_cfg_to_fuse_sram: Update DUT_FUSE/DUT_SRAM/REF_FUSE/REF_SRAM with cfg-controlled fields
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apply_cfg_to_fuse_sram();
  bit [31:0] word_data;
  bit [31:0] pri_data;
  bit [31:0] shd_data;

  backdoor_cfg_efuse = 1'b1;

  // LCS_STATE: low 4 bits at APB offset 0x48
  read_word(LCS_STATE_START, word_data, pri_data, shd_data, DUT_FUSE, 1'b1);
  word_data[3:0] = cfg.lcs_state;
  write_word(LCS_STATE_START, word_data, DUT_FUSE, FORCE_WRITE, 1'b1);
  write_word(LCS_STATE_START, word_data, DUT_SRAM, FORCE_WRITE);
  write_word(LCS_STATE_START, word_data, REF_FUSE, FORCE_WRITE, 1'b1);
  write_word(LCS_STATE_START, word_data, REF_SRAM, FORCE_WRITE);

  // Write access disable: low 8 bits at APB offset 0x7C
  read_word(WR_RD_ACC_DIS_START, word_data, pri_data, shd_data, DUT_FUSE, 1'b1);
  word_data[7:0] = cfg.top_region_wr_disable;
  write_word(WR_RD_ACC_DIS_START, word_data, DUT_FUSE, FORCE_WRITE, 1'b1);
  write_word(WR_RD_ACC_DIS_START, word_data, DUT_SRAM, FORCE_WRITE);
  write_word(WR_RD_ACC_DIS_START, word_data, REF_FUSE, FORCE_WRITE, 1'b1);
  write_word(WR_RD_ACC_DIS_START, word_data, REF_SRAM, FORCE_WRITE);

  // Read access disable: low 8 bits at APB offset 0x80
  read_word(WR_RD_ACC_DIS_START + 4, word_data, pri_data, shd_data, DUT_FUSE, 1'b1);
  word_data[7:0] = cfg.top_region_rd_disable;
  write_word(WR_RD_ACC_DIS_START + 4, word_data, DUT_FUSE, FORCE_WRITE, 1'b1);
  write_word(WR_RD_ACC_DIS_START + 4, word_data, DUT_SRAM, FORCE_WRITE);
  write_word(WR_RD_ACC_DIS_START + 4, word_data, REF_FUSE, FORCE_WRITE, 1'b1);
  write_word(WR_RD_ACC_DIS_START + 4, word_data, REF_SRAM, FORCE_WRITE);

  // shadow_sram_acc_bit at APB offset 0xA8 bit[10]
  // top_acc_sec_region_bit at APB offset 0xA8 bit[9]
  read_word(32'hA8, word_data, pri_data, shd_data, DUT_FUSE, 1'b1);
  word_data[10] = cfg.shadow_sram_acc_bit;
  word_data[9]  = cfg.top_acc_sec_region_bit;
  write_word(32'hA8, word_data, DUT_FUSE, FORCE_WRITE, 1'b1);
  write_word(32'hA8, word_data, DUT_SRAM, FORCE_WRITE);
  write_word(32'hA8, word_data, REF_FUSE, FORCE_WRITE, 1'b1);
  write_word(32'hA8, word_data, REF_SRAM, FORCE_WRITE);

  backdoor_cfg_efuse = 1'b0;
endtask

function void efuse_ctrl_scoreboard::check_pslverr(svt_apb_transaction tr, bit expected_err);
  if (cfg != null && !cfg.pslverr_check_enable) begin
    `uvm_info(get_type_name(), $sformatf(
      "PSLVERR check skipped: addr=0x%08x pslverr_check_enable=0",
      tr.address
    ), UVM_HIGH)
    return;
  end

  if (tr.pslverr_enable !== expected_err) begin
    `uvm_error(get_type_name(), $sformatf(
      "PSLVERR check failed! addr=0x%08x %s exp_pslverr_enable=%0b act=%0b",
      tr.address, tr.xact_type.name(), expected_err, tr.pslverr_enable
    ))
  end else begin
    `uvm_info(get_type_name(), $sformatf(
      "PSLVERR check PASS: addr=0x%08x pslverr_enable=%0b",
      tr.address, tr.pslverr_enable
    ), UVM_HIGH)
  end
endfunction

function void efuse_ctrl_scoreboard::check_read_data(svt_apb_transaction tr, bit [31:0] expected_data, string reason);
  if (tr.data !== expected_data) begin
    `uvm_error(get_type_name(), $sformatf(
      "READ MISMATCH! addr=0x%08x exp=0x%08x act=0x%08x (%s)",
      tr.address, expected_data, tr.data, reason
    ))
  end else begin
    `uvm_info(get_type_name(), $sformatf(
      "READ PASS: addr=0x%08x data=0x%08x (%s)",
      tr.address, tr.data, reason
    ), UVM_HIGH)
  end
endfunction

//----------------------------------------------------------------------------
// check_fuse_raw_match: Compare expected logical data against raw fuse bits
//   The fuse backdoor returns LFSR-encoded raw bits, so expected_data is
//   encoded with wr_lfsr_translate before the comparison.
//----------------------------------------------------------------------------
function void efuse_ctrl_scoreboard::check_fuse_raw_match(
  input bit [31:0] addr,
  input bit [31:0] expected_data,
  input bit [31:0] actual_data,
  input string     reason
);
  bit [31:0] logic_addr;
  logic_addr = addr - EFUSE_BASE_ADDR;
  `CHECK_DATA_MATCH(addr, wr_lfsr_translate(logic_addr, expected_data), actual_data, reason)
endfunction

//----------------------------------------------------------------------------
// is_before_efuse_load_done: Determine if a transaction started before the
// efuse_load_done rising edge.
//   If cfg.check_trans_before_load_done_by_single is 1, use the current
//   efuse_load_done signal level (legacy behavior).
//   Otherwise, compare the transaction begin time with efuse_load_done_time.
//----------------------------------------------------------------------------
function bit efuse_ctrl_scoreboard::is_before_efuse_load_done(svt_apb_transaction tr);
  if (cfg != null && cfg.check_trans_before_load_done_by_single) begin
    return (efuse_ctrl_vif.efuse_load_done !== 1'b1);
  end
  if (!efuse_load_done_recorded) begin
    return 1'b1;
  end
  return (tr.svt_begin_realtime < efuse_load_done_time);
endfunction

function bit [31:0] efuse_ctrl_scoreboard::rd_lfsr_translate(
  input bit [31:0] addr,
  input bit [31:0] data
);
  bit test_mode;

  if (reg_model == null) begin
    `uvm_fatal(get_type_name(), "rd_lfsr_translate: reg_model is null")
  end
  test_mode = reg_model.efuse_ctrl_acc_cfg.efuse_test_mode.get();
  return efuse_ctrl_vif.rd_lfsr_out_data(test_mode, addr, data);
endfunction

function bit [31:0] efuse_ctrl_scoreboard::wr_lfsr_translate(
  input bit [31:0] addr,
  input bit [31:0] data
);
  bit test_mode;

  if (reg_model == null) begin
    `uvm_fatal(get_type_name(), "wr_lfsr_translate: reg_model is null")
  end
  test_mode = reg_model.efuse_ctrl_acc_cfg.efuse_test_mode.get();
  return efuse_ctrl_vif.wr_lfsr_out_data(test_mode, addr, data);
endfunction

//----------------------------------------------------------------------------
// update_vif_sva_expect_val: Update VIF/SVA expected values from eFuse data
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::update_vif_sva_expect_val();
  bit [31:0] lcs_state_word;
  bit [3:0]  lcs_state;
  bit [31:0] pri_tmp;
  bit [31:0] shd_tmp;
  bit [31:0] feat_w0;
  bit [31:0] feat_w1;
  bit [31:0] mem_w0;
  bit [31:0] mem_w1;
  bit [31:0] mem_w2;
  bit [31:0] ana_w0;
  bit [31:0] ana_w1;
  bit [31:0] ana_w2;
  bit [31:0] ana_w3;
  bit [31:0] ana_w4;
  bit [31:0] ana_w5;
  bit [31:0] ana_w6;
  bit [31:0] ana_w7;
  bit [31:0] boot_cfg_bit;
  bit [31:0] dcu_w0;
  bit [31:0] dcu_w1;
  bit [31:0] dcu_w2;
  bit [31:0] dcu_w3;
  bit [127:0] dcu_en_src;
  bit [127:0] dcu_en_sram_mask;

  // LCS_STATE enum values
  localparam bit [3:0] LCS_CM = 4'b0000;
  localparam bit [3:0] LCS_DM = 4'b0001;
  localparam bit [3:0] LCS_DD = 4'b0011;
  localparam bit [3:0] LCS_DR = 4'b0111;

  if (reg_model == null) begin
    `uvm_fatal(get_type_name(), "update_vif_sva_expect_val: reg_model is null")
  end
  if (efuse_ctrl_vif == null) begin
    `uvm_fatal(get_type_name(), "update_vif_sva_expect_val: efuse_ctrl_vif is null")
  end

  // Drive margin_read_mode to vif so backdoor reads use the current mode
  efuse_ctrl_vif.margin_read_mode = reg_model.efuse_ctrl_acc_cfg.margin_read_mode.get();

  // expect_device_id_bit: DUT_SRAM offset 0x8C, 32bit
  read_word(32'h8C, efuse_ctrl_vif.expect_device_id_bit, pri_tmp, shd_tmp, DUT_SRAM);

  // expect_feature_cfg_bit: DUT_SRAM offset 0xA4, 64bit
  read_word(32'hA4, feat_w0, pri_tmp, shd_tmp, DUT_SRAM);
  read_word(32'hA8, feat_w1, pri_tmp, shd_tmp, DUT_SRAM);
  efuse_ctrl_vif.expect_feature_cfg_bit = {feat_w1, feat_w0};

  // expect_memory_cfg_bit: DUT_SRAM offset 0xAC, 96bit
  read_word(32'hAC, mem_w0, pri_tmp, shd_tmp, DUT_SRAM);
  read_word(32'hB0, mem_w1, pri_tmp, shd_tmp, DUT_SRAM);
  read_word(32'hB4, mem_w2, pri_tmp, shd_tmp, DUT_SRAM);
  efuse_ctrl_vif.expect_memory_cfg_bit = {mem_w2, mem_w1, mem_w0};

  // expect_analog_calibre_bit: DUT_SRAM offset 0xB8, 256bit
  read_word(32'hB8, ana_w0, pri_tmp, shd_tmp, DUT_SRAM);
  read_word(32'hBC, ana_w1, pri_tmp, shd_tmp, DUT_SRAM);
  read_word(32'hC0, ana_w2, pri_tmp, shd_tmp, DUT_SRAM);
  read_word(32'hC4, ana_w3, pri_tmp, shd_tmp, DUT_SRAM);
  read_word(32'hC8, ana_w4, pri_tmp, shd_tmp, DUT_SRAM);
  read_word(32'hCC, ana_w5, pri_tmp, shd_tmp, DUT_SRAM);
  read_word(32'hD0, ana_w6, pri_tmp, shd_tmp, DUT_SRAM);
  read_word(32'hD4, ana_w7, pri_tmp, shd_tmp, DUT_SRAM);
  efuse_ctrl_vif.expect_analog_calibre_bit = {ana_w7, ana_w6, ana_w5, ana_w4, ana_w3, ana_w2, ana_w1, ana_w0};

  // boot_cfg_bit: DUT_SRAM offset 0xA0, 32bit
  read_word(32'hA0, boot_cfg_bit, pri_tmp, shd_tmp, DUT_SRAM);

  // LCS_STATE: DUT_SRAM offset 0x48, low 4 bits
  read_word(LCS_STATE_START, lcs_state_word, pri_tmp, shd_tmp, DUT_SRAM);
  lcs_state = lcs_state_word[3:0];

  // expect_dcu_en_bit calculation
  if (lcs_state == LCS_DD) begin
    if (efuse_dcu_en_written) begin
      dcu_en_src = reg_model.efuse_dcu_en.get();
    end else begin
      dcu_en_src = '0;
    end
    read_word(32'h90, dcu_w0, pri_tmp, shd_tmp, DUT_SRAM);
    read_word(32'h94, dcu_w1, pri_tmp, shd_tmp, DUT_SRAM);
    read_word(32'h98, dcu_w2, pri_tmp, shd_tmp, DUT_SRAM);
    read_word(32'h9C, dcu_w3, pri_tmp, shd_tmp, DUT_SRAM);
    dcu_en_sram_mask = {dcu_w3, dcu_w2, dcu_w1, dcu_w0};
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
    `uvm_info(get_type_name(), $sformatf("update_vif_sva_expect_val: unknown LCS_STATE=0x%0x", lcs_state), UVM_LOW)
    efuse_ctrl_vif.expect_dcu_en_bit = efuse_ctrl_vif.dcu_en_cm;
  end

  // expect_boot_latch_pin calculation
  efuse_ctrl_vif.expect_boot_latch_pin[efuse_ctrl_vif.BOOT_PIN_NUM-1:8] = efuse_ctrl_vif.boot_strap_pin[efuse_ctrl_vif.BOOT_PIN_NUM-1:8];
  if (~efuse_ctrl_vif.expect_dcu_en_bit[0] & boot_cfg_bit[31]) begin
    efuse_ctrl_vif.expect_boot_latch_pin[7:0] = boot_cfg_bit[7:0];
  end else begin
    efuse_ctrl_vif.expect_boot_latch_pin[7:0] = efuse_ctrl_vif.boot_strap_pin[7:0];
  end

  `uvm_info(get_type_name(), $sformatf(
    "update_vif_sva_expect_val: LCS_STATE=0x%0x device_id=0x%08x feature_cfg=0x%016x memory_cfg=0x%024x analog=0x%064x dcu_en=0x%032x boot_latch=%p",
    lcs_state, efuse_ctrl_vif.expect_device_id_bit, efuse_ctrl_vif.expect_feature_cfg_bit, efuse_ctrl_vif.expect_memory_cfg_bit,
    efuse_ctrl_vif.expect_analog_calibre_bit, efuse_ctrl_vif.expect_dcu_en_bit, efuse_ctrl_vif.expect_boot_latch_pin
  ), UVM_HIGH)
endtask

//----------------------------------------------------------------------------
// good_trans_checker_and_ref_update: Check good transactions and update reference model
//   logic_addr is the pre-computed eFuse macro offset (relative to EFUSE_BASE_ADDR).
// PPROT1 (secure/non-secure) support: svt_apb_transaction::NON_SECURE means non-secure access.
// Read returns 0. For writes in non-reverse eFuse region, check the write is
// ignored (DUT_FUSE and DUT_SRAM unchanged); for reverse region, no write check.
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::good_trans_checker_and_ref_update(
  input svt_apb_transaction tr,
  input bit [31:0]          logic_addr,
  input string              reason
);
  bit [31:0] pri_data_fuse;
  bit [31:0] shd_data_fuse;
  bit [31:0] pri_data_sram;
  bit [31:0] shd_data_sram;
  bit [31:0] hw_data;
  bit [31:0] hw_data_sram;
  bit [31:0] mem_data;
  bit [31:0] expected_data;
  bit [31:0] pri_data_ref;
  bit [31:0] shd_data_ref;
  bit        read_from_efuse;
  bit        shadow_sram_acc;
  mem_type_enum backdoor_mem_type;

  logic_addr[1:0] = 2'b00; // word-align the address for backdoor access

  if (reg_model == null) begin
    `uvm_fatal(get_type_name(), "good_trans_checker_and_ref_update: reg_model is null")
  end

  // Non-secure access: read returns 0, write is ignored.
  if (tr.pprot1 === svt_apb_transaction::NON_SECURE) begin
    `uvm_info(get_type_name(), $sformatf(
      "[%s] pprot1=NON_SECURE non-secure access: addr=0x%08x %s data=0x%08x",
      reason, tr.address, tr.xact_type.name(), tr.data
    ), UVM_HIGH)
    check_pslverr(tr, 1'b0);
    if (tr.xact_type == svt_apb_transaction::READ) begin
      check_read_data(tr, 32'h0, "pprot1=NON_SECURE non-secure read returns 0");
    end else if (logic_addr < EFUSE_SIZE) begin
      // Check DUT_FUSE unchanged
      read_word(logic_addr, mem_data, pri_data_ref, shd_data_ref, REF_FUSE, 1'b1);
      read_word(logic_addr, hw_data, pri_data_fuse, shd_data_fuse, DUT_FUSE, 1'b1);
      `CHECK_DATA_MATCH(tr.address, mem_data, hw_data, "pprot1=NON_SECURE non-secure write ignored, DUT_FUSE unchanged")
      // Check DUT_SRAM unchanged
      read_word(logic_addr, mem_data, pri_data_sram, shd_data_sram, REF_SRAM, 1'b1);
      read_word(logic_addr, hw_data, pri_data_fuse, shd_data_fuse, DUT_SRAM, 1'b1);
      `CHECK_DATA_MATCH(tr.address, mem_data, hw_data, "pprot1=NON_SECURE non-secure write ignored, DUT_SRAM unchanged")
    end
    return;
  end

  if (tr.xact_type == svt_apb_transaction::READ) begin
    bit [31:0] ref_data;
    bit [31:0] ref_pri;
    bit [31:0] ref_shd;

    read_from_efuse = reg_model.efuse_ctrl_acc_cfg.read_from_efuse.get();
    backdoor_mem_type = (read_from_efuse === 1'b1) ? DUT_FUSE : DUT_SRAM;

    read_word(logic_addr, hw_data, pri_data_fuse, shd_data_fuse, backdoor_mem_type);
    `CHECK_DATA_MATCH(tr.address, hw_data, tr.data, $sformatf(
      "%s read backdoor read_from_efuse=%0b backdoor_mem_type=%s",
      reason, read_from_efuse, backdoor_mem_type.name()
    ))

    // Check ref vs dut consistency
    if (backdoor_mem_type == DUT_FUSE) begin
      read_word(logic_addr, ref_data, ref_pri, ref_shd, REF_FUSE);
    end else begin
      read_word(logic_addr, ref_data, ref_pri, ref_shd, REF_SRAM);
    end
    `CHECK_DATA_MATCH(tr.address, hw_data, ref_data, $sformatf(
      "%s ref-dut consistency read_from_efuse=%0b backdoor_mem_type=%s",
      reason, read_from_efuse, backdoor_mem_type.name()
    ))

    // Normal read expects pslverr = 0
    check_pslverr(tr, 1'b0);

    if (cfg.READ_UPDATE_SRAM && read_from_efuse) begin
      write_word(logic_addr, hw_data, DUT_SRAM, FORCE_WRITE);
    end
  end
  else begin // WRITE
    bit expect_pslverr;
    bit wr_en;
    bit [3:0] pstrb;
    int byte_idx;
    bit [31:0] new_one;
    bit [31:0] new_one_raw;

    read_word(logic_addr, mem_data, pri_data_ref, shd_data_ref, REF_FUSE);

    // Apply APB byte strobe (pstrb): only strobed bytes are OR-ed with write data;
    // non-strobed bytes keep the existing fuse value.
    pstrb = tr.pstrb;
    expected_data = mem_data;
    for (byte_idx = 0; byte_idx < 4; byte_idx++) begin
      if (pstrb[byte_idx]) begin
        expected_data[byte_idx*8 +: 8] = mem_data[byte_idx*8 +: 8] | tr.data[byte_idx*8 +: 8];
      end
    end
    new_one     = expected_data & ~mem_data;
    new_one_raw = wr_lfsr_translate(logic_addr, new_one);
    expect_pslverr = 1'b0;

    read_word(logic_addr, hw_data, pri_data_fuse, shd_data_fuse, DUT_FUSE);
    get_shadow_sram_acc_bit(shadow_sram_acc);
    wr_en = reg_model.efuse_shadow_sram.wr_en.get();

    if (wr_en == 1'b1 && shadow_sram_acc == 1'b0) begin
      read_word(logic_addr, hw_data_sram, pri_data_sram, shd_data_sram, DUT_SRAM);

      `CHECK_DATA_MATCH(tr.address, pri_data_ref | new_one_raw, pri_data_fuse, {reason, " DUT_FUSE primary"})
      `CHECK_DATA_MATCH(tr.address, shd_data_ref | new_one_raw, shd_data_fuse, {reason, " DUT_FUSE shadow"})
      `CHECK_DATA_MATCH(tr.address, mem_data | new_one, hw_data, {reason, " DUT_FUSE decoded"})
      `CHECK_DATA_MATCH(tr.address, expected_data, hw_data_sram, {reason, " DUT_SRAM"})

      write_word(logic_addr, expected_data, REF_SRAM, FORCE_WRITE);
   
      // Re-calculate expected DUT outputs whenever a good write updates the SRAM reference
      update_vif_sva_expect_val();
    end
    else begin
      `CHECK_DATA_MATCH(tr.address, pri_data_ref | new_one_raw, pri_data_fuse, {reason, " DUT_FUSE primary"})
      `CHECK_DATA_MATCH(tr.address, shd_data_ref | new_one_raw, shd_data_fuse, {reason, " DUT_FUSE shadow"})
      `CHECK_DATA_MATCH(tr.address, mem_data | new_one, hw_data, {reason, " DUT_FUSE decoded"})
    end

    check_pslverr(tr, expect_pslverr);
    write_fuse_word_by_pri_sdh(logic_addr, pri_data_ref | new_one_raw, shd_data_ref | new_one_raw, REF_FUSE, FORCE_WRITE);
  end
endtask

//----------------------------------------------------------------------------
// test_mode_good_trans_checker_and_ref_update: Good transaction check in test mode
//   logic_addr is the pre-computed eFuse macro offset (relative to EFUSE_BASE_ADDR).
// Only checks DUT_FUSE, no SRAM access/check.
// PPROT1 (secure/non-secure) support: svt_apb_transaction::NON_SECURE means non-secure access.
// Read returns 0. For writes in non-reverse eFuse region, check the write is
// ignored (DUT_FUSE unchanged); for reverse region, no write check.
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::test_mode_good_trans_checker_and_ref_update(
  input svt_apb_transaction tr,
  input bit [31:0]          logic_addr,
  input string              reason
);
  bit [31:0] pri_data_fuse;
  bit [31:0] shd_data_fuse;
  bit [31:0] mem_data;
  bit [31:0] expected_data;
  bit [31:0] pri_data_ref;
  bit [31:0] shd_data_ref;
  bit [31:0] hw_data;
  bit [31:0] ref_data;
  bit [31:0] ref_pri;
  bit [31:0] ref_shd;

  logic_addr[1:0] = 2'b00; // word-align the address for backdoor access

  if (reg_model == null) begin
    `uvm_fatal(get_type_name(), "test_mode_good_trans_checker_and_ref_update: reg_model is null")
  end

  // Non-secure access: read returns 0, write is ignored.
  if (tr.pprot1 === svt_apb_transaction::NON_SECURE) begin
    `uvm_info(get_type_name(), $sformatf(
      "[%s] pprot1=NON_SECURE non-secure access: addr=0x%08x %s data=0x%08x",
      reason, tr.address, tr.xact_type.name(), tr.data
    ), UVM_HIGH)
    check_pslverr(tr, 1'b0);
    if (tr.xact_type == svt_apb_transaction::READ) begin
      check_read_data(tr, 32'h0, "pprot1=NON_SECURE non-secure read returns 0");
    end else if (logic_addr < EFUSE_SIZE) begin
      read_word(logic_addr, mem_data, pri_data_ref, shd_data_ref, REF_FUSE, 1'b1);
      read_word(logic_addr, hw_data, pri_data_fuse, shd_data_fuse, DUT_FUSE, 1'b1);
      `CHECK_DATA_MATCH(tr.address, mem_data, hw_data, "pprot1=NON_SECURE non-secure write ignored, DUT_FUSE unchanged")
    end
    return;
  end

  if (tr.xact_type == svt_apb_transaction::READ) begin
    read_word(logic_addr, hw_data, pri_data_fuse, shd_data_fuse, DUT_FUSE);
    `CHECK_DATA_MATCH(tr.address, hw_data, tr.data, {reason, " read backdoor"})

    read_word(logic_addr, ref_data, ref_pri, ref_shd, REF_FUSE);
    `CHECK_DATA_MATCH(tr.address, hw_data, ref_data, {reason, " ref-dut consistency"})

    check_pslverr(tr, 1'b0);
  end
  else begin // WRITE
    bit expect_pslverr;
    bit [3:0] pstrb;
    int byte_idx;
    bit [31:0] new_one;
    bit [31:0] new_one_raw;

    read_word(logic_addr, mem_data, pri_data_ref, shd_data_ref, REF_FUSE);

    // Apply APB byte strobe (pstrb): only strobed bytes are OR-ed with write data;
    // non-strobed bytes keep the existing fuse value.
    pstrb = tr.pstrb;
    expected_data = mem_data;
    for (byte_idx = 0; byte_idx < 4; byte_idx++) begin
      if (pstrb[byte_idx]) begin
        expected_data[byte_idx*8 +: 8] = mem_data[byte_idx*8 +: 8] | tr.data[byte_idx*8 +: 8];
      end
    end
    new_one     = expected_data & ~mem_data;
    new_one_raw = wr_lfsr_translate(logic_addr, new_one);
    expect_pslverr = 1'b0;

    read_word(logic_addr, hw_data, pri_data_fuse, shd_data_fuse, DUT_FUSE);

    `CHECK_DATA_MATCH(tr.address, pri_data_ref | new_one_raw, pri_data_fuse, {reason, " DUT_FUSE primary"})
    `CHECK_DATA_MATCH(tr.address, shd_data_ref | new_one_raw, shd_data_fuse, {reason, " DUT_FUSE shadow"})
    `CHECK_DATA_MATCH(tr.address, mem_data | new_one, hw_data, {reason, " DUT_FUSE decoded"})

    check_pslverr(tr, expect_pslverr);
    write_fuse_word_by_pri_sdh(logic_addr, pri_data_ref | new_one_raw, shd_data_ref | new_one_raw, REF_FUSE, FORCE_WRITE);
  end
endtask

function int efuse_ctrl_scoreboard::get_region_res_index(bit [31:0] logic_addr);
  if (logic_addr >= 32'h84 && logic_addr < 32'h8C) return 0;
  if (logic_addr >= 32'h8C && logic_addr < 32'h90) return 1;
  if (logic_addr >= 32'h90 && logic_addr < 32'hA0) return 2;
  if (logic_addr >= 32'hA0 && logic_addr < 32'hA4) return 3;
  if (logic_addr >= 32'hA4 && logic_addr < 32'hAC) return 4;
  if (logic_addr >= 32'hAC && logic_addr < 32'hB8) return 5;
  if (logic_addr >= 32'hB8 && logic_addr < 32'h13C) return 6;
  if (logic_addr >= 32'h13C && logic_addr < 32'h200) return 7;
  return -1;
endfunction

task efuse_ctrl_scoreboard::is_write_disabled(bit [31:0] logic_addr, output bit disabled);
  bit [31:0] wr_acc_dis_word;
  bit [31:0] pri_data;
  bit [31:0] shd_data;
  bit        force_normal_mode;
  int        region_idx;
  force_normal_mode = 1'b1;
  region_idx = get_region_res_index(logic_addr);
  if (region_idx < 0 || region_idx > 7) begin
    disabled = 1'b0;
    return;
  end
  read_word(WR_RD_ACC_DIS_START, wr_acc_dis_word, pri_data, shd_data, REF_SRAM, force_normal_mode);
  disabled = wr_acc_dis_word[region_idx];
endtask

task efuse_ctrl_scoreboard::is_read_disabled(bit [31:0] logic_addr, output bit disabled);
  bit [31:0] rd_acc_dis_word;
  bit [31:0] pri_data;
  bit [31:0] shd_data;
  bit        force_normal_mode;
  int        region_idx;
  force_normal_mode = 1'b1;
  region_idx = get_region_res_index(logic_addr);
  if (region_idx < 0 || region_idx > 7) begin
    disabled = 1'b0;
    return;
  end
  read_word(WR_RD_ACC_DIS_START + 4, rd_acc_dis_word, pri_data, shd_data, REF_SRAM, force_normal_mode);
  disabled = rd_acc_dis_word[region_idx];
endtask

task efuse_ctrl_scoreboard::get_shadow_sram_acc_bit(output bit val);
  bit [31:0] word_data;
  bit [31:0] pri_data;
  bit [31:0] shd_data;
  bit        force_normal_mode;
  force_normal_mode = 1'b1;
  read_word(32'hA8, word_data, pri_data, shd_data, REF_SRAM, force_normal_mode);
  val = word_data[10];
endtask

task efuse_ctrl_scoreboard::get_top_acc_sec_region_bit(output bit val);
  bit [31:0] word_data;
  bit [31:0] pri_data;
  bit [31:0] shd_data;
  bit        force_normal_mode;
  force_normal_mode = 1'b1;
  read_word(32'hA8, word_data, pri_data, shd_data, REF_SRAM, force_normal_mode);
  val = word_data[9];
endtask

function bit efuse_ctrl_scoreboard::is_secure_region(bit [31:0] addr);
  return (addr >= EFUSE_BASE_ADDR) && (addr < EFUSE_BASE_ADDR + SECURE_REGION_END);
endfunction

function bit efuse_ctrl_scoreboard::is_valid_efuse_addr(bit [31:0] addr);
  return (addr >= EFUSE_BASE_ADDR) && (addr < EFUSE_BASE_ADDR + EFUSE_SIZE);
endfunction

task efuse_ctrl_scoreboard::run_phase(uvm_phase phase);
  super.run_phase(phase);
  if (efuse_ctrl_vif.dft_dc_scan_mode === 1'b1) begin
    `uvm_info(get_type_name(), "dft_dc_scan_mode is high, skip all scoreboard checks", UVM_LOW)
    return;
  end
  fork
    apbs_checker();
    apbp_checker();
    load_checker();
  join
endtask

//----------------------------------------------------------------------------
// Backdoor access wrapper implementations
//----------------------------------------------------------------------------
function logic efuse_ctrl_scoreboard::fuse_data(logic [fuse_addr_size - 1 : 0] A, mem_type_enum mem_type);
  case (mem_type)
    REF_FUSE: return ref_fuse_data[A];
    DUT_FUSE: return efuse_ctrl_vif.fuse_data(A);
    default: begin
      `uvm_error(get_type_name(), $sformatf("fuse_data called with invalid mem_type=%s", mem_type.name()))
      return 1'b0;
    end
  endcase
endfunction

function logic efuse_ctrl_scoreboard::test_row(logic [1 : 0] A_7_6, logic [out_addr_size - 1 : 0] k, mem_type_enum mem_type);
  if (mem_type == REF_FUSE) begin
    return ref_test_row[A_7_6][k];
  end else if (mem_type == DUT_FUSE) begin
    return efuse_ctrl_vif.test_row(A_7_6, k);
  end else begin
    `uvm_error(get_type_name(), $sformatf("test_row does not support mem_type=%s", mem_type.name()))
    return 1'b0;
  end
endfunction

function logic efuse_ctrl_scoreboard::test_row_2(logic [1 : 0] A_7_6, logic [out_addr_size - 1 : 0] k, mem_type_enum mem_type);
  if (mem_type == REF_FUSE) begin
    return ref_test_row_2[A_7_6][k];
  end else if (mem_type == DUT_FUSE) begin
    return efuse_ctrl_vif.test_row_2(A_7_6, k);
  end else begin
    `uvm_error(get_type_name(), $sformatf("test_row_2 does not support mem_type=%s", mem_type.name()))
    return 1'b0;
  end
endfunction

function logic efuse_ctrl_scoreboard::test_column(logic AT_0, logic [5 : 0] test_col_A, mem_type_enum mem_type);
  if (mem_type == REF_FUSE) begin
    return ref_test_column[AT_0][test_col_A];
  end else if (mem_type == DUT_FUSE) begin
    return efuse_ctrl_vif.test_column(AT_0, test_col_A);
  end else begin
    `uvm_error(get_type_name(), $sformatf("test_column does not support mem_type=%s", mem_type.name()))
    return 1'b0;
  end
endfunction

function void efuse_ctrl_scoreboard::write_fuse_data(logic [fuse_addr_size - 1 : 0] A, logic d, mem_type_enum mem_type);
  case (mem_type)
    REF_FUSE: ref_fuse_data[A] = d;
    DUT_FUSE: efuse_ctrl_vif.write_fuse_data(A, d);
    default:  `uvm_error(get_type_name(), $sformatf("write_fuse_data called with invalid mem_type=%s", mem_type.name()))
  endcase
endfunction

function void efuse_ctrl_scoreboard::write_test_row(logic [1 : 0] A_7_6, logic [out_addr_size - 1 : 0] k, logic d, mem_type_enum mem_type);
  if (mem_type == REF_FUSE) begin
    ref_test_row[A_7_6][k] = d;
  end else if (mem_type == DUT_FUSE) begin
    efuse_ctrl_vif.write_test_row(A_7_6, k, d);
  end else begin
    `uvm_error(get_type_name(), $sformatf("write_test_row does not support mem_type=%s", mem_type.name()))
  end
endfunction

function void efuse_ctrl_scoreboard::write_test_row_2(logic [1 : 0] A_7_6, logic [out_addr_size - 1 : 0] k, logic d, mem_type_enum mem_type);
  if (mem_type == REF_FUSE) begin
    ref_test_row_2[A_7_6][k] = d;
  end else if (mem_type == DUT_FUSE) begin
    efuse_ctrl_vif.write_test_row_2(A_7_6, k, d);
  end else begin
    `uvm_error(get_type_name(), $sformatf("write_test_row_2 does not support mem_type=%s", mem_type.name()))
  end
endfunction

function void efuse_ctrl_scoreboard::write_test_column(logic AT_0, logic [5 : 0] test_col_A, logic d, mem_type_enum mem_type);
  if (mem_type == REF_FUSE) begin
    ref_test_column[AT_0][test_col_A] = d;
  end else if (mem_type == DUT_FUSE) begin
    efuse_ctrl_vif.write_test_column(AT_0, test_col_A, d);
  end else begin
    `uvm_error(get_type_name(), $sformatf("write_test_column does not support mem_type=%s", mem_type.name()))
  end
endfunction

//----------------------------------------------------------------------------
// High-level fuse read/write task implementations
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::ReadFuse(
  input logic [fuse_addr_size - 1 : 0] A_i,
  output logic [out_size - 1 : 0]      Q_d,
  input mem_type_enum                  mem_type,
  input bit                            force_normal_mode
);
  logic [fuse_addr_size - 1 : 0] internal_A;
  logic [out_addr_size - 1 : 0]  k;
  logic [5 : 0]                  test_col_A;
  logic                          test_mode;
  logic [1 : 0]                  AT_i;
  int                            j;

  if (reg_model == null) begin
    `uvm_fatal(get_type_name(), "ReadFuse: reg_model is null, cannot read efuse_ctrl_acc_cfg")
  end

  test_mode = force_normal_mode ? 1'b0 : reg_model.efuse_ctrl_acc_cfg.efuse_test_mode.get();
  AT_i      = reg_model.efuse_ctrl_acc_cfg.efuse_test_row_col.get();

  if (test_mode === 1'b0) begin // normal read
    for (j = 0; j <= {out_addr_size{1'b1}}; j = j + 1) begin
      k = j[out_addr_size-1:0];
      internal_A[fuse_addr_size-1 : fuse_addr_size-out_addr_size] = k;
      internal_A[read_addr_size-1 : 0] = A_i[read_addr_size-1 : 0];
      Q_d[k] = fuse_data(internal_A, mem_type);
    end
  end
  else if (test_mode === 1'b1 && AT_i[0] === 1'b0 && AT_i[1] === 1'b0) begin // read 1st test row
    for (j = 0; j <= {out_addr_size{1'b1}}; j = j + 1) begin
      k = j[out_addr_size-1:0];
      internal_A[fuse_addr_size-1 : fuse_addr_size-out_addr_size] = k;
      internal_A[read_addr_size-1 : 0] = A_i[read_addr_size-1 : 0];
      Q_d[k] = test_row(A_i[7:6], k, mem_type);
    end
  end
  else if (test_mode === 1'b1 && AT_i[0] === 1'b1 && AT_i[1] === 1'b0) begin // read 2nd test row
    for (j = 0; j <= {out_addr_size{1'b1}}; j = j + 1) begin
      k = j[out_addr_size-1:0];
      internal_A[fuse_addr_size-1 : fuse_addr_size-out_addr_size] = k;
      internal_A[read_addr_size-1 : 0] = A_i[read_addr_size-1 : 0];
      Q_d[k] = test_row_2(A_i[7:6], k, mem_type);
    end
  end
  else if (test_mode === 1'b1 && (AT_i[0] === 1'b0 || AT_i[0] === 1'b1) && AT_i[1] === 1'b1) begin // read 1st/2nd test column
    test_col_A = A_i[5:0];
    for (j = 0; j <= {out_addr_size{1'b1}}; j = j + 1) begin
      k = j[out_addr_size-1:0];
      internal_A[fuse_addr_size-1 : fuse_addr_size-out_addr_size] = k;
      internal_A[read_addr_size-1 : 0] = A_i[read_addr_size-1 : 0];
      if (AT_i[0] === 1'b0 && j == 0) begin
        Q_d[k] = test_column(AT_i[0], test_col_A, mem_type);
      end
      else if (AT_i[0] === 1'b1 && j == {out_addr_size{1'b1}}) begin
        Q_d[k] = test_column(AT_i[0], test_col_A, mem_type);
      end
      else begin
        Q_d[k] = 1'bx;
      end
    end
  end
endtask

task efuse_ctrl_scoreboard::WriteFuse(
  input logic [fuse_addr_size - 1 : 0] A_i,
  input logic                          D,
  input mem_type_enum                  mem_type,
  input write_type_enum                write_type,
  input bit                            force_normal_mode
);
  logic [fuse_addr_size - 1 : 0] internal_A;
  logic [out_addr_size - 1 : 0]  test_row_A;
  logic [5 : 0]                  test_col_A;
  logic                          test_mode;
  logic [1 : 0]                  AT_i;
  logic                          old_d;

  if (reg_model == null) begin
    `uvm_fatal(get_type_name(), "WriteFuse: reg_model is null, cannot read efuse_ctrl_acc_cfg")
  end

  test_mode = force_normal_mode ? 1'b0 : reg_model.efuse_ctrl_acc_cfg.efuse_test_mode.get();
  AT_i      = reg_model.efuse_ctrl_acc_cfg.efuse_test_row_col.get();

  if (write_type === BURN_WRITE && D !== 1'b1) begin
    return;
  end

  if (test_mode === 1'b0) begin // burn fuse
    internal_A = A_i;

    if (write_type === BURN_WRITE) begin
      old_d = fuse_data(A_i, mem_type);
      if (old_d === 1'b1) begin
        return;
      end
    end

    write_fuse_data(A_i, D, mem_type);
  end
  else if (test_mode === 1'b1 && AT_i[0] === 1'b0 && AT_i[1] === 1'b0) begin // write 1st test row
    test_row_A = A_i[fuse_addr_size - 1 : read_addr_size];

    if (write_type === BURN_WRITE) begin
      old_d = test_row(A_i[7:6], test_row_A, mem_type);
      if (old_d === 1'b1) begin
        return;
      end
    end

    write_test_row(A_i[7:6], test_row_A, D, mem_type);
  end
  else if (test_mode === 1'b1 && AT_i[0] === 1'b1 && AT_i[1] === 1'b0) begin // write 2nd test row
    test_row_A = A_i[fuse_addr_size - 1 : read_addr_size];

    if (write_type === BURN_WRITE) begin
      old_d = test_row_2(A_i[7:6], test_row_A, mem_type);
      if (old_d === 1'b1) begin
        return;
      end
    end

    write_test_row_2(A_i[7:6], test_row_A, D, mem_type);
  end
  else if (test_mode === 1'b1 && (AT_i[0] === 1'b0 || AT_i[0] === 1'b1) && AT_i[1] === 1'b1) begin // write 1st/2nd test column
    test_col_A = A_i[5:0];

    if (write_type === BURN_WRITE) begin
      old_d = test_column(AT_i[0], test_col_A, mem_type);
      if (old_d === 1'b1) begin
        return;
      end
    end

    write_test_column(AT_i[0], test_col_A, D, mem_type);
  end
endtask

//----------------------------------------------------------------------------
// ReadSram: Read a 32-bit word from SRAM backdoor
// SRAM is word-addressable, no primary/shadow split, no LFSR
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::ReadSram(
  input bit [31:0]    addr,
  output bit [31:0]   word_data,
  input mem_type_enum mem_type
);
  case (mem_type)
    DUT_SRAM: word_data = efuse_ctrl_vif.sram_data(addr[8:2]);
    REF_SRAM: word_data = ref_sram_data[addr[8:2]];
    default: begin
      `uvm_error(get_type_name(), $sformatf("ReadSram called with invalid mem_type=%s", mem_type.name()))
      word_data = '0;
    end
  endcase
endtask

//----------------------------------------------------------------------------
// WriteSram: Write a 32-bit word to SRAM backdoor
// SRAM is word-addressable, no primary/shadow split, no LFSR
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::WriteSram(
  input bit [31:0]    addr,
  input bit [31:0]    word_data,
  input mem_type_enum mem_type
);
  case (mem_type)
    DUT_SRAM: efuse_ctrl_vif.write_sram_data(addr[8:2], word_data);
    REF_SRAM: ref_sram_data[addr[8:2]] = word_data;
    default:  `uvm_error(get_type_name(), $sformatf("WriteSram called with invalid mem_type=%s", mem_type.name()))
  endcase
endtask

//----------------------------------------------------------------------------
// apbs_checker: Secure master dispatcher
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apbs_checker();
  svt_apb_transaction tr;
  bit test_mode;

  forever begin
    apbs_port.get(tr);

    `uvm_info(get_type_name(), $sformatf(
      "[APBS] %s addr=0x%08x data=0x%08x",
      tr.xact_type.name(), tr.address, tr.data
    ), UVM_MEDIUM)

    // Secure master only accesses eFuse region; register access branch is not applicable.
    if (is_before_efuse_load_done(tr)) begin
      apbs_efuse_load_not_done_check(tr);
    end else begin
      test_mode = reg_model.efuse_ctrl_acc_cfg.efuse_test_mode.get();
      if (test_mode === 1'b1) begin
        apbs_test_mode_checker(tr);
      end else begin
        apbs_efuse_access_checker(tr);
      end
    end
  end
endtask

//----------------------------------------------------------------------------
// apbs_reg_checker: Secure master register access (below eFuse base address)
// Secure master is not allowed to access registers: write invalid, read=0, pslverr=1
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apbs_reg_checker(svt_apb_transaction tr);
  bit expect_pslverr = 1'b1;

  `uvm_info(get_type_name(), $sformatf(
    "[APBS_REG] %s addr=0x%08x data=0x%08x (non-eFuse register, access denied)",
    tr.xact_type.name(), tr.address, tr.data
  ), UVM_MEDIUM)

  check_pslverr(tr, expect_pslverr);
  if (tr.xact_type == svt_apb_transaction::READ) begin
    check_read_data(tr, 32'h0, "secure master register access denied");
  end
endtask

//----------------------------------------------------------------------------
// apbs_test_mode_checker: Secure master eFuse access in test mode
// Illegal SRAM access: write invalid, read=0.
// Legal access: dispatch to good_trans (follows test_mode for test row/col access).
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apbs_test_mode_checker(svt_apb_transaction tr);
  bit read_from_efuse;
  bit shadow_sram_acc;
  bit wr_en;
  bit illegal_sram_access;
  bit [31:0] sram_data;
  bit [31:0] ref_sram_data;
  bit [31:0] pri_data;
  bit [31:0] shd_data;

  read_from_efuse = reg_model.efuse_ctrl_acc_cfg.read_from_efuse.get();
  get_shadow_sram_acc_bit(shadow_sram_acc);
  wr_en = reg_model.efuse_shadow_sram.wr_en.get();

  // In test mode, SRAM access is illegal when enabled:
  //   - read_from_efuse == 0 means SRAM read is enabled -> illegal
  //   - shadow_sram_acc == 0 means SRAM write is enabled and wr_en == 1 -> illegal
  illegal_sram_access = (tr.xact_type == svt_apb_transaction::READ  && read_from_efuse === 1'b0) ||
                        (tr.xact_type == svt_apb_transaction::WRITE && shadow_sram_acc === 1'b0 && wr_en === 1'b1);

  `uvm_info(get_type_name(), $sformatf(
    "[APBS_TEST] %s addr=0x%08x read_from_efuse=%0b shadow_sram_acc=%0b wr_en=%0b illegal_sram=%0b",
    tr.xact_type.name(), tr.address, read_from_efuse, shadow_sram_acc, wr_en, illegal_sram_access
  ), UVM_HIGH)

  if (illegal_sram_access) begin
    check_pslverr(tr, 1'b0);
    if (tr.xact_type == svt_apb_transaction::READ) begin
      check_read_data(tr, 32'h0, "test mode illegal sram read");
    end else begin
      read_word(tr.address, sram_data, pri_data, shd_data, DUT_SRAM, 1'b1);
      read_word(tr.address, ref_sram_data, pri_data, shd_data, REF_SRAM, 1'b1);
      `CHECK_DATA_MATCH(tr.address, ref_sram_data, sram_data, "test mode illegal sram write, DUT_SRAM unchanged")
    end
  end else begin
    test_mode_good_trans_checker_and_ref_update(tr, tr.address, "secure master test mode efuse access");
  end
endtask

//----------------------------------------------------------------------------
// apbs_efuse_access_checker: Split into accessible/access_deny/reverse eFuse region
// For non-reverse region, if the transaction started before the efuse_load_done rising edge, write is ignored and read=0.
// PPROT1 (secure/non-secure) handling is performed inside good_trans_checker_and_ref_update.
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apbs_efuse_access_checker(svt_apb_transaction tr);
  if (tr.address >= EFUSE_SIZE) begin
    apbs_efuse_reverse_check(tr);
  end else if (is_before_efuse_load_done(tr)) begin
    apbs_efuse_load_not_done_check(tr);
  end else if (tr.address < SECURE_REGION_END) begin
    apbs_efuse_accessible_check(tr);
  end else begin
    apbs_efuse_access_deny_check(tr);
  end
endtask

//----------------------------------------------------------------------------
// apbs_efuse_accessible_check: Secure master within secure region
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apbs_efuse_accessible_check(svt_apb_transaction tr);
  good_trans_checker_and_ref_update(tr, tr.address, "secure master efuse access");
endtask

//----------------------------------------------------------------------------
// apbs_efuse_access_deny_check: Secure master in EFUSE region but outside secure region
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apbs_efuse_access_deny_check(svt_apb_transaction tr);
  bit [31:0] mem_data;
  bit [31:0] hw_data;
  bit [31:0] pri_data;
  bit [31:0] shd_data;

  `uvm_info(get_type_name(), $sformatf(
    "[APBS] Access denied! addr=0x%08x in EFUSE region but outside secure region", tr.address
  ), UVM_HIGH)

  check_pslverr(tr, 1'b1);
  if (tr.xact_type == svt_apb_transaction::READ) begin
    check_read_data(tr, 32'h0, "access denied");
  end else begin
    read_word(tr.address, mem_data, pri_data, shd_data, REF_FUSE);
    read_word(tr.address, hw_data, pri_data, shd_data, DUT_FUSE);
    `CHECK_DATA_MATCH(tr.address, mem_data, hw_data, "access denied, DUT_FUSE unchanged")
  end
endtask

//----------------------------------------------------------------------------
// apbs_efuse_load_not_done_check: Secure master in non-reverse eFuse region before load done
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apbs_efuse_load_not_done_check(svt_apb_transaction tr);
  bit [31:0] mem_data;
  bit [31:0] hw_data;
  bit [31:0] pri_data;
  bit [31:0] shd_data;

  `uvm_info(get_type_name(), $sformatf(
    "[APBS] before efuse_load_done rising edge! addr=0x%08x write ignored, read=0, only check fuse",
    tr.address
  ), UVM_HIGH)

  check_pslverr(tr, 1'b0);
  if (tr.xact_type == svt_apb_transaction::READ) begin
    check_read_data(tr, 32'h0, "efuse load not done");
  end else begin
    read_word(tr.address, mem_data, pri_data, shd_data, REF_FUSE, 1'b1);
    read_word(tr.address, hw_data, pri_data, shd_data, DUT_FUSE, 1'b1);
    `CHECK_DATA_MATCH(tr.address, mem_data, hw_data, "efuse load not done, DUT_FUSE unchanged")
  end
endtask

//----------------------------------------------------------------------------
// apbs_efuse_reverse_check: Secure master in EFUSE REVERSE region
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apbs_efuse_reverse_check(svt_apb_transaction tr);
  `uvm_info(get_type_name(), $sformatf(
    "[APBS] EFUSE REVERSE region: addr=0x%08x (no pslverr)", tr.address
  ), UVM_HIGH)

  check_pslverr(tr, 1'b0);
  if (tr.xact_type == svt_apb_transaction::READ) begin
    check_read_data(tr, 32'h0, "reverse region read");
  end
endtask

//----------------------------------------------------------------------------
// apbp_checker: Public master dispatcher
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apbp_checker();
  svt_apb_transaction tr;
  bit test_mode;

  forever begin
    apbp_port.get(tr);

    `uvm_info(get_type_name(), $sformatf(
      "[APBP] %s addr=0x%08x data=0x%08x",
      tr.xact_type.name(), tr.address, tr.data
    ), UVM_MEDIUM)

    // Split into register access and eFuse access
    if (tr.address < EFUSE_BASE_ADDR) begin
      apbp_reg_checker(tr);
    end else if (is_before_efuse_load_done(tr)) begin
      apbp_efuse_load_not_done_check(tr);
    end else begin
      test_mode = reg_model.efuse_ctrl_acc_cfg.efuse_test_mode.get();
      if (test_mode === 1'b1) begin
        apbp_test_mode_checker(tr);
      end else begin
        apbp_efuse_access_checker(tr);
      end
    end
  end
endtask

//----------------------------------------------------------------------------
// apbp_test_mode_checker: Public master eFuse access in test mode
// Illegal SRAM access: write invalid, read=0.
// Legal access: dispatch to good_trans (follows test_mode for test row/col access).
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apbp_test_mode_checker(svt_apb_transaction tr);
  bit read_from_efuse;
  bit shadow_sram_acc;
  bit wr_en;
  bit illegal_sram_access;
  bit [31:0] sram_data;
  bit [31:0] ref_sram_data;
  bit [31:0] pri_data;
  bit [31:0] shd_data;

  read_from_efuse = reg_model.efuse_ctrl_acc_cfg.read_from_efuse.get();
  get_shadow_sram_acc_bit(shadow_sram_acc);
  wr_en = reg_model.efuse_shadow_sram.wr_en.get();

  // In test mode, SRAM access is illegal when enabled:
  //   - read_from_efuse == 0 means SRAM read is enabled -> illegal
  //   - shadow_sram_acc == 0 means SRAM write is enabled and wr_en == 1 -> illegal
  illegal_sram_access = (tr.xact_type == svt_apb_transaction::READ  && read_from_efuse === 1'b0) ||
                        (tr.xact_type == svt_apb_transaction::WRITE && shadow_sram_acc === 1'b0 && wr_en === 1'b1);

  `uvm_info(get_type_name(), $sformatf(
    "[APBP_TEST] %s addr=0x%08x read_from_efuse=%0b shadow_sram_acc=%0b wr_en=%0b illegal_sram=%0b",
    tr.xact_type.name(), tr.address, read_from_efuse, shadow_sram_acc, wr_en, illegal_sram_access
  ), UVM_HIGH)

  if (illegal_sram_access) begin
    check_pslverr(tr, 1'b0);
    if (tr.xact_type == svt_apb_transaction::READ) begin
      check_read_data(tr, 32'h0, "test mode illegal sram read");
    end else begin
      read_word(tr.address - EFUSE_BASE_ADDR, sram_data, pri_data, shd_data, DUT_SRAM, 1'b1);
      read_word(tr.address - EFUSE_BASE_ADDR, ref_sram_data, pri_data, shd_data, REF_SRAM, 1'b1);
      `CHECK_DATA_MATCH(tr.address, ref_sram_data, sram_data, "test mode illegal sram write, DUT_SRAM unchanged")
    end
  end else begin
    test_mode_good_trans_checker_and_ref_update(tr, tr.address - EFUSE_BASE_ADDR, "public master test mode efuse access");
  end
endtask

//----------------------------------------------------------------------------
// apbp_efuse_access_checker: Split into accessible/access_deny/reverse eFuse region
// For non-reverse region, if the transaction started before the efuse_load_done rising edge, write is ignored and read=0.
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apbp_efuse_access_checker(svt_apb_transaction tr);
  bit in_secure;
  bit top_acc_sec_region;
  bit write_dis;
  bit read_dis;

  in_secure = is_secure_region(tr.address);

  if (tr.address >= EFUSE_BASE_ADDR + EFUSE_SIZE) begin
    apbp_efuse_reverse_check(tr);
  end else if (is_before_efuse_load_done(tr)) begin
    apbp_efuse_load_not_done_check(tr);
  end else if (in_secure) begin
    get_top_acc_sec_region_bit(top_acc_sec_region);
    if (top_acc_sec_region == 1'b0) begin
      apbp_efuse_accessible_check(tr);
    end else begin
      apbp_efuse_access_deny_check(tr);
    end
  end else begin
    // Non-secure valid eFuse: dispatch by region_res disable
    is_write_disabled(tr.address - EFUSE_BASE_ADDR, write_dis);
    is_read_disabled(tr.address - EFUSE_BASE_ADDR, read_dis);
    if ((tr.xact_type == svt_apb_transaction::WRITE && write_dis) ||
        (tr.xact_type == svt_apb_transaction::READ  && read_dis)) begin
      apbp_efuse_access_deny_check(tr);
    end else begin
      apbp_efuse_accessible_check(tr);
    end
  end
endtask

//----------------------------------------------------------------------------
// apbp_efuse_accessible_check: Public master accessible eFuse access
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apbp_efuse_accessible_check(svt_apb_transaction tr);
  `uvm_info(get_type_name(), $sformatf(
    "[APBP] Access granted: addr=0x%08x", tr.address
  ), UVM_HIGH)

  good_trans_checker_and_ref_update(tr, tr.address - EFUSE_BASE_ADDR, "public master efuse access");
endtask

//----------------------------------------------------------------------------
// apbp_efuse_access_deny_check: Public master access denied in eFuse region
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apbp_efuse_access_deny_check(svt_apb_transaction tr);
  bit [31:0] mem_data;
  bit [31:0] hw_data;
  bit [31:0] pri_data;
  bit [31:0] shd_data;
  bit        in_valid_efuse;

  in_valid_efuse = is_valid_efuse_addr(tr.address);

  `uvm_info(get_type_name(), $sformatf(
    "[APBP] Access denied! addr=0x%08x in eFuse region", tr.address
  ), UVM_HIGH)

  check_pslverr(tr, 1'b1);
  if (tr.xact_type == svt_apb_transaction::READ) begin
    check_read_data(tr, 32'h0, "access denied");
  end else if (in_valid_efuse) begin
    // For valid eFuse region, write is ignored but eFuse data unchanged
    read_word(tr.address - EFUSE_BASE_ADDR, mem_data, pri_data, shd_data, REF_FUSE);
    read_word(tr.address - EFUSE_BASE_ADDR, hw_data, pri_data, shd_data, DUT_FUSE);
    `CHECK_DATA_MATCH(tr.address, mem_data, hw_data, "access denied, DUT_FUSE unchanged")
  end
endtask

//----------------------------------------------------------------------------
// apbp_efuse_load_not_done_check: Public master in non-reverse eFuse region before load done
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apbp_efuse_load_not_done_check(svt_apb_transaction tr);
  bit [31:0] mem_data;
  bit [31:0] hw_data;
  bit [31:0] pri_data;
  bit [31:0] shd_data;

  `uvm_info(get_type_name(), $sformatf(
    "[APBP] before efuse_load_done rising edge! addr=0x%08x write ignored, read=0, only check fuse",
    tr.address
  ), UVM_HIGH)

  check_pslverr(tr, 1'b0);
  if (tr.xact_type == svt_apb_transaction::READ) begin
    check_read_data(tr, 32'h0, "efuse load not done");
  end else begin
    read_word(tr.address - EFUSE_BASE_ADDR, mem_data, pri_data, shd_data, REF_FUSE, 1'b1);
    read_word(tr.address - EFUSE_BASE_ADDR, hw_data, pri_data, shd_data, DUT_FUSE, 1'b1);
    `CHECK_DATA_MATCH(tr.address, mem_data, hw_data, "efuse load not done, DUT_FUSE unchanged")
  end
endtask

//----------------------------------------------------------------------------
// apbp_efuse_reverse_check: Public master in EFUSE REVERSE region
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apbp_efuse_reverse_check(svt_apb_transaction tr);
  `uvm_info(get_type_name(), $sformatf(
    "[APBP] EFUSE REVERSE region: addr=0x%08x (no pslverr)", tr.address
  ), UVM_HIGH)

  check_pslverr(tr, 1'b0);
  if (tr.xact_type == svt_apb_transaction::READ) begin
    check_read_data(tr, 32'h0, "reverse region read");
  end
endtask

//----------------------------------------------------------------------------
// apbp_reg_checker: Handle APB public master access to non-eFuse registers
// (addresses below EFUSE_BASE_ADDR).
// When address > 0x44, access is denied: write invalid, read=0, pslverr=1.
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::apbp_reg_checker(svt_apb_transaction tr);
  bit expect_pslverr;

  if (tr.address > 32'h44) begin
    expect_pslverr = 1'b1;

    `uvm_info(get_type_name(), $sformatf(
      "[APBP_REG] %s addr=0x%08x data=0x%08x (non-eFuse register, access denied)",
      tr.xact_type.name(), tr.address, tr.data
    ), UVM_MEDIUM)

    check_pslverr(tr, expect_pslverr);
    if (tr.xact_type == svt_apb_transaction::READ) begin
      check_read_data(tr, 32'h0, "public master register access denied");
    end
  end else begin
    `uvm_info(get_type_name(), $sformatf(
      "[APBP_REG] %s addr=0x%08x data=0x%08x (non-eFuse register, below/equal 0x44, placeholder)",
      tr.xact_type.name(), tr.address, tr.data
    ), UVM_MEDIUM)

    // Detect software load done: efuse_done_status bit1 becomes 1 on read
    if (tr.xact_type == svt_apb_transaction::READ &&
        tr.address == reg_model.efuse_done_status.get_offset() &&
        tr.data[1] == 1'b1) begin
      `uvm_info(get_type_name(), "[LOAD] software load done detected (efuse_done_status[1]=1)", UVM_MEDIUM)
      -> software_load_done_event;
    end

    // Detect writes to efuse_dcu_en register.
    // expect_dcu_en_bit only factors in the efuse_dcu_en register value once it has been written.
    if (tr.xact_type == svt_apb_transaction::WRITE &&
        tr.address == reg_model.efuse_dcu_en.get_offset()) begin
      `uvm_info(get_type_name(), $sformatf(
        "[APBP_REG] efuse_dcu_en register write detected at addr=0x%08x data=0x%08x",
        tr.address, tr.data
      ), UVM_MEDIUM)
      efuse_dcu_en_written = 1'b1;
      update_vif_sva_expect_val();
    end

    // Detect writes to efuse_ctrl_acc_cfg.
    // update_vif_sva_expect_val will drive vif.margin_read_mode from reg_model.
    if (tr.xact_type == svt_apb_transaction::WRITE &&
        tr.address == reg_model.efuse_ctrl_acc_cfg.get_offset()) begin
      `uvm_info(get_type_name(), $sformatf(
        "[APBP_REG] efuse_ctrl_acc_cfg write detected at addr=0x%08x data=0x%08x",
        tr.address, tr.data
      ), UVM_MEDIUM)
      update_vif_sva_expect_val();
    end
  end
endtask

//----------------------------------------------------------------------------
// load_checker: Wait for auto load and software load done, then verify
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::load_checker();
  fork
    auto_load_check();
    software_load_check();
  join
endtask

//----------------------------------------------------------------------------
// auto_load_check: Wait for efuse_load_done and verify loaded data
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::auto_load_check();
  `uvm_info(get_type_name(), "[LOAD] waiting for auto load done (efuse_load_done)", UVM_MEDIUM)
  @(posedge efuse_ctrl_vif.efuse_load_done);
  efuse_load_done_time     = $realtime;
  efuse_load_done_recorded = 1'b1;
  `uvm_info(get_type_name(), $sformatf("[LOAD] auto load done detected at time %0t", efuse_load_done_time), UVM_MEDIUM)
  do_load_verify("auto load");
  update_vif_sva_expect_val();
endtask

//----------------------------------------------------------------------------
// software_load_check: Wait for efuse_done_status[1]=1 and verify loaded data
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::software_load_check();
  `uvm_info(get_type_name(), "[LOAD] waiting for software load done (efuse_done_status[0]=1)", UVM_MEDIUM)
  @software_load_done_event;
  `uvm_info(get_type_name(), "[LOAD] software load done detected", UVM_MEDIUM)
  do_load_verify("software load");
  update_vif_sva_expect_val();
endtask

//----------------------------------------------------------------------------
// do_load_verify: Compare DUT_SRAM vs DUT_FUSE word-by-word,
// then copy ref_fuse_data to ref_sram_data
// test_mode will never be set during load, so no need to consider test row/col access here
//----------------------------------------------------------------------------
task efuse_ctrl_scoreboard::do_load_verify(string reason);
  int                        word_idx;
  bit [31:0]                 sram_word;
  bit [31:0]                 fuse_word;
  bit [31:0]                 pri_tmp;
  bit [31:0]                 shd_tmp;
  bit [31:0]                 addr;
  bit                        mismatch;

  `uvm_info(get_type_name(), $sformatf("[LOAD] start %s verify", reason), UVM_MEDIUM)

  mismatch = 1'b0;
  for (word_idx = 0; word_idx < fuse_size/32/2; word_idx++) begin
    addr = word_idx * 4;

    // DUT_SRAM: read through read_word instead of directly using sram_data
    read_word(addr, sram_word, pri_tmp, shd_tmp, DUT_SRAM, 1'b1);

    // DUT_FUSE: combine primary + shadow, then apply LFSR decode
    read_word(addr, fuse_word, pri_tmp, shd_tmp, DUT_FUSE, 1'b1);

    if (sram_word !== fuse_word) begin
      `uvm_error(get_type_name(), $sformatf(
        "[LOAD] %s mismatch at word[%0d] (addr=0x%08x): DUT_SRAM=0x%08x DUT_FUSE=0x%08x",
        reason, word_idx, addr, sram_word, fuse_word
      ))
      mismatch = 1'b1;
    end
  end

  if (!mismatch) begin
    `uvm_info(get_type_name(), $sformatf("[LOAD] %s DUT_SRAM/DUT_FUSE match", reason), UVM_MEDIUM)
  end

  // Copy ref_fuse_data to ref_sram_data word-by-word
  for (word_idx = 0; word_idx < fuse_size/32/2; word_idx++) begin
    addr = word_idx * 4;
    read_word(addr, ref_sram_data[word_idx], pri_tmp, shd_tmp, REF_FUSE, 1'b1);
  end
  `uvm_info(get_type_name(), $sformatf("[LOAD] %s ref_fuse_data copied to ref_sram_data", reason), UVM_MEDIUM)
endtask

`endif // EFUSE_CTRL_SCOREBOARD_SV
