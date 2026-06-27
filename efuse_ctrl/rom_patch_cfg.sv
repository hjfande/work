`ifndef ROM_PATCH_CFG_SV
`define ROM_PATCH_CFG_SV

//----------------------------------------------------------------------------
// ROM patch configuration object
//
// Stores ROM patch entries and provides expected response lookup.
// - rom_patch_addr entries are WORD addresses (4-byte aligned).
// - get_expect() takes a WORD address and returns the hit/data for that
//   address group.
//----------------------------------------------------------------------------
class rom_patch_cfg extends uvm_object;

  `uvm_object_utils(rom_patch_cfg)

  // Number of patch entries
  localparam int ROM_PATCH_ENTRY_NUM = 32;

  // Data width for each patch entry (total data width / hit width)
  localparam int ROM_PATCH_WORD_DATA_WIDTH = ROM_CTRL_DATA_WIDTH / ROM_CTRL_HIT_WIDTH;

  // One hit bit per patch entry
  rand bit [ROM_PATCH_ENTRY_NUM-1:0] rom_patch_hit;

  // Word address for each patch entry
  rand bit [ROM_CTRL_ADDR_WIDTH-1:0] rom_patch_addr [ROM_PATCH_ENTRY_NUM];

  // 32-bit patch data for each entry
  rand bit [ROM_PATCH_WORD_DATA_WIDTH-1:0] rom_patch_data [ROM_PATCH_ENTRY_NUM];

  function new(string name = "rom_patch_cfg");
    super.new(name);
  endfunction

  // Get expected hit/data for a given word address.
  // Returns ROM_CTRL_HIT_WIDTH hit bits and ROM_CTRL_DATA_WIDTH data bits.
  function void get_expect(bit [ROM_CTRL_ADDR_WIDTH-1:0] word_addr,
                           output bit [ROM_CTRL_HIT_WIDTH-1:0] hit,
                           output bit [ROM_CTRL_DATA_WIDTH-1:0] data);
    bit [ROM_CTRL_VALID_ADDR_WIDTH-1-2:0] valid_word_addr;

    hit = '0;
    data = '0;
    valid_word_addr = word_addr[ROM_CTRL_VALID_ADDR_WIDTH-1-2:0];  // truncate to valid word address width

    // For each word offset in the address group, search rom_patch_addr from
    // the beginning. If the address matches and the hit bit is set, mark hit[j]
    // and OR the corresponding data into the result slice.
    for (int j = 0; j < ROM_CTRL_HIT_WIDTH; j++) begin
      bit [ROM_PATCH_WORD_DATA_WIDTH-1:0] slice_data = '0;
      hit[j] = 1'b0;
      foreach (rom_patch_addr[i]) begin
        if ((valid_word_addr + j) == rom_patch_addr[i] && rom_patch_hit[i] == 1'b1) begin
          hit[j] = 1'b1;
          slice_data = slice_data | rom_patch_data[i];
        end
      end
      data[ROM_PATCH_WORD_DATA_WIDTH*j +: ROM_PATCH_WORD_DATA_WIDTH] = slice_data;
    end
  endfunction

endclass

`endif // ROM_PATCH_CFG_SV
