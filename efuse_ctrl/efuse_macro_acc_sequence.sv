//============================================================================
// efuse_macro_acc_sequence
//   - Inherits from svt_apb_master_base_sequence
//   - Uses base class req/rsp handles (svt_apb_transaction)
//   - APB read/write access to eFuse macro regions
//   - Region-based address constraints
//   - Responses collected after all transactions are sent
//============================================================================

//----------------------------------------------------------------------------
// eFuse Region Definitions (byte address range, based on gen_preload.py)
//----------------------------------------------------------------------------
typedef enum {
  EFUSE_SECURE_REGION,     // [0x00,  0x7C)  124B
  EFUSE_WR_RD_ACC_DIS,     // [0x7C,  0x84)  8B
  EFUSE_REGION_RES_0,      // [0x84,  0x8C)  8B   Wafer Info
  EFUSE_REGION_RES_1,      // [0x8C,  0x90)  4B   Device ID
  EFUSE_REGION_RES_2,      // [0x90,  0xA0)  16B  Secure Debug Lock
  EFUSE_REGION_RES_3,      // [0xA0,  0xA4)  4B   Boot CFG
  EFUSE_REGION_RES_4,      // [0xA4,  0xAC)  8B   Feature CFG
  EFUSE_REGION_RES_5,      // [0xAC,  0xB8)  12B  Mem CFG
  EFUSE_REGION_RES_6,      // [0xB8,  0x13C) 132B Analog Calibration
  EFUSE_REGION_RES_7       // [0x13C, 0x200) 196B ROM Patch
} efuse_region_enum;

//----------------------------------------------------------------------------
// Region address range utility
//----------------------------------------------------------------------------
class efuse_region_util;
  static function bit [31:0] get_region_start(efuse_region_enum region);
    case (region)
      EFUSE_ALL_REGION:     return 32'h00;
      EFUSE_SECURE_REGION:  return 32'h00;
      EFUSE_WR_RD_ACC_DIS:  return 32'h7C;
      EFUSE_REGION_RES_0:   return 32'h84;
      EFUSE_REGION_RES_1:   return 32'h8C;
      EFUSE_REGION_RES_2:   return 32'h90;
      EFUSE_REGION_RES_3:   return 32'hA0;
      EFUSE_REGION_RES_4:   return 32'hA4;
      EFUSE_REGION_RES_5:   return 32'hAC;
      EFUSE_REGION_RES_6:   return 32'hB8;
      EFUSE_REGION_RES_7:   return 32'h13C;
      default:              return 32'h0;
    endcase
  endfunction

  static function bit [31:0] get_region_end(efuse_region_enum region);
    case (region)
      EFUSE_ALL_REGION:     return 32'h200;
      EFUSE_SECURE_REGION:  return 32'h7C;
      EFUSE_WR_RD_ACC_DIS:  return 32'h84;
      EFUSE_REGION_RES_0:   return 32'h8C;
      EFUSE_REGION_RES_1:   return 32'h90;
      EFUSE_REGION_RES_2:   return 32'hA0;
      EFUSE_REGION_RES_3:   return 32'hA4;
      EFUSE_REGION_RES_4:   return 32'hAC;
      EFUSE_REGION_RES_5:   return 32'hB8;
      EFUSE_REGION_RES_6:   return 32'h13C;
      EFUSE_REGION_RES_7:   return 32'h200;
      default:              return 32'h0;
    endcase
  endfunction
endclass

//----------------------------------------------------------------------------
// eFuse Macro Access Sequence
//   - Inherits svt_apb_master_base_sequence, uses base class req/rsp
//----------------------------------------------------------------------------
class efuse_macro_acc_sequence extends svt_apb_master_base_sequence;

  `uvm_object_utils(efuse_macro_acc_sequence)

  // Random controls
  rand efuse_region_enum                 target_region;
  rand svt_apb_transaction::xact_type_enum xact_type;

  // Default to random read/write mix
  constraint c_xact_type {
    xact_type dist {svt_apb_transaction::READ := 50, svt_apb_transaction::WRITE := 50};
  }

  function new(string name = "efuse_macro_acc_sequence");
    super.new(name);
  endfunction

  virtual task body();
    bit [31:0]            region_start, region_end;

    region_start = efuse_region_util::get_region_start(target_region);
    region_end   = efuse_region_util::get_region_end(target_region);

    `uvm_info(get_type_name(), $sformatf(
      "Access: region=%s %s", target_region.name(), xact_type.name()
    ), UVM_HIGH)

    `uvm_do_with(req, {
      xact_type == local::xact_type;
      address inside {[local::region_start : local::region_end - 1]};
      address[1:0] == 2'b00;
    })

    `uvm_info(get_type_name(), "Sequence completed", UVM_MEDIUM)
  endtask

endclass


