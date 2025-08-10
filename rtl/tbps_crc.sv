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
 USAGE GUIDE: tbps_crc
================================================================================
This module implements a high-throughput, parameterizable CRC generator with byte enable support.

Parameters:
  // Implementation parameters:
  - DWIDTH:     Data width in bits (must be a multiple of 8, e.g., 64, 512, 768)
  - PIPE_LVL:   Number of pipeline stages for fmax/area/latency tradeoff
  - REV_PIPE_EN_ONEHOT: Revert pipeline enable one-hot code, controls whether to register corresponding pipeline stages

  //CRC polynomial parameters:
  - CRC_WIDTH:  Width of the CRC output (e.g., 16 for CRC-16)
  - CRC_POLY:   CRC polynomial (hexadecimal, e.g., 16'hda5f)

Ports:

  - clk:           Clock input
  - rst:           Synchronous reset (active high)
  // Dynamic CRC control inputs:
  - crc_init_val:  Initial CRC value [CRC_WIDTH-1:0] (input)
  - xor_out:       Value to XOR with CRC result before output (input)
  - ref_in:        Reflect input bytes (bit reversal per byte, input)
  - ref_out:       Reflect output CRC (bit reversal, input)
  // Input data bus
  - din:           Input data bus [DWIDTH-1:0]
  - byteEn:        Byte enable mask [DWIDTH/8-1:0], 1=valid byte, 0=ignore
  - dlast:         Asserted on the last data beat of a packet/transaction
  - flitEn:        Data valid strobe (asserted when din/byteEn are valid)
  // Output ports:
  - crc_out:       CRC output value [CRC_WIDTH-1:0]
  - crc_out_vld:   Output valid strobe (asserted when crc_out is valid)

Usage:

  - Set crc_init_val, xor_out, ref_in, and ref_out as needed for your CRC configuration.
  - Assert flitEn when din and byteEn are valid.
  - Set dlast high on the last data beat of a packet.
  - crc_out and crc_out_vld will be asserted with the computed CRC after the last beat.
  - The module supports pipelined operation for high-throughput designs.

Example instantiation:

  tbps_crc #(
    .DWIDTH(256),
    .CRC_WIDTH(16),
    .PIPE_LVL(2),
    .CRC_POLY(16'h1021)
  ) u_tbps_crc (
    .clk(clk),
    .rst(rst),
    .crc_init_val(16'hFFFF),
    .xor_out(16'h0000),
    .ref_in(1'b1),
    .ref_out(1'b1),
    .din(din),
    .byteEn(byteEn),
    .dlast(dlast),
    .flitEn(flitEn),
    .crc_out(crc_out),
    .crc_out_vld(crc_out_vld)
  );
================================================================================
*/

`timescale 1ps / 1ps
module tbps_crc #(
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
    parameter int CRC_WIDTH = 32,
    // CRC polynomial in hexadecimal format
    parameter CRC_POLY = 32'h04C11DB7
) (
    // Clock signal
    input logic clk,
    // Synchronous reset (active high)
    input logic rst,

    // Initial value for CRC calculation
    input logic [CRC_WIDTH-1:0] crc_init_val,
    // Value to XOR with CRC result before output
    input logic [CRC_WIDTH-1:0] xor_out,
    // Reflect input bytes (bit reversal per byte)
    input logic ref_in,
    // Reflect output CRC (bit reversal)
    input logic ref_out,

    // Input data bus
    input logic [DWIDTH-1:0] din,
    // Byte enable mask (1 bit per byte, active high)
    input logic [DWIDTH/8-1:0] byteEn,
    // Indicates the last data beat in a packet/transaction
    input logic dlast,
    // Data valid strobe (asserted when din/byteEn are valid)
    input logic flitEn,
    // CRC output value
    output logic [CRC_WIDTH-1:0] crc_out,
    // CRC output valid (asserted when crc_out is valid)
    output logic crc_out_vld
);
    generate
        if (DWIDTH % 8 != 0) $fatal(0,"DWIDTH has to be a multiple of 8");
    endgenerate
    `include "tbps_crc.svh"

    localparam int DEPTH = $clog2(DWIDTH/8) == 0 ? 1 : $clog2(DWIDTH/8);

    localparam bit [CRC_WIDTH-1:0][CRC_WIDTH+DWIDTH-1:0] UNI_TABLE = gen_unified_table();
    localparam bit [CRC_WIDTH-1:0][CRC_WIDTH-1:0] CRC_TABLE = gen_crc_table(UNI_TABLE);
    localparam bit [CRC_WIDTH-1:0][DWIDTH-1:0] DATA_TABLE = gen_data_table(UNI_TABLE);
    localparam int DIV_PER_LVL = get_div_per_lvl();
    localparam bit [PIPE_LVL:0][31:0] N_TERMS = get_n_terms(DIV_PER_LVL);
    localparam bit [PIPE_LVL:0][CRC_WIDTH-1:0][(DWIDTH-1)/DIV_PER_LVL:0] BRANCH_ENABLE_TABLE = get_branch_enable_table(DATA_TABLE,DIV_PER_LVL,N_TERMS);
    localparam bit [DEPTH-1:0][CRC_WIDTH-1:0][CRC_WIDTH-1:0] REVERT_TABLE = get_revert_table();

    //input registers
    logic [DEPTH-1:0] crc_rev_en_pipe_wire;
    logic [PIPE_LVL:0][DEPTH-1:0] crc_rev_en_pipe_reg;
    logic [PIPE_LVL:0] dlast_reg;
    logic [PIPE_LVL:0] flitEn_reg;
    logic [DWIDTH-1:0] din_masked;

    //CRC signals before revert logic
    logic [DEPTH-1:0] crc_rev_en_fwd;
    logic dlast_fwd;
    logic flitEn_fwd;

    //input mask
    logic [DWIDTH-1:0] mask_in_byte;

    //internal wire
    logic [CRC_WIDTH-1:0] crc_int;

    //refin-refout convertion
    logic [DWIDTH-1:0] din_refin;
    logic [CRC_WIDTH-1:0] crc_refout;

    //pipeline logic
    logic [PIPE_LVL:0][CRC_WIDTH-1:0][(DWIDTH-1)/DIV_PER_LVL:0] data_pipe;
    logic [PIPE_LVL:0][CRC_WIDTH-1:0][(DWIDTH-1)/DIV_PER_LVL:0] data_pipe_reg;

    //crc feedback
    logic [CRC_WIDTH-1:0] crc_previous;

    //crc revert
    logic [DEPTH-1:0][CRC_WIDTH-1:0] crc_rev_wire;
    logic [DEPTH-1:0][CRC_WIDTH-1:0] crc_rev_reg;
    logic [DEPTH-1:0][DEPTH-1:0] crc_rev_en_reg;
    logic [DEPTH-1:0] crc_vld_rev_reg;

//input regs
    always_comb begin
        for (int i = 0; i < DWIDTH/8; i++)
            mask_in_byte[(i+1)*8-1-:8] = {8{byteEn[i]}};
    end

    assign din_masked = din & mask_in_byte;

    always_comb begin
    //REFIN logic
        if (ref_in)
            din_refin = {<<{din_masked}};
        else
            din_refin = {<<8{din_masked}};

    //generate the first level
        data_pipe = '0;
        for (int i = 0; i < CRC_WIDTH; i++) begin
            for (int j = 0; j < (DWIDTH-1)/DIV_PER_LVL+1; j++) begin
                for (int k = 0; k < DIV_PER_LVL && j*DIV_PER_LVL+k < DWIDTH; k++) begin
                    if (DATA_TABLE[i][j*DIV_PER_LVL+k])
                        data_pipe[0][i][j] = data_pipe[0][i][j] ^ din_refin[j*DIV_PER_LVL+k];
                end
            end
        end
    //level 2 -> aggregate data chain into 1 bit per crc bit
        for (int i = 1; i <= PIPE_LVL; i++) begin
            for (int j = 0; j < CRC_WIDTH; j++) begin
                for (int k = 0; k < (N_TERMS[i]-1)/DIV_PER_LVL+1; k++) begin
                    for (int m = k*DIV_PER_LVL; m < (k+1)*DIV_PER_LVL && m < N_TERMS[i]; m++) begin
                        if (BRANCH_ENABLE_TABLE[i-1][j][m])
                            data_pipe[i][j][k] = data_pipe[i][j][k] ^ data_pipe_reg[i-1][j][m];
                    end
                end
            end
        end
    //the last level
        crc_int = {CRC_WIDTH{1'b0}};
        for (int i = 0; i < CRC_WIDTH; i++) begin
            for (int j = 0; j < CRC_WIDTH; j++) begin
                if (CRC_TABLE[i][j])
                    crc_int[i] = crc_int[i] ^ crc_previous[j];
            end
            crc_int[i] = crc_int[i] ^ data_pipe[PIPE_LVL][i][0];
        end
    end

    if (PIPE_LVL == 0) begin
        always_comb begin
            data_pipe_reg[0] = '0;
            for (int j = 0; j < CRC_WIDTH; j++) begin
                for (int k = 0; k < N_TERMS[1]; k++) begin
                    if (BRANCH_ENABLE_TABLE[0][j][k])
                        data_pipe_reg[0][j][k] = data_pipe[0][j][k];
                end
            end
        end
    end
    else begin
        always_ff @(posedge clk) begin
            for (int i = 0; i < PIPE_LVL; i++) begin
                for (int j = 0; j < CRC_WIDTH; j++) begin
                    for (int k = 0; k < N_TERMS[i+1]; k++) begin
                        if (BRANCH_ENABLE_TABLE[i][j][k])
                            data_pipe_reg[i][j][k] <= data_pipe[i][j][k];
                    end
                end
            end
        end
    end
//input signal pipelining logic
    always_comb begin
        crc_rev_en_pipe_wire = {DEPTH{1'b0}};
        for (int i = 0; i < DWIDTH/8; i++) begin
            crc_rev_en_pipe_wire = crc_rev_en_pipe_wire + {~byteEn[i]};
        end
    end

    if (PIPE_LVL == 0) begin
        assign crc_rev_en_fwd = {<<{crc_rev_en_pipe_wire}};
        assign dlast_fwd = dlast;
        assign flitEn_fwd = flitEn;
    end
    else begin
        always_ff @(posedge clk) begin
            crc_rev_en_pipe_reg[0] <= {<<{crc_rev_en_pipe_wire}};
            dlast_reg[0] <= dlast;
            flitEn_reg[0] <= flitEn;
            for (int i = 1; i <= PIPE_LVL; i++) begin
                crc_rev_en_pipe_reg[i] <= crc_rev_en_pipe_reg[i-1];
                dlast_reg[i] <= dlast_reg[i-1];
                flitEn_reg[i] <= flitEn_reg[i-1];
            end
        end
        assign crc_rev_en_fwd = crc_rev_en_pipe_reg[PIPE_LVL-1];
        assign dlast_fwd = dlast_reg[PIPE_LVL-1];
        assign flitEn_fwd = flitEn_reg[PIPE_LVL-1];
    end

//register intermidate crc result
    always_ff @(posedge clk) begin
        if (rst)
            crc_previous <= crc_init_val;
        else if (flitEn_fwd & dlast_fwd)
            crc_previous <= crc_init_val;
        else if (flitEn_fwd)
            crc_previous <= crc_int;
    end

//do crc revert to cancel the padding zeros
    always_comb begin
        crc_rev_wire = '0;
        for (int i = 0; i < DEPTH; i++) begin
            for (int j = 0; j < CRC_WIDTH; j++) begin
                for (int k = 0; k < CRC_WIDTH; k++) begin
                    if (REVERT_TABLE[i][j][k])
                        crc_rev_wire[i][j] = crc_rev_wire[i][j] ^ crc_rev_reg[i][k];
                end
            end
        end
    end

    if (REV_PIPE_EN_ONEHOT[0]) begin
        always_ff @(posedge clk) begin
            crc_rev_reg[0] <= crc_int;
            crc_vld_rev_reg[0] <= flitEn_fwd & dlast_fwd;
            crc_rev_en_reg[0] <= crc_rev_en_fwd;
        end
    end
    else begin
        always_comb begin
            crc_rev_reg[0] = crc_int;
            crc_vld_rev_reg[0] = flitEn_fwd & dlast_fwd;
            crc_rev_en_reg[0] = crc_rev_en_fwd;
        end
    end

    for (genvar i = 1; i < DEPTH; i++) begin
        if (REV_PIPE_EN_ONEHOT[i]) begin
            always_ff @(posedge clk) begin
                crc_rev_en_reg[i] <= crc_rev_en_reg[i-1];
                if (crc_rev_en_reg[i-1][i-1])
                    crc_rev_reg[i] <= crc_rev_wire[i-1];
                else
                    crc_rev_reg[i] <= crc_rev_reg[i-1];
                crc_vld_rev_reg[i] <= crc_vld_rev_reg[i-1];
            end
        end
        else begin
            always_comb begin
                crc_rev_en_reg[i] = crc_rev_en_reg[i-1];
                if (crc_rev_en_reg[i-1][i-1])
                    crc_rev_reg[i] = crc_rev_wire[i-1];
                else
                    crc_rev_reg[i] = crc_rev_reg[i-1];
                crc_vld_rev_reg[i] = crc_vld_rev_reg[i-1];
            end
        end
    end

//refout logic
    always_comb begin
        if (crc_rev_en_reg[DEPTH-1][DEPTH-1])
            crc_refout = crc_rev_wire[DEPTH-1];
        else
            crc_refout = crc_rev_reg[DEPTH-1];

        if (ref_out)
            crc_refout = {<<{crc_refout}};
    end

//output the result
    always_ff @(posedge clk) begin
        if (rst) begin
            crc_out <= {CRC_WIDTH{1'b0}};
            crc_out_vld <= 1'b0;
        end
        else begin
            if (crc_vld_rev_reg[DEPTH-1])
                crc_out <= crc_refout ^ xor_out;
            crc_out_vld <= crc_vld_rev_reg[DEPTH-1];
        end
    end
endmodule
