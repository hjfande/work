class rom_ctrl_base_sequence extends uvm_sequence #(rom_ctrl_transaction);

    `uvm_object_utils(rom_ctrl_base_sequence)

    int num_transactions = 10;

    // ROM patch configuration, retrieved from config_db
    rom_patch_cfg cfg;

    function new(string name = "rom_ctrl_base_sequence");
        super.new(name);
    endfunction

    virtual task pre_body();
        super.pre_body();
        if (!uvm_config_db#(rom_patch_cfg)::get(get_sequencer(), "", "rom_patch_cfg", cfg)) begin
            `uvm_fatal(get_type_name(), "Failed to get rom_patch_cfg from config_db")
        end
    endtask

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

class rom_ctrl_addr_walking_sequence extends rom_ctrl_base_sequence;

    `uvm_object_utils(rom_ctrl_addr_walking_sequence)

    function new(string name = "rom_ctrl_addr_walking_sequence");
        super.new(name);
    endfunction

    virtual task body();
        rom_ctrl_transaction tr;
        rom_ctrl_transaction rsp;
        bit [ROM_CTRL_HIT_WIDTH-1:0]  exp_hit;
        bit [ROM_CTRL_DATA_WIDTH-1:0] exp_data;

        // Traverse addresses from rom_patch_cfg; cfg stores word addresses,
        // convert to byte addresses by shifting left 2 bits.
        for (int i = 0; i < cfg.rom_patch_addr.size(); i++) begin
            tr = rom_ctrl_transaction::type_id::create($sformatf("tr_%0d", i));
            start_item(tr);
            assert(tr.randomize() with {
                rom_ctrl_addr     == (cfg.rom_patch_addr[i] << 2);
                rom_ctrl_addr_vld == 1'b1;
            });
            finish_item(tr);
            get_response(rsp);

            cfg.get_expect(cfg.rom_patch_addr[i], exp_hit, exp_data);

            if (rsp.rom_patch_hit !== exp_hit || rsp.rom_patch_data !== exp_data) begin
                `uvm_error(get_type_name(), $sformatf(
                  "ROM patch mismatch! idx=%0d word_addr=0x%08x exp_hit=0x%1x act_hit=0x%1x exp_data=0x%032x act_data=0x%032x",
                  i, cfg.rom_patch_addr[i], exp_hit, rsp.rom_patch_hit, exp_data, rsp.rom_patch_data
                ))
            end else begin
                `uvm_info(get_type_name(), $sformatf(
                  "ROM patch match idx=%0d word_addr=0x%08x hit=0x%1x data=0x%032x",
                  i, cfg.rom_patch_addr[i], rsp.rom_patch_hit, rsp.rom_patch_data
                ), UVM_MEDIUM)
            end
        end
    endtask

endclass

//----------------------------------------------------------------------------
// Direct ROM control sequence: send one address and capture response hit/data
//----------------------------------------------------------------------------
class rom_ctrl_direct_sequence extends rom_ctrl_base_sequence;

    `uvm_object_utils_begin(rom_ctrl_direct_sequence)
        `uvm_field_int(addr,     UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(rsp_hit,  UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(rsp_data, UVM_ALL_ON | UVM_HEX)
    `uvm_object_utils_end

    // Address to be sent (set by caller)
    rom_ctrl_addr_t addr;

    // Response captured from DUT
    rom_ctrl_hit_t  rsp_hit;
    rom_ctrl_data_t rsp_data;

    function new(string name = "rom_ctrl_direct_sequence");
        super.new(name);
    endfunction

    virtual function string convert2string();
        string s;
        s = super.convert2string();
        s = {s, $sformatf("\n addr     = 0x%08x", addr)};
        s = {s, $sformatf("\n rsp_hit  = 0x%1x",  rsp_hit)};
        s = {s, $sformatf("\n rsp_data = 0x%032x", rsp_data)};
        return s;
    endfunction

    virtual task body();
        rom_ctrl_transaction tr;
        rom_ctrl_transaction rsp;

        tr = rom_ctrl_transaction::type_id::create("tr");
        start_item(tr);
        assert(tr.randomize() with {
            rom_ctrl_addr     == addr;
            rom_ctrl_addr_vld == 1'b1;
        });
        finish_item(tr);

        get_response(rsp);
        rsp_hit  = rsp.rom_patch_hit;
        rsp_data = rsp.rom_patch_data;

        `uvm_info(get_type_name(), $sformatf(
          "Direct seq response: addr=0x%08x hit=0x%1x data=0x%032x",
          addr, rsp_hit, rsp_data
        ), UVM_MEDIUM)
    endtask

endclass
