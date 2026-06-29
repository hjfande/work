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

  // Number of patch entries
  localparam int ROM_PATCH_ENTRY_NUM = 32;

  // Valid (used) data width, runtime-configurable via config_db (default = full
  // ROM_CTRL_DATA_WIDTH). The valid hit count derived from it may be smaller than
  // the physical ROM_CTRL_HIT_WIDTH.
  rand int valid_data_width = ROM_CTRL_DATA_WIDTH;

  `uvm_object_utils_begin(rom_patch_cfg)
    `uvm_field_int(valid_data_width, UVM_ALL_ON)
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
    if (valid_data_width == 128) {
      foreach (rom_patch_byte_addr[i])
        rom_patch_byte_addr[i][3:0] == 4'b0000;  // 16-byte aligned
    } else if (valid_data_width == 64) {
      foreach (rom_patch_byte_addr[i])
        rom_patch_byte_addr[i][2:0] == 3'b00;  // 8-byte aligned
    } else if (valid_data_width == 32) {
      foreach (rom_patch_byte_addr[i])
        rom_patch_byte_addr[i][1:0] == 2'b00;  // 4-byte aligned
    }
    valid_data_width inside {32, 64, 128};
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
