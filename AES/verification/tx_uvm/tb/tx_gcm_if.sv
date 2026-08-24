`timescale 1ns/1ps

interface tx_gcm_if(input logic aclk);
  logic         aresetn;
  logic         sw3_encrypt;
  logic [31:0]  session_id;
  logic [255:0] session_key;
  logic         session_key_valid;
  logic         key_commit;
  logic         key_clear;

  logic [127:0] s_axis_tdata;
  logic [15:0]  s_axis_tkeep;
  logic         s_axis_tvalid;
  logic         s_axis_tready;
  logic         s_axis_tuser;
  logic         s_axis_tlast;

  logic [127:0] m_axis_tdata;
  logic [15:0]  m_axis_tkeep;
  logic         m_axis_tvalid;
  logic         m_axis_tready;
  logic         m_axis_tuser;
  logic         m_axis_tlast;

  logic [127:0] m_meta_tdata;
  logic [15:0]  m_meta_tkeep;
  logic         m_meta_tvalid;
  logic         m_meta_tready;
  logic         m_meta_tlast;

  logic [31:0]  status_frame_id;
  logic [15:0]  status_packet_index;
  logic [31:0]  debug_status;
  logic         key_ready;
  logic         busy;
  logic         protocol_error;

  clocking drv_cb @(posedge aclk);
    default input #1step output #0;
    output aresetn, sw3_encrypt, session_id, session_key;
    output session_key_valid, key_commit, key_clear;
    output s_axis_tdata, s_axis_tkeep, s_axis_tvalid;
    output s_axis_tuser, s_axis_tlast;
    output m_axis_tready, m_meta_tready;
    input  s_axis_tready, key_ready, busy, protocol_error;
  endclocking

  clocking mon_cb @(posedge aclk);
    default input #1step;
    input aresetn;
    input s_axis_tdata, s_axis_tkeep, s_axis_tvalid, s_axis_tready;
    input s_axis_tuser, s_axis_tlast;
    input m_axis_tdata, m_axis_tkeep, m_axis_tvalid, m_axis_tready;
    input m_axis_tuser, m_axis_tlast;
    input m_meta_tdata, m_meta_tkeep, m_meta_tvalid, m_meta_tready;
    input m_meta_tlast;
    input status_frame_id, status_packet_index, debug_status;
    input key_ready, busy, protocol_error;
  endclocking
endinterface
