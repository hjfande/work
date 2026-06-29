class rom_ctrl_driver extends uvm_driver #(rom_ctrl_transaction);

    `uvm_component_utils(rom_ctrl_driver)

    virtual rom_ctrl_if vif;
    rom_ctrl_config cfg;

    function new(string name = "rom_ctrl_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual rom_ctrl_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal(get_type_name(), "Failed to get virtual interface from config DB")
        end
        if (!uvm_config_db#(rom_ctrl_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info(get_type_name(), "No rom_ctrl_config found in config DB, using default", UVM_MEDIUM)
            cfg = rom_ctrl_config::type_id::create("cfg");
        end
    endfunction

    virtual task reset_phase(uvm_phase phase);
        super.reset_phase(phase);
        phase.raise_objection(this);
        `uvm_info(get_type_name(), "Driving reset values to interface", UVM_MEDIUM)
        vif.drv_cb.rom_ctrl_addr     <= '0;
        vif.drv_cb.rom_ctrl_addr_vld <= '0;
        phase.drop_objection(this);
    endtask

    virtual task run_phase(uvm_phase phase);
        rom_ctrl_transaction rsp;
        forever begin
            seq_item_port.get_next_item(req);
            drive_item(req);
            $cast(rsp, req.clone());
            rsp.set_id_info(req);
            seq_item_port.item_done(rsp);
        end
    endtask

    // Align a byte address to the group size implied by patch_cfg.valid_data_width.
    // 128bit -> 16B (4 words), 64bit -> 8B (2 words), 32bit -> 4B (1 word).
    function rom_ctrl_addr_t align_addr(rom_ctrl_addr_t addr);
        int valid_data_width = (cfg.patch_cfg != null) ? cfg.patch_cfg.valid_data_width : ROM_CTRL_DATA_WIDTH;
        case (valid_data_width)
            128:     align_addr = addr & ~rom_ctrl_addr_t'('hF);  // 16-byte aligned
            64:      align_addr = addr & ~rom_ctrl_addr_t'('h7);  // 8-byte aligned
            default: align_addr = addr & ~rom_ctrl_addr_t'('h3);  // 4-byte (word) aligned
        endcase
    endfunction

    virtual task drive_item(rom_ctrl_transaction tr);
        rom_ctrl_addr_t driven_addr;

        // Wait for reset release
        @(vif.drv_cb);
        if (!vif.rom_ctrl_rst_n) begin
            @(posedge vif.rom_ctrl_rst_n);
            @(vif.drv_cb);
        end

        // Apply delay before driving
        repeat (tr.addr_vld_delay) @(vif.drv_cb);

        // Align the address to the valid_data_width group before driving
        driven_addr = align_addr(tr.rom_ctrl_addr);
        if (driven_addr !== tr.rom_ctrl_addr) begin
            `uvm_info(get_type_name(), $sformatf(
              "Aligned addr 0x%08x -> 0x%08x (valid_data_width=%0d)",
              tr.rom_ctrl_addr, driven_addr,
              (cfg.patch_cfg != null) ? cfg.patch_cfg.valid_data_width : ROM_CTRL_DATA_WIDTH
            ), UVM_HIGH)
        end

        // Drive address and assert valid for one cycle only
        vif.drv_cb.rom_ctrl_addr     <= driven_addr;
        vif.drv_cb.rom_ctrl_addr_vld <= 1'b1;
        @(vif.drv_cb);

        // Deassert addr_vld after one cycle, keep addr for reference
        vif.drv_cb.rom_ctrl_addr_vld <= 1'b0;

        // Wait (back_pipe + front_pipe) cycles before sampling response
        repeat (cfg.back_pipe + cfg.front_pipe) @(vif.drv_cb);

        // Check response valid
        if (!vif.drv_cb.rom_patch_data_vld) begin
            `uvm_error(get_type_name(), $sformatf(
              "rom_patch_data_vld is not asserted after %0d cycles (back_pipe=%0d front_pipe=%0d)",
              cfg.back_pipe + cfg.front_pipe, cfg.back_pipe, cfg.front_pipe
            ))
        end

        // Capture response
        tr.rom_patch_hit      = vif.drv_cb.rom_patch_hit;
        tr.rom_patch_data     = vif.drv_cb.rom_patch_data;
        tr.rom_patch_data_vld = vif.drv_cb.rom_patch_data_vld;

        // Clear addr
        vif.drv_cb.rom_ctrl_addr <= '0;

        `uvm_info(get_type_name(), $sformatf("Driven item:\n%s", tr.convert2string()), UVM_MEDIUM)
    endtask

endclass
