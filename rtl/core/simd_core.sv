module simd_core #(
    parameter integer LANES = 8,
    parameter integer WARPS = 4,
    parameter integer WARP_ID_WIDTH = (WARPS > 1) ? $clog2(WARPS) : 1
) (
    input wire clk,
    input wire [WARP_ID_WIDTH-1:0] read_warp_id, write_warp_id,
    input wire [3:0] rs1, rs2, rd,
    input wire [3:0] alu_ctrl,
    input wire write_enable, 
    input wire [LANES-1:0] active_mask,
    input wire external_writeback_select,
    input wire [31:0] external_writeback_data [0:LANES-1],
    
    output wire [31:0] read_data1 [0:LANES-1],
    output wire [31:0] read_data2 [0:LANES-1],
    output wire [31:0] alu_result [0:LANES-1],
    output wire [LANES-1:0] zero
);

for (genvar lane = 0; lane < LANES; lane++) begin : lanes
    execution_lane #(
        .WARPS(WARPS),
        .WARP_ID_WIDTH(WARP_ID_WIDTH)
    ) lane_unit (
        .clk(clk),
        .read_warp_id(read_warp_id),
        .write_warp_id(write_warp_id),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .alu_ctrl(alu_ctrl),
        .write_enable(write_enable),
        .lane_active(active_mask[lane]),
        .external_writeback_select(external_writeback_select),
        .external_writeback_data(external_writeback_data[lane]),
        .read_data1(read_data1[lane]),
        .read_data2(read_data2[lane]),
        .alu_result(alu_result[lane]),
        .zero(zero[lane])
    );
end
endmodule