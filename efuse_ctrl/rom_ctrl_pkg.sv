`ifndef ROM_CTRL_PKG_SV
`define ROM_CTRL_PKG_SV

package rom_ctrl_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    //============================================================================
    // Parameters
    //============================================================================
    parameter int ROM_CTRL_ADDR_WIDTH = 32;
    parameter int ROM_CTRL_VALID_ADDR_WIDTH = 18;  // 256KB ROM patch space
    parameter int ROM_CTRL_HIT_WIDTH  = 4;
    parameter int ROM_CTRL_DATA_WIDTH = 128;  // 4*32

    //============================================================================
    // Typedefs
    //============================================================================
    typedef logic [ROM_CTRL_ADDR_WIDTH-1:0] rom_ctrl_addr_t;
    typedef logic [ROM_CTRL_HIT_WIDTH-1:0]  rom_ctrl_hit_t;
    typedef logic [ROM_CTRL_DATA_WIDTH-1:0] rom_ctrl_data_t;

    //============================================================================
    // Configuration Object
    //============================================================================
    class rom_ctrl_config extends uvm_object;

        `uvm_object_utils(rom_ctrl_config)

        // Agent mode
        uvm_active_passive_enum is_active = UVM_ACTIVE;

        // Enable/disable checks and coverage
        bit has_checks   = 1'b1;
        bit has_coverage = 1'b1;

        // Timing configuration
        int min_addr_vld_delay   = 0;
        int max_addr_vld_delay   = 10;
        int min_addr_hold_cycles = 1;
        int max_addr_hold_cycles = 3;

        // Pipeline delays
        int front_pipe = `EFUSE_CTRL_ROM_PATCH_FRONT_PIPE;  // additional cycles before sampling response
        int back_pipe  = `EFUSE_CTRL_ROM_PATCH_BACK_PIPE;   // base cycles after addr_vld before sampling response

        function new(string name = "rom_ctrl_config");
            super.new(name);
        endfunction

        virtual function string convert2string();
            string s;
            s = $sformatf("is_active=%s, has_checks=%0b, has_coverage=%0b, front_pipe=%0d, back_pipe=%0d",
                          is_active.name(), has_checks, has_coverage, front_pipe, back_pipe);
            return s;
        endfunction

    endclass

    //============================================================================
    // ROM Patch Configuration
    //============================================================================
    `include "rom_patch_cfg.sv"

    //============================================================================
    // Agent Components (include order matters!)
    //============================================================================
    `include "rom_ctrl_transaction.sv"
    `include "rom_ctrl_sequencer.sv"
    `include "rom_ctrl_driver.sv"
    `include "rom_ctrl_monitor.sv"
    `include "rom_ctrl_agent.sv"
    `include "rom_ctrl_sequence.sv"

endpackage : rom_ctrl_pkg

`endif // ROM_CTRL_PKG_SV
