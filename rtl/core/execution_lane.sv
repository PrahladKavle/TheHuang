// One physical lane. Control and warp IDs are supplied by the shared core.
module execution_lane #(
    parameter integer WARPS = 4,
    parameter integer WARP_ID_WIDTH = (WARPS > 1) ? $clog2(WARPS) : 1
) (
    input wire clk,
    input wire [WARP_ID_WIDTH-1:0] read_warp_id, write_warp_id,
    input wire [3:0] rs1, rs2, rd,
    input wire [3:0] alu_ctrl,
    input wire write_enable, lane_active,
    input wire external_writeback_select,
    input wire [31:0] external_writeback_data,
    output wire [31:0] read_data1, read_data2,
    output wire [31:0] alu_result,
    output wire zero
);
    wire [31:0] writeback_data = external_writeback_select
                                ? external_writeback_data : alu_result;
    // For delayed loads, lane_active must carry the original request's
    // eligibility, rather than the currently scheduled warp's active mask.
    wire commit_enable = write_enable && lane_active;

    register_file #(.WARPS(WARPS), .WARP_ID_WIDTH(WARP_ID_WIDTH)) registers (
        .clk(clk), .rs1(rs1), .rs2(rs2), .ws(rd),
        .w_data(writeback_data), .w_en(commit_enable),
        .rs1_data(read_data1), .rs2_data(read_data2),
        .read_warp_id(read_warp_id), .write_warp_id(write_warp_id)
    );
    alu arithmetic (
        .a(read_data1), .b(read_data2), .ctrl(alu_ctrl),
        .result(alu_result), .zero(zero)
    );
endmodule
