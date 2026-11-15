// Minimal GPU system: executing core, instruction ROM and shared data RAM.
// No display/host serial interface yet. Launch only inactive warps.
module gpu_top #(
    parameter integer LANES=8, WARPS=4,
    parameter integer WARP_ID_WIDTH=(WARPS>1)?$clog2(WARPS):1,
    parameter integer PROGRAM_DEPTH=256, DATA_DEPTH=16384, MASK_STACK_DEPTH=8,
    parameter PROGRAM_INIT_FILE="", DATA_INIT_FILE=""
) (
    input wire clk, reset,
    input wire perf_clear, perf_enable,
    output wire [63:0] total_cycles, instructions_issued, active_lane_instructions,
    output wire [63:0] scheduler_idle_cycles, memory_blocked_cycles,

    input wire launch_valid,
    input wire [WARP_ID_WIDTH-1:0] launch_warp_id,
    input wire [31:0] launch_pc,
    input wire [LANES-1:0] launch_mask,
    input wire [31:0] launch_args [0:3],
    output wire [WARPS-1:0] running,
    output wire busy, fault,
    output wire [31:0] fault_pc,
    input wire [WARP_ID_WIDTH-1:0] debug_warp_id,
    input wire [3:0] debug_register,
    output wire [31:0] debug_data [0:LANES-1]
);
    wire memory_request_valid, memory_request_ready, memory_store;
    wire memory_response_valid, memory_response_ready, memory_error;
    wire [31:0] memory_address, memory_write_data, memory_read_data;
    minimal_core #(.LANES(LANES),.WARPS(WARPS),.WARP_ID_WIDTH(WARP_ID_WIDTH),
        .PROGRAM_DEPTH(PROGRAM_DEPTH),.MASK_STACK_DEPTH(MASK_STACK_DEPTH),.INIT_FILE(PROGRAM_INIT_FILE)) core (
        .clk(clk),.reset(reset),.perf_clear(perf_clear),.perf_enable(perf_enable),
        .total_cycles(total_cycles),.instructions_issued(instructions_issued),
        .active_lane_instructions(active_lane_instructions),
        .scheduler_idle_cycles(scheduler_idle_cycles),.memory_blocked_cycles(memory_blocked_cycles),
        .launch_valid(launch_valid),.launch_warp_id(launch_warp_id),
        .launch_pc(launch_pc),.launch_mask(launch_mask),.launch_args(launch_args),.running(running),.busy(busy),
        .fault(fault),.fault_pc(fault_pc),.debug_warp_id(debug_warp_id),
        .debug_register(debug_register),.debug_data(debug_data),
        .memory_request_valid(memory_request_valid),.memory_request_ready(memory_request_ready),
        .memory_address(memory_address),.memory_write_data(memory_write_data),.memory_store(memory_store),
        .memory_response_valid(memory_response_valid),.memory_response_ready(memory_response_ready),
        .memory_read_data(memory_read_data),.memory_error(memory_error));
    data_memory #(.DEPTH(DATA_DEPTH),.INIT_FILE(DATA_INIT_FILE)) data_ram (
        .clk(clk),.reset(reset),
        .memory_request_valid(memory_request_valid),.memory_request_ready(memory_request_ready),
        .memory_address(memory_address),.memory_write_data(memory_write_data),.memory_store(memory_store),
        .memory_response_valid(memory_response_valid),.memory_response_ready(memory_response_ready),
        .memory_read_data(memory_read_data),.memory_error(memory_error));
endmodule
