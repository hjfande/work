class rom_ctrl_monitor extends uvm_monitor;

    `uvm_component_utils(rom_ctrl_monitor)

    virtual rom_ctrl_if vif;
    uvm_analysis_port #(rom_ctrl_transaction) analysis_port;

    function new(string name = "rom_ctrl_monitor", uvm_component parent = null);
        super.new(name, parent);
        analysis_port = new("analysis_port", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual rom_ctrl_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal(get_type_name(), "Failed to get virtual interface from config DB")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        wait_for_reset();
        fork
            collect_transactions();
        join_none
    endtask

    virtual task wait_for_reset();
        @(vif.mon_cb);
        if (!vif.rom_ctrl_rst_n) begin
            @(posedge vif.rom_ctrl_rst_n);
        end
        `uvm_info(get_type_name(), "Reset released, starting monitoring", UVM_MEDIUM)
    endtask

    virtual task collect_transactions();
        rom_ctrl_transaction tr;
        bit collecting;

        forever begin
            @(vif.mon_cb);

            // Detect transaction start: addr_vld asserted
            if (vif.mon_cb.rom_ctrl_addr_vld && !collecting) begin
                collecting = 1;
                tr = rom_ctrl_transaction::type_id::create("tr");
                tr.rom_ctrl_addr     = vif.mon_cb.rom_ctrl_addr;
                tr.rom_ctrl_addr_vld = vif.mon_cb.rom_ctrl_addr_vld;
            end

            // Collect response signals during transaction
            if (collecting) begin
                if (vif.mon_cb.rom_patch_data_vld) begin
                    tr.rom_patch_hit      = vif.mon_cb.rom_patch_hit;
                    tr.rom_patch_data     = vif.mon_cb.rom_patch_data;
                    tr.rom_patch_data_vld = vif.mon_cb.rom_patch_data_vld;

                    // Transaction completes when response is received
                    collecting = 0;
                    analysis_port.write(tr);
                    `uvm_info(get_type_name(), $sformatf("Monitored transaction:\n%s", tr.convert2string()), UVM_MEDIUM)
                end
            end
        end
    endtask

endclass
