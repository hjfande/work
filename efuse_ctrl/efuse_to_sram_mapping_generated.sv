//----------------------------------------------------------------------------
// Generated eFuse-to-SRAM mapping for debug
//
// Assumptions:
//   - eFuse macro `EFUSE_DATA is a 1-bit array indexed by 13-bit address
//   - SRAM debug_efuse_mapping_sram is declared as:
//       logic [31:0] debug_efuse_mapping_sram [EFUSE_SIZE/32/2-1:0];
//     i.e. 128 words of 32 bits each
//   - Each SRAM word/bit[bit_idx] at word_idx is the OR of the corresponding
//     primary and shadow eFuse bits:
//       primary fuse addr = {bit_idx[4:0], 1'b0, word_idx[6:0]}
//       shadow  fuse addr = {bit_idx[4:0], 1'b1, word_idx[6:0]}
//----------------------------------------------------------------------------

localparam int EFUSE_SIZE          = 8192;
localparam int EFUSE_FUSE_ADDR_SIZE= 13;
localparam int EFUSE_OUT_ADDR_SIZE = 5;
localparam int EFUSE_WORD_NUM      = EFUSE_SIZE / 32 / 2;  // 128

//----------------------------------------------------------------------------
// Option 1: Combinational mapping via generate block (recommended for debug)
// Copy this block into the interface.
//----------------------------------------------------------------------------
genvar gi, gj;
generate
  for (gi = 0; gi < EFUSE_WORD_NUM; gi++) begin : gen_efuse_sram_word
    for (gj = 0; gj < 32; gj++) begin : gen_efuse_sram_bit
      // primary fuse bit address: {k, 1'b0, word_index}
      // shadow  fuse bit address: {k, 1'b1, word_index}
      assign debug_efuse_mapping_sram[gi][gj] =
        `EFUSE_DATA[{gj[EFUSE_OUT_ADDR_SIZE-1:0], 1'b0, gi[6:0]}] |
        `EFUSE_DATA[{gj[EFUSE_OUT_ADDR_SIZE-1:0], 1'b1, gi[6:0]}];
    end
  end
endgenerate

//----------------------------------------------------------------------------
// Option 2: Function-based mapping (call whenever EFUSE_DATA changes)
// Copy this function into the interface and invoke it after eFuse update.
//----------------------------------------------------------------------------
function automatic void debug_update_efuse_to_sram_mapping();
  int word_idx;
  int bit_idx;
  bit [EFUSE_FUSE_ADDR_SIZE-1:0] pri_addr;
  bit [EFUSE_FUSE_ADDR_SIZE-1:0] shd_addr;

  for (word_idx = 0; word_idx < EFUSE_WORD_NUM; word_idx++) begin
    for (bit_idx = 0; bit_idx < 32; bit_idx++) begin
      pri_addr = {bit_idx[EFUSE_OUT_ADDR_SIZE-1:0], 1'b0, word_idx[6:0]};
      shd_addr = {bit_idx[EFUSE_OUT_ADDR_SIZE-1:0], 1'b1, word_idx[6:0]};
      debug_efuse_mapping_sram[word_idx][bit_idx] = `EFUSE_DATA[pri_addr] | `EFUSE_DATA[shd_addr];
    end
  end
endfunction

//----------------------------------------------------------------------------
// Option 3: Per-word helper function (returns one 32-bit SRAM word)
//----------------------------------------------------------------------------
function automatic bit [31:0] debug_get_sram_word_from_efuse(int word_idx);
  bit [31:0] sram_word;
  int        bit_idx;
  bit [EFUSE_FUSE_ADDR_SIZE-1:0] pri_addr;
  bit [EFUSE_FUSE_ADDR_SIZE-1:0] shd_addr;

  for (bit_idx = 0; bit_idx < 32; bit_idx++) begin
    pri_addr = {bit_idx[EFUSE_OUT_ADDR_SIZE-1:0], 1'b0, word_idx[6:0]};
    shd_addr = {bit_idx[EFUSE_OUT_ADDR_SIZE-1:0], 1'b1, word_idx[6:0]};
    sram_word[bit_idx] = `EFUSE_DATA[pri_addr] | `EFUSE_DATA[shd_addr];
  end
  return sram_word;
endfunction
