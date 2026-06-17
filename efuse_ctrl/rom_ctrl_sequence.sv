class rom_ctrl_base_sequence extends uvm_sequence #(rom_ctrl_transaction);

    `uvm_object_utils(rom_ctrl_base_sequence)

    int num_transactions = 10;

    function new(string name = "rom_ctrl_base_sequence");
        super.new(name);
    endfunction

    virtual task body();
        rom_ctrl_transaction tr;
        for (int i = 0; i < num_transactions; i++) begin
            tr = rom_ctrl_transaction::type_id::create($sformatf("tr_%0d", i));
            start_item(tr);
            assert(tr.randomize() with {
                rom_ctrl_addr_vld == 1'b1;
            });
            finish_item(tr);
            `uvm_info(get_type_name(), $sformatf("Sent transaction %0d: addr=0x%08x", i, tr.rom_ctrl_addr), UVM_MEDIUM)
        end
    endtask

endclass

class rom_ctrl_addr_walking_sequence extends uvm_sequence #(rom_ctrl_transaction);

    `uvm_object_utils(rom_ctrl_addr_walking_sequence)

    int num_transactions = 16;

    function new(string name = "rom_ctrl_addr_walking_sequence");
        super.new(name);
    endfunction

    virtual task body();
        rom_ctrl_transaction tr;
        for (int i = 0; i < num_transactions; i++) begin
            tr = rom_ctrl_transaction::type_id::create($sformatf("tr_%0d", i));
            start_item(tr);
            assert(tr.randomize() with {
                rom_ctrl_addr == (32'h0000_0001 << i);
                rom_ctrl_addr_vld == 1'b1;
            });
            finish_item(tr);
        end
    endtask

endclass
