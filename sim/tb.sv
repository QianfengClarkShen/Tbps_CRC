`timescale 1ps / 1ps
module tb #(
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
    parameter string CRC_NAME = "crc32",
    parameter int CRC_WIDTH = 32,
    // CRC polynomial in hexadecimal format
    parameter longint CRC_POLY = 32'h04c11db7,
    parameter longint INIT = 32'hffffffff,
    parameter longint XOR_OUT = 32'hffffffff,
    parameter int REFIN = 0,
    parameter int REFOUT = 0
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
    // AXIS output CRC value
    output logic [CRC_WIDTH-1:0] o_crc_axis_tdata,
    // AXIS output valid strobe (asserted when o_crc_axis_tdata is valid)
    output logic o_crc_axis_tvalid
);
    logic [CRC_WIDTH-1:0] crc_init_val;
    logic [CRC_WIDTH-1:0] xor_out;
    logic ref_in;
    logic ref_out;

    assign crc_init_val = ref_in ? {<<{INIT[CRC_WIDTH-1:0]}} : INIT[CRC_WIDTH-1:0];
    assign xor_out = ref_out? {<<{XOR_OUT[CRC_WIDTH-1:0]}} : XOR_OUT[CRC_WIDTH-1:0];
    assign ref_in = REFIN[0];
    assign ref_out = REFOUT[0];

    tbps_crc_axis #(
        .DWIDTH(DWIDTH),
        .PIPE_LVL(PIPE_LVL),
        .REV_PIPE_EN_ONEHOT(REV_PIPE_EN_ONEHOT),
        .CRC_WIDTH(CRC_WIDTH),
        .CRC_POLY(CRC_POLY[CRC_WIDTH-1:0])
    ) dut (.*);
endmodule