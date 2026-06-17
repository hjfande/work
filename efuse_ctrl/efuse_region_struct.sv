//----------------------------------------------------------------------------
// eFuse Region Packed Data Structures
// Total size: 512 bytes = 4096 bits
// Address offset: 0x00 ~ 0x1FF
//----------------------------------------------------------------------------

//----------------------------------------------------------------------------
// Region: secure_region [0x00, 0x7C) = 124 bytes = 992 bits = 31 words
//----------------------------------------------------------------------------
// word 0~8  [0x00:0x20] : lfsr_data0~lfsr_data8  (1st~9th words, LFSR)
// word 9~30 [0x24:0x78] : data0~data21           (remaining 22 words)
//----------------------------------------------------------------------------
typedef struct packed {
    bit [31:0]  data0;              // [0x24]
    // word 0~8: 1st~9th words, LFSR
    bit [31:0]  lfsr_data[9];         // [0x00] 1st word
   
    // word 9~30: data0~data21
    bit [31*22-1:0]  data1;              // [0x24]
} secure_region_t;                  // 124 bytes total (31 words)

//----------------------------------------------------------------------------
// Region: wr_rd_acc_dis [0x7C, 0x84) = 8 bytes = 64 bits
//----------------------------------------------------------------------------
typedef struct packed {
    bit [7:0]   wr_acc_dis;         // [0x7C] Write access disable (bit[i] -> region_res_i)
    bit [7:0]   rd_acc_dis;         // [0x80] Read access disable (bit[i] -> region_res_i)
    bit [31:0]  reserved;           // [0x84] Reserved
    bit [15:0]  reserved_1;         // Padding to align
} wr_rd_acc_dis_t;                  // 8 bytes total

//----------------------------------------------------------------------------
// Region: region_res_0 [0x84, 0x8C) = 8 bytes = 64 bits (Wafer Info Bit)
//----------------------------------------------------------------------------
typedef struct packed {
    bit [15:0]  wafer_id;           // [0x84] Wafer ID
    bit [7:0]   wafer_x;            // [0x86] Wafer X coordinate
    bit [7:0]   wafer_y;            // [0x87] Wafer Y coordinate
    bit [15:0]  lot_id_lo;          // [0x88] Lot ID low
    bit [15:0]  lot_id_hi;          // [0x8A] Lot ID high
} region_res_0_t;                   // 8 bytes total

//----------------------------------------------------------------------------
// Region: region_res_1 [0x8C, 0x90) = 4 bytes = 32 bits (Device ID Bit)
//----------------------------------------------------------------------------
typedef struct packed {
    bit [15:0]  device_id_lo;       // [0x8C] Device ID low
    bit [15:0]  device_id_hi;       // [0x8E] Device ID high
} region_res_1_t;                   // 4 bytes total

//----------------------------------------------------------------------------
// Region: region_res_2 [0x90, 0xA0) = 16 bytes = 128 bits (Secure Debug Lock Bit)
//----------------------------------------------------------------------------
typedef struct packed {
    bit         jtag_disable;       // [0x90:0] JTAG disable
    bit         debug_enable;       // [0x90:1] Debug enable
    bit         secure_boot;        // [0x90:2] Secure boot flag
    bit [4:0]   reserved_0;         // [0x90:7:3]
    bit [7:0]   debug_auth_key;     // [0x91] Debug authentication key
    bit [111:0] reserved_1;         // [0x92:0x9F] Reserved (14 bytes)
} region_res_2_t;                   // 16 bytes total

//----------------------------------------------------------------------------
// Region: region_res_3 [0xA0, 0xA4) = 4 bytes = 32 bits (Boot CFG Bit)
//----------------------------------------------------------------------------
typedef struct packed {
    bit [2:0]   boot_mode;          // [0xA0:2:0] Boot mode selection
    bit         boot_from_nand;     // [0xA0:3] Boot from NAND
    bit         boot_from_nor;      // [0xA0:4] Boot from NOR
    bit         boot_from_emmc;     // [0xA0:5] Boot from eMMC
    bit         boot_from_sd;       // [0xA0:6] Boot from SD
    bit         boot_from_spi;      // [0xA0:7] Boot from SPI
    bit [7:0]   boot_delay;         // [0xA1] Boot delay config
    bit [15:0]  reserved;           // [0xA2] Reserved
} region_res_3_t;                   // 4 bytes total

//----------------------------------------------------------------------------
// Region: region_res_4 [0xA4, 0xAC) = 8 bytes = 64 bits (Feature CFG Bit)
//----------------------------------------------------------------------------
typedef struct packed {
    bit         crypto_enable;      // [0xA4:0] Crypto engine enable
    bit         dma_enable;         // [0xA4:1] DMA enable
    bit         usb_enable;         // [0xA4:2] USB enable
    bit         ethernet_enable;    // [0xA4:3] Ethernet enable
    bit         wifi_enable;        // [0xA4:4] WiFi enable
    bit         bluetooth_enable;   // [0xA4:5] Bluetooth enable
    bit         gpu_enable;         // [0xA4:6] GPU enable
    bit         npu_enable;         // [0xA4:7] NPU enable
    bit [55:0]  reserved;           // [0xA5:0xAB] Reserved (7 bytes)
} region_res_4_t;                   // 8 bytes total

//----------------------------------------------------------------------------
// Region: region_res_5 [0xAC, 0xB8) = 12 bytes = 96 bits (Mem CFG Bit)
//----------------------------------------------------------------------------
typedef struct packed {
    bit [3:0]   sram_size;          // [0xAC:3:0] SRAM size config
    bit [3:0]   ddr_size;           // [0xAC:7:4] DDR size config
    bit [7:0]   ddr_type;           // [0xAD] DDR type
    bit [15:0]  mem_timing;         // [0xAE] Memory timing
    bit [31:0]  mem_base_addr;      // [0xB0] Memory base address
    bit [31:0]  mem_size_limit;     // [0xB4] Memory size limit
} region_res_5_t;                   // 12 bytes total

//----------------------------------------------------------------------------
// Region: region_res_6 [0xB8, 0x13C) = 132 bytes = 1056 bits (Analog Calibration Bit)
//----------------------------------------------------------------------------
typedef struct packed {
    bit [31:0]  adc_cal_data;       // [0xB8] ADC calibration data
    bit [31:0]  dac_cal_data;       // [0xBC] DAC calibration data
    bit [31:0]  pll_cal_data;       // [0xC0] PLL calibration data
    bit [31:0]  temp_sensor_cal;    // [0xC4] Temperature sensor cal
    bit [31:0]  vref_cal;           // [0xC8] Voltage reference cal
    bit [31:0]  rc_osc_cal;         // [0xCC] RC oscillator cal
    bit [31:0]  reserved_0;         // [0xD0]
    bit [31:0]  reserved_1;         // [0xD4]
    bit [31:0]  reserved_2;         // [0xD8]
    bit [31:0]  reserved_3;         // [0xDC]
    bit [31:0]  reserved_4;         // [0xE0]
    bit [31:0]  reserved_5;         // [0xE4]
    bit [31:0]  reserved_6;         // [0xE8]
    bit [31:0]  reserved_7;         // [0xEC]
    bit [31:0]  reserved_8;         // [0xF0]
    bit [31:0]  reserved_9;         // [0xF4]
    bit [31:0]  reserved_10;        // [0xF8]
    bit [31:0]  reserved_11;        // [0xFC]
    bit [31:0]  reserved_12;        // [0x100]
    bit [31:0]  reserved_13;        // [0x104]
    bit [31:0]  reserved_14;        // [0x108]
    bit [31:0]  reserved_15;        // [0x10C]
    bit [31:0]  reserved_16;        // [0x110]
    bit [31:0]  reserved_17;        // [0x114]
    bit [31:0]  reserved_18;        // [0x118]
    bit [31:0]  reserved_19;        // [0x11C]
    bit [31:0]  reserved_20;        // [0x120]
    bit [31:0]  reserved_21;        // [0x124]
    bit [31:0]  reserved_22;        // [0x128]
    bit [31:0]  reserved_23;        // [0x12C]
    bit [31:0]  reserved_24;        // [0x130]
    bit [31:0]  reserved_25;        // [0x134]
    bit [31:0]  reserved_26;        // [0x138]
} region_res_6_t;                   // 132 bytes total

//----------------------------------------------------------------------------
// Region: region_res_7 [0x13C, 0x200) = 196 bytes = 1568 bits (ROM Patch Bit)
//----------------------------------------------------------------------------
// Structure:
//   ROM PATCH HIT   : 32 bits          [0x13C:0x13F]
//   ROM PATCH ADDR  : 32 x 16 bits     [0x140:0x17F]  (addr0 ~ addr31)
//   ROM PATCH DATA  : 32 x 32 bits     [0x180:0x1FF]  (data0 ~ data31)
//----------------------------------------------------------------------------
typedef struct packed {
    bit [31:0]        rom_patch_hit;         // [0x13C] 32-bit hit flags
    bit [31:0] [15:0] rom_patch_addr;        // [0x140] 32 addr x 16bit
    bit [31:0] [31:0] rom_patch_data;        // [0x180] 32 data x 32bit
} region_res_7_t;                            // 196 bytes total

//----------------------------------------------------------------------------
// Top-level eFuse data structure: 512 bytes = 4096 bits
//----------------------------------------------------------------------------
typedef struct packed {
    secure_region_t     secure_region;      // [0x00:0x7B]   124 bytes
    wr_rd_acc_dis_t     wr_rd_acc_dis;      // [0x7C:0x83]   8 bytes
    region_res_0_t      region_res_0;       // [0x84:0x8B]   8 bytes
    region_res_1_t      region_res_1;       // [0x8C:0x8F]   4 bytes
    region_res_2_t      region_res_2;       // [0x90:0x9F]   16 bytes
    region_res_3_t      region_res_3;       // [0xA0:0xA3]   4 bytes
    region_res_4_t      region_res_4;       // [0xA4:0xAB]   8 bytes
    region_res_5_t      region_res_5;       // [0xAC:0xB7]   12 bytes
    region_res_6_t      region_res_6;       // [0xB8:0x13B]  132 bytes
    region_res_7_t      region_res_7;       // [0x13C:0x1FF] 196 bytes
} efuse_data_t;

// Compile-time size check
initial begin
    // Use $bits() to verify packed struct size
    // $bits(efuse_data_t) should equal 4096 (512 bytes * 8)
end
