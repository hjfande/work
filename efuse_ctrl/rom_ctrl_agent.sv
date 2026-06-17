class rom_ctrl_agent extends uvm_agent;

    `uvm_component_utils(rom_ctrl_agent)

    rom_ctrl_config    cfg;
    rom_ctrl_sequencer sequencer;
    rom_ctrl_driver    driver;
    rom_ctrl_monitor   monitor;

    function new(string name = "rom_ctrl_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Get configuration from config DB, or create default
        if (!uvm_config_db#(rom_ctrl_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info(get_type_name(), "No config found, using default", UVM_MEDIUM)
            cfg = rom_ctrl_config::type_id::create("cfg");
        end

        // Create monitor (always present)
        monitor = rom_ctrl_monitor::type_id::create("monitor", this);

        // Create driver and sequencer only in ACTIVE mode
        if (cfg.is_active == UVM_ACTIVE) begin
            sequencer = rom_ctrl_sequencer::type_id::create("sequencer", this);
            driver    = rom_ctrl_driver::type_id::create("driver", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        if (cfg.is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass
