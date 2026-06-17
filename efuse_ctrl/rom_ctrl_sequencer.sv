class rom_ctrl_sequencer extends uvm_sequencer #(rom_ctrl_transaction);

    `uvm_component_utils(rom_ctrl_sequencer)

    function new(string name = "rom_ctrl_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass
