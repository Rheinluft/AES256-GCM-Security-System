// ---------------------------------------------------------------------------
// Collects m_axis payload (90 beats per committed packet) and every err_valid
// strobe from the error detector.
// ---------------------------------------------------------------------------

class rx_out_item extends uvm_object;
  `uvm_object_utils(rx_out_item)
  byte unsigned plain[];   // PAYLOAD_BYTES
  bit           saw_tlast;
  function new(string name = "rx_out_item");
    super.new(name);
  endfunction
endclass


class rx_err_item extends uvm_object;
  `uvm_object_utils(rx_err_item)
  logic [4:0]   flags;
  logic [2:0]   code;
  logic [15:0]  packet_index;
  logic [31:0]  session_id;
  logic [31:0]  frame_id;
  logic [191:0] record;
  time          at;
  function new(string name = "rx_err_item");
    super.new(name);
  endfunction
  function string convert2string();
    return $sformatf("flags=%b code=%0d pkt=%0d session=%08h frame=%08h",
                     flags, code, packet_index, session_id, frame_id);
  endfunction
endclass


class rx_out_monitor extends uvm_component;
  `uvm_component_utils(rx_out_monitor)

  virtual rx_if vif;
  uvm_analysis_port #(rx_out_item) ap;
  uvm_analysis_port #(rx_err_item) err_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap     = new("ap", this);
    err_ap = new("err_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual rx_if)::get(this, "", "vif", vif))
      `uvm_fatal("OMON", "virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      collect_payload();
      collect_errors();
    join
  endtask

  task collect_payload();
    byte unsigned beat_buf[];
    int unsigned  beat;
    bit           tlast_seen;
    beat_buf = new[PAYLOAD_BYTES];
    beat = 0;
    tlast_seen = 1'b0;
    forever begin
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1) begin
        beat = 0;
        continue;
      end
      if (vif.m_axis_tvalid === 1'b1 && vif.m_axis_tready === 1'b1) begin
        for (int lane = 0; lane < 16; lane++)
          beat_buf[beat * 16 + lane] = vif.m_axis_tdata[lane*8 +: 8];
        if (vif.m_axis_tlast === 1'b1) tlast_seen = 1'b1;
        beat++;
        if (beat == PAYLOAD_WORDS) begin
          rx_out_item o = rx_out_item::type_id::create("out");
          o.plain = new[PAYLOAD_BYTES];
          foreach (o.plain[b]) o.plain[b] = beat_buf[b];
          o.saw_tlast = tlast_seen;
          ap.write(o);
          beat = 0;
          tlast_seen = 1'b0;
        end
      end
    end
  endtask

  task collect_errors();
    forever begin
      @(posedge vif.aclk);
      if (vif.aresetn === 1'b1 && vif.err_valid === 1'b1) begin
        rx_err_item e = rx_err_item::type_id::create("err");
        e.flags        = vif.err_flags;
        e.code         = vif.err_code;
        e.record       = vif.err_record;
        // err_record layout: {time,frame,session,index,aux,epoch,info,0,code,flags}
        e.frame_id     = vif.err_record[159:128];
        e.session_id   = vif.err_record[127:96];
        e.packet_index = vif.err_record[95:80];
        e.at           = $time;
        `uvm_info("OMON", $sformatf("ERROR %s", e.convert2string()), UVM_LOW)
        err_ap.write(e);
      end
    end
  endtask

endclass
