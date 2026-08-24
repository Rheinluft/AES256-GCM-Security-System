`timescale 1ns/1ps

module tb_top;
  import uvm_pkg::*;
  import tx_gcm_pkg::*;

  logic aclk = 1'b0;
  always #5 aclk = ~aclk;

  tx_gcm_if vif(aclk);

  video_aes_gcm_tx_top dut (
      .aclk(vif.aclk),
      .aresetn(vif.aresetn),
      .sw3_encrypt(vif.sw3_encrypt),
      .session_id(vif.session_id),
      .session_key(vif.session_key),
      .session_key_valid(vif.session_key_valid),
      .key_commit(vif.key_commit),
      .key_clear(vif.key_clear),
      .s_axis_tdata(vif.s_axis_tdata),
      .s_axis_tkeep(vif.s_axis_tkeep),
      .s_axis_tvalid(vif.s_axis_tvalid),
      .s_axis_tready(vif.s_axis_tready),
      .s_axis_tuser(vif.s_axis_tuser),
      .s_axis_tlast(vif.s_axis_tlast),
      .m_axis_tdata(vif.m_axis_tdata),
      .m_axis_tkeep(vif.m_axis_tkeep),
      .m_axis_tvalid(vif.m_axis_tvalid),
      .m_axis_tready(vif.m_axis_tready),
      .m_axis_tuser(vif.m_axis_tuser),
      .m_axis_tlast(vif.m_axis_tlast),
      .m_meta_tdata(vif.m_meta_tdata),
      .m_meta_tkeep(vif.m_meta_tkeep),
      .m_meta_tvalid(vif.m_meta_tvalid),
      .m_meta_tready(vif.m_meta_tready),
      .m_meta_tlast(vif.m_meta_tlast),
      .status_frame_id(vif.status_frame_id),
      .status_packet_index(vif.status_packet_index),
      .debug_status(vif.debug_status),
      .key_ready(vif.key_ready),
      .busy(vif.busy),
      .protocol_error(vif.protocol_error)
  );

  initial begin
    uvm_config_db#(virtual tx_gcm_if)::set(null, "*", "vif", vif);
    run_test();
  end
endmodule
