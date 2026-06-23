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
    hit = '0;
    data = '0;
    foreach (rom_patch_addr[i]) begin
      if (word_addr == rom_patch_addr[i]) begin
        for (int j = 0; j < ROM_CTRL_HIT_WIDTH; j++) begin
          if ((i + j) < ROM_PATCH_ENTRY_NUM &&
              rom_patch_hit[i+j] == 1'b1 &&
              (word_addr + j) == rom_patch_addr[i+j]) begin
            hit[j] = 1'b1;
            data[ROM_PATCH_WORD_DATA_WIDTH*j +: ROM_PATCH_WORD_DATA_WIDTH] = rom_patch_data[i+j];
          end else begin
            hit[j] = 1'b0;
          end
        end
        break;
      end
    end
  endfunction

endclass

`endif // ROM_PATCH_CFG_SV
