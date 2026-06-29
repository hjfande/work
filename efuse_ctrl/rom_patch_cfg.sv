`ifndef ROM_PATCH_CFG_SV
`define ROM_PATCH_CFG_SV

//----------------------------------------------------------------------------
// ROM patch configuration object
//
// Stores ROM patch entries and provides expected response lookup.
// - rom_patch_byte_addr entries are BYTE addresses (4-byte aligned).
// - get_expect() takes a BYTE address and returns the hit/data for that
//   address group.
//----------------------------------------------------------------------------
class rom_patch_cfg extends uvm_object;

  // Allowed valid data widths. enum int so the value is usable directly in
  // arithmetic (e.g. valid_data_width / ROM_CTRL_WORD_DATA_WIDTH).
  typedef enum int {
    VALID_DW_32  = 32,
    VALID_DW_64  = 64,
    VALID_DW_128 = 128
  } valid_data_width_e;

  // Number of patch entries
  localparam int ROM_PATCH_ENTRY_NUM = 32;

  // Valid (used) data width, runtime-configurable via config_db (default = full
  // ROM_CTRL_DATA_WIDTH). The valid hit count derived from it may be smaller than
  // the physical ROM_CTRL_HIT_WIDTH.
  valid_data_width_e valid_data_width = VALID_DW_128;

  // When set, addresses within each group are forced to be consecutive words.
  // Group size = get_valid_hit_width() (128bit -> 4 entries, 64bit -> 2, 32bit -> 1).
  bit continue_addr_enable = 1;

  `uvm_object_utils_begin(rom_patch_cfg)
    `uvm_field_enum(valid_data_width_e, valid_data_width, UVM_ALL_ON)
    `uvm_field_int(continue_addr_enable,       UVM_ALL_ON)
    `uvm_field_sarray_int(rom_patch_byte_addr, UVM_ALL_ON)
    `uvm_field_sarray_int(rom_patch_data,      UVM_ALL_ON)
    `uvm_field_int(rom_patch_hit,              UVM_ALL_ON)
  `uvm_object_utils_end

  // One hit bit per patch entry
  rand bit [ROM_PATCH_ENTRY_NUM-1:0] rom_patch_hit;

  // Byte address for each patch entry (4-byte aligned)
  rand bit [ROM_CTRL_ADDR_WIDTH-1:0] rom_patch_byte_addr [ROM_PATCH_ENTRY_NUM];

  // 32-bit patch data for each entry
  rand bit [ROM_CTRL_WORD_DATA_WIDTH-1:0] rom_patch_data [ROM_PATCH_ENTRY_NUM];

  constraint rom_patch_addr_align_c {
    foreach (rom_patch_byte_addr[i])
      rom_patch_byte_addr[i][1:0] == 2'b00;  // each address is 4-byte aligned
  }

  // When continue_addr_enable is set, addresses within each group are
  // consecutive words: a non-group-first entry must equal the previous entry
  // plus one word (4 bytes). Group size follows valid_data_width:
  //   128bit -> 4 entries per group, 64bit -> 2, 32bit -> 1 (no constraint).
  constraint rom_patch_addr_continue_c {
    if (continue_addr_enable) {
      if (valid_data_width == VALID_DW_128) {
        foreach (rom_patch_byte_addr[i])
          if (i % 4 != 0)
            rom_patch_byte_addr[i] == rom_patch_byte_addr[i-1] + 4;
      } else if (valid_data_width == VALID_DW_64) {
        foreach (rom_patch_byte_addr[i])
          if (i % 2 != 0)
            rom_patch_byte_addr[i] == rom_patch_byte_addr[i-1] + 4;
      }
    }
  }

  function new(string name = "rom_patch_cfg");
    super.new(name);
  endfunction

  // Number of valid hit bits derived from the runtime valid data width.
  function int get_valid_hit_width();
    return valid_data_width / ROM_CTRL_WORD_DATA_WIDTH;
  endfunction

  // Get expected hit/data for a given byte address.
  // Returns ROM_CTRL_HIT_WIDTH hit bits and ROM_CTRL_DATA_WIDTH data bits.
  function void get_expect(bit [ROM_CTRL_ADDR_WIDTH-1:0] byte_addr,
                           output bit [ROM_CTRL_HIT_WIDTH-1:0] hit,
                           output bit [ROM_CTRL_DATA_WIDTH-1:0] data);
    bit [ROM_CTRL_ADDR_WIDTH-1:0] word_addr;

    hit = '0;
    data = '0;
    // Convert the byte address to a word address.
    word_addr = byte_addr[ROM_CTRL_ADDR_WIDTH-1:2];

    // For each word offset in the address group, search the patch entries from
    // the beginning. If the (byte) address matches and the hit bit is set, mark
    // hit[j] and OR the corresponding data into the result slice.
    for (int j = 0; j < get_valid_hit_width(); j++) begin
      bit [ROM_CTRL_WORD_DATA_WIDTH-1:0]   slice_data = '0;
      bit [ROM_CTRL_ADDR_WIDTH-1:0]        cmp_word_addr = word_addr + j;
      hit[j] = 1'b0;
      foreach (rom_patch_byte_addr[i]) begin
        if (cmp_word_addr == rom_patch_byte_addr[i][ROM_CTRL_ADDR_WIDTH-1:2] && rom_patch_hit[i] == 1'b1) begin
          hit[j] = 1'b1;
          slice_data = slice_data | rom_patch_data[i];
        end
      end
      data[ROM_CTRL_WORD_DATA_WIDTH*j +: ROM_CTRL_WORD_DATA_WIDTH] = slice_data;
    end
  endfunction

endclass

`endif // ROM_PATCH_CFG_SV
