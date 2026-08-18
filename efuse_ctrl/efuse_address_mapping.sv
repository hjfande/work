`ifndef EFUSE_ADDRESS_MAPPING_SV
`define EFUSE_ADDRESS_MAPPING_SV

//----------------------------------------------------------------------------
// EFUSE_CE region base address enum
//
// All values are byte offsets within the eFuse APB address space.
// Sourced from efuse_mapping.xlsx / sheet AON_EFUSE, Master = CE.
//----------------------------------------------------------------------------
typedef enum bit [31:0] {
  EFUSE_CE_MASTER_ID_ADDR   = 32'h000,
  EFUSE_CE_MODEL_KEY_ADDR   = 32'h004,
  EFUSE_CE_DEVICE_ID_ADDR   = 32'h014,
  EFUSE_CE_DEVICE_KEY_ADDR  = 32'h018,
  EFUSE_CE_PK_HASH_ADDR     = 32'h028,
  EFUSE_CE_LCS_STATE_ADDR   = 32'h048,
  EFUSE_CE_LOCK_CTRL_ADDR   = 32'h04C,
  EFUSE_CE_USR_NON_SEC_ADDR = 32'h050,
  EFUSE_CE_USR_SEC_ADDR     = 32'h070
} efuse_ce_addr_e;

//----------------------------------------------------------------------------
// EFUSE_TOP region base address enum
//
// All values are byte offsets within the eFuse APB address space.
// Sourced from efuse_mapping.xlsx / sheet AON_EFUSE, Master = TOP.
//----------------------------------------------------------------------------
typedef enum bit [31:0] {
  EFUSE_TOP_WR_ACC_DIS_ADDR    = 32'h074,
  EFUSE_TOP_RD_ACC_DIS_ADDR    = 32'h078,
  EFUSE_TOP_REGION_RES_0_ADDR  = 32'h07C,
  EFUSE_TOP_REGION_RES_1_ADDR  = 32'h084,
  EFUSE_TOP_REGION_RES_2_ADDR  = 32'h088,
  EFUSE_TOP_REGION_RES_3_ADDR  = 32'h098,
  EFUSE_TOP_REGION_RES_4_ADDR  = 32'h09C,
  EFUSE_TOP_REGION_RES_5_ADDR  = 32'h0A8,
  EFUSE_TOP_REGION_RES_6_ADDR  = 32'h0B0,
  EFUSE_TOP_REGION_RES_7_ADDR  = 32'h13C
} efuse_top_addr_e;

//----------------------------------------------------------------------------
// Region output signal width parameters (bit width of each region's DUT output)
//
// Sourced from efuse_mapping.xlsx / sheet AON_EFUSE region descriptions.
//----------------------------------------------------------------------------

// REGION_RES_1 (PartNum ID): 32-bit output
localparam int REGION_1_SIGNAL_SIZE_DEVICE_ID_BIT   = 32;

// REGION_RES_2 (DCU_EN / secure debug cfg): 32-bit output
localparam int REGION_2_SIGNAL_SIZE_DCU_EN_BIT      = 32;

// REGION_RES_3 (boot_cfg / boot_latch_pin): 10-bit output
localparam int REGION_3_SIGNAL_SIZE_BOOT_CFG_BIT    = 10;

// REGION_RES_4 (feature_cfg): 96-bit output
localparam int REGION_4_SIGNAL_SIZE_FEATURE_CFG_BIT = 96;

// REGION_RES_5 (memory_cfg): 64-bit output
localparam int REGION_5_SIGNAL_SIZE_MEM_CFG_BIT     = 64;

// REGION_RES_6 (analog calibration): 96-bit output
localparam int REGION_6_SIGNAL_SIZE_ANALOG_CALIBRE_BIT = 96;

//----------------------------------------------------------------------------
// Bit / field mapping parameters
//
// Sourced from efuse_mapping.xlsx / sheet AON_EFUSE, region descriptions.
//----------------------------------------------------------------------------

// Number of boot configuration pins (boot_cfg bit[9:0])
localparam int BOOT_PIN_NUMBER = 10;

// Boot select valid bit position within REGION_RES_3 (boot_cfg) word
//   bit[15] = efuse is burned and make sense
localparam int BOOT_SEL_PIN_BIT_MAP = 15;

// Alias: boot_cfg_vld is the same bit as boot_sel_pin (REGION_RES_3 bit[15])
localparam int BOOT_CFG_VLD_BIT_MAP = BOOT_SEL_PIN_BIT_MAP;

// Top access secure region disable bit position within REGION_RES_4 (feature_cfg)
//   bit[64] = top access eFuse secure region, 0=enable, 1=disable
localparam int TOP_ACC_SEC_REGION_BIT_MAP = 64;

// Shadow SRAM write enable bit position within REGION_RES_4 (feature_cfg)
//   bit[65] = shadow sram write enable, 0=enable, 1=disable
localparam int SHADOW_SRAM_ACC_BIT_MAP = 65;

//----------------------------------------------------------------------------
// eFuse key region deny address array
//
// All word-byte addresses of key / sensitive regions that non-secure
// masters should be denied access to.
//   - Model_Key   (16 bytes, 4 words)  @ 0x004 - 0x010
//   - Device_Key  (16 bytes, 4 words)  @ 0x018 - 0x024
//----------------------------------------------------------------------------
localparam bit [31:0] EFUSE_KEY_ACC_DENY_ADDR [] = '{
  // Model_Key (4 words)
  EFUSE_CE_MODEL_KEY_ADDR  + 32'h00,
  EFUSE_CE_MODEL_KEY_ADDR  + 32'h04,
  EFUSE_CE_MODEL_KEY_ADDR  + 32'h08,
  EFUSE_CE_MODEL_KEY_ADDR  + 32'h0C,
  // Device_Key (4 words)
  EFUSE_CE_DEVICE_KEY_ADDR + 32'h00,
  EFUSE_CE_DEVICE_KEY_ADDR + 32'h04,
  EFUSE_CE_DEVICE_KEY_ADDR + 32'h08,
  EFUSE_CE_DEVICE_KEY_ADDR + 32'h0C
};

//----------------------------------------------------------------------------
// eFuse function register deny address array
//
// Control / status registers that non-secure masters should be denied
// write (or read) access to.  Addresses are the first word of each
// function register region.
//
// Sourced from efuse_mapping.xlsx / sheet AON_EFUSE.
// Mapped to the new address space (old mapping in comments for reference).
//----------------------------------------------------------------------------
localparam bit [31:0] EFUSE_FUNC_ACC_DENY_ADDR [] = '{
  EFUSE_CE_LCS_STATE_ADDR,         // LCS_STATE                 (old: 32'h48)
  EFUSE_TOP_WR_ACC_DIS_ADDR,       // Top Region WR Disable     (old: 32'h7C)
  EFUSE_TOP_RD_ACC_DIS_ADDR,       // Top Region RD Disable     (old: 32'h80)
  EFUSE_TOP_REGION_RES_2_ADDR,     // DCU_EN_SEL / DCU_EN_LOCK  (old: 32'h90)
  EFUSE_TOP_REGION_RES_3_ADDR,     // Boot Cfg (bit[31] valid)  (old: 32'hA0)
  EFUSE_TOP_REGION_RES_4_ADDR      // Feature Cfg (top_acc_sec_region / shadow_sram_acc)
                                   //                           (old: 32'hA8)
};

`endif // EFUSE_ADDRESS_MAPPING_SV
