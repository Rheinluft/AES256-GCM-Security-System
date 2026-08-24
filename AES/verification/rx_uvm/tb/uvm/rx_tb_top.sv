`timescale 1ns/1ps

module rx_tb_top;
  import uvm_pkg::*;
  import rx_uvm_pkg::*;
  `include "uvm_macros.svh"

  // 150 MHz
  localparam time CLK_PERIOD = 6.667ns;

  logic aclk = 1'b0;
  always #(CLK_PERIOD/2) aclk = ~aclk;

  rx_if vif (.aclk(aclk));

  // Doc section 7: without these overrides the 100 ms / 50 ms defaults mask
  // SESSION and TIMEOUT detection for 7.5M clocks after reset.
  axis_gcm_rx_frame_processor #(
      .RECORD_WORDS (92),
      .FRAME_PACKETS(1280),
      .CLK_HZ       (150_000_000),
      .TIMEOUT_US   (32'd200),
      .REKEY_US     (32'd100)
  ) dut (
      .aclk             (aclk),
      .aresetn          (vif.aresetn),
      .sw3_decrypt      (vif.sw3_decrypt),
      .session_id       (vif.session_id),
      .session_key      (vif.session_key),
      .session_key_valid(vif.session_key_valid),
      .key_commit       (vif.key_commit),
      .key_clear        (vif.key_clear),
      .key_epoch        (vif.key_epoch),

      .s_axis_tdata (vif.s_axis_tdata),
      .s_axis_tkeep (vif.s_axis_tkeep),
      .s_axis_tvalid(vif.s_axis_tvalid),
      .s_axis_tready(vif.s_axis_tready),
      .s_axis_tlast (vif.s_axis_tlast),

      .m_axis_tdata (vif.m_axis_tdata),
      .m_axis_tkeep (vif.m_axis_tkeep),
      .m_axis_tvalid(vif.m_axis_tvalid),
      .m_axis_tready(vif.m_axis_tready),
      .m_axis_tlast (vif.m_axis_tlast),

      .frame_status(vif.frame_status),
      .key_ready   (vif.key_ready),
      .busy        (vif.busy),

      .error_control(vif.error_control),
      .error_status (vif.error_status),
      .error_irq    (vif.error_irq),
      .err_valid    (vif.err_valid),
      .err_flags    (vif.err_flags),
      .err_code     (vif.err_code),
      .err_sticky   (vif.err_sticky),
      .err_record   (vif.err_record)
  );

  initial begin
    vif.aresetn = 1'b0;
    repeat (10) @(posedge aclk);
    vif.aresetn = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual rx_if)::set(null, "*", "vif", vif);
    run_test();
  end

endmodule
