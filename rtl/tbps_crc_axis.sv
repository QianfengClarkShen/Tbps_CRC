/**
Copyright (c) 2025, Qianfeng (Clark) Shen
All rights reserved.

This source code is licensed under the BSD-style license found in the
LICENSE file in the root directory of this source tree.
 * @author Qianfeng (Clark) Shen
 * @email qianfeng.shen@gmail.com
 * @create date 2022-03-18 13:57:54
 * @modify date 2025-08-02 15:45:33
 */

/*
================================================================================
 USAGE GUIDE: tbps_crc_axis
================================================================================
This module wraps a CRC generator with AXI-Stream (AXIS) bus interfaces for easy integration.

Parameters:
  // Implementation parameters:
  - DWIDTH:     Data width in bits (must be a multiple of 8, e.g., 64, 512, 768)
  - PIPE_LVL:   Number of pipeline stages for fmax/area/latency tradeoff
  - REV_PIPE_EN_ONEHOT: Revert pipeline enable one-hot code, controls whether to register corresponding revert pipeline stages
    there are log2(DWIDTH/8) revert stages, by default, all pipeline stages are registered

  // CRC polynomial parameters:
  - CRC_WIDTH:  Width of the CRC output (e.g., 16 for CRC-16)
  - CRC_POLY:   CRC polynomial (hexadecimal, e.g., 16'hda5f)

Ports:

  - clk:                Clock input
  - rst:                Synchronous reset (active high)
  // Dynamic CRC control inputs:
  - crc_init_val:  Initial CRC value [CRC_WIDTH-1:0] (input)
  - xor_out:       Value to XOR with CRC result before output (input)
  - ref_in:        Reflect input bytes (bit reversal per byte, input)
  - ref_out:       Reflect output CRC (bit reversal, input)
  // Input data bus
  - i_data_axis_tdata:  AXIS input data bus [DWIDTH-1:0]
  - i_data_axis_tkeep:  AXIS input byte enable mask [DWIDTH/8-1:0]
  - i_data_axis_tlast:  AXIS input last signal (asserted on last data beat)
  - i_data_axis_tvalid: AXIS input valid strobe
  // Output ports:
  - o_crc_axis_tdata:   AXIS output CRC value [CRC_WIDTH-1:0]
  - o_crc_axis_tvalid:  AXIS output valid strobe (asserted when o_crc_axis_tdata is valid)

Usage:

  - Set crc_init_val, xor_out, ref_in, and ref_out as needed for your CRC configuration.
  - Assert i_data_axis_tvalid when i_data_axis_tdata and i_data_axis_tkeep are valid.
  - Set i_data_axis_tlast high on the last data beat of a packet.
  - o_crc_axis_tdata and o_crc_axis_tvalid will be asserted with the computed CRC after the last beat.
  - The module supports pipelined operation for high-throughput designs.

Example instantiation:

  tbps_crc_axis #(
    .DWIDTH(256),
    .CRC_WIDTH(16),
    .PIPE_LVL(2),
    .CRC_POLY(16'h1021)
  ) u_tbps_crc_axis (
    .clk(clk),
    .rst(rst),
    .crc_init_val(16'hFFFF),
    .xor_out(16'h0000),
    .ref_in(1'b1),
    .ref_out(1'b1),
    .i_data_axis_tdata(i_data_axis_tdata),
    .i_data_axis_tkeep(i_data_axis_tkeep),
    .i_data_axis_tlast(i_data_axis_tlast),
    .i_data_axis_tvalid(i_data_axis_tvalid),
    .o_crc_axis_tdata(o_crc_axis_tdata),
    .o_crc_axis_tvalid(o_crc_axis_tvalid)
  );
================================================================================
*/

`timescale 1ps / 1ps
module tbps_crc_axis #(
    /*
        Implementation parameters:
    */
    // Data width in bits (must be a multiple of 8)
    parameter int DWIDTH = 512,
    // Number of pipeline stages (latency control)
    parameter int PIPE_LVL = 0,
    // Revert pipeline enable one-hot code, controls whether to register corresponding pipeline stages, default is all stages enabled
    parameter int REV_PIPE_EN_ONEHOT = 32'hffffffff,

    /*
        CRC polynomial parameters:
    */
    // CRC output width in bits
    parameter int CRC_WIDTH = 16,
    // CRC polynomial in hexadecimal format
    parameter CRC_POLY = 16'hda5f
) (
    // Clock signal
    input logic clk,
    // Synchronous reset (active high)
    input logic rst,
    // AXIS input data bus
    input logic [DWIDTH-1:0] i_data_axis_tdata,
    // AXIS input byte enable mask
    input logic [DWIDTH/8-1:0] i_data_axis_tkeep,
    // AXIS input last signal (asserted on last data beat)
    input logic i_data_axis_tlast,
    // AXIS input valid strobe
    input logic i_data_axis_tvalid,
    // CRC initial value
    input logic [CRC_WIDTH-1:0] crc_init_val,
    // Value to XOR with CRC result before output
    input logic [CRC_WIDTH-1:0] xor_out,
    // Reflect input bytes (bit reversal per byte)
    input logic ref_in,
    // Reflect output CRC (bit reversal)
    input logic ref_out,
    // AXIS output CRC value
    output logic [CRC_WIDTH-1:0] o_crc_axis_tdata,
    // AXIS output valid strobe (asserted when o_crc_axis_tdata is valid)
    output logic o_crc_axis_tvalid
);
    // Instantiate the CRC generator, directly connecting wrapper ports
    tbps_crc #(
        .DWIDTH(DWIDTH),
        .PIPE_LVL(PIPE_LVL),
        .REV_PIPE_EN_ONEHOT(REV_PIPE_EN_ONEHOT),
        .CRC_WIDTH(CRC_WIDTH),
        .CRC_POLY(CRC_POLY)
    ) u_tbps_crc (
        .clk(clk),
        .rst(rst),
        .crc_init_val(crc_init_val),
        .xor_out(xor_out),
        .ref_in(ref_in),
        .ref_out(ref_out),
        .din(i_data_axis_tdata),
        .byteEn(i_data_axis_tkeep),
        .dlast(i_data_axis_tlast),
        .flitEn(i_data_axis_tvalid),
        .crc_out(o_crc_axis_tdata),
        .crc_out_vld(o_crc_axis_tvalid)
    );

endmodule