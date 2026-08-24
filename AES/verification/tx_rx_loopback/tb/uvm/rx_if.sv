`timescale 1ns/1ps

// All DUT pins in one interface.  The doc (section 6) notes every signal the
// verification needs is exposed on the wrapper boundary, so no hierarchical
// references into the core are required.
interface rx_if (input logic aclk);

  logic         aresetn;

  // key / control
  logic         sw3_decrypt;
  logic [31:0]  session_id;
  logic [255:0] session_key;
  logic         session_key_valid;
  logic         key_commit;
  logic         key_clear;
  logic [15:0]  key_epoch;

  // slave stream (stimulus)
  logic [127:0] s_axis_tdata;
  logic [15:0]  s_axis_tkeep;
  logic         s_axis_tvalid;
  logic         s_axis_tready;
  logic         s_axis_tlast;

  // master stream (recovered plaintext)
  logic [127:0] m_axis_tdata;
  logic [15:0]  m_axis_tkeep;
  logic         m_axis_tvalid;
  logic         m_axis_tready;
  logic         m_axis_tlast;

  // status
  logic [31:0]  frame_status;
  logic         key_ready;
  logic         busy;

  // error detector
  logic [31:0]  error_control;
  logic [31:0]  error_status;
  logic         error_irq;
  logic         err_valid;
  logic [4:0]   err_flags;
  logic [2:0]   err_code;
  logic [4:0]   err_sticky;
  logic [191:0] err_record;

endinterface
