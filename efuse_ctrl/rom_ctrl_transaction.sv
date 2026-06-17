class rom_ctrl_transaction extends uvm_sequence_item;

    // Request signals
    rand rom_ctrl_addr_t rom_ctrl_addr;
    rand bit             rom_ctrl_addr_vld;

    // Response signals
    rom_ctrl_hit_t  rom_patch_hit;
    rom_ctrl_data_t rom_patch_data;
    bit             rom_patch_data_vld;

    // Timing control
    rand int addr_vld_delay;     // Delay before asserting addr_vld

    constraint c_addr_vld_delay {
        addr_vld_delay >= 0;
        addr_vld_delay <= 10;
    }

    `uvm_object_utils_begin(rom_ctrl_transaction)
        `uvm_field_int(rom_ctrl_addr,        UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(rom_ctrl_addr_vld,    UVM_ALL_ON)
        `uvm_field_int(rom_patch_hit,        UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(rom_patch_data,       UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(rom_patch_data_vld,   UVM_ALL_ON)
        `uvm_field_int(addr_vld_delay,       UVM_ALL_ON | UVM_NOPACK)
    `uvm_object_utils_end

    function new(string name = "rom_ctrl_transaction");
        super.new(name);
    endfunction

    virtual function string convert2string();
        string s;
        s = super.convert2string();
        s = {s, $sformatf("\n rom_ctrl_addr      = 0x%08x", rom_ctrl_addr)};
        s = {s, $sformatf("\n rom_ctrl_addr_vld  = %0b", rom_ctrl_addr_vld)};
        s = {s, $sformatf("\n rom_patch_hit      = 0x%1x", rom_patch_hit)};
        s = {s, $sformatf("\n rom_patch_data     = 0x%032x", rom_patch_data)};
        s = {s, $sformatf("\n rom_patch_data_vld = %0b", rom_patch_data_vld)};
        return s;
    endfunction

endclass
