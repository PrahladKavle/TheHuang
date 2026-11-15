// Per-warp context. Event masks allow completions for multiple warps.
module warp_state #(
    parameter integer WARPS=4,
    parameter integer LANES=8,
    parameter integer WARP_ID_WIDTH=(WARPS>1)?$clog2(WARPS):1
) (
    input wire clk, reset,
    input wire launch_valid,
    input wire [WARP_ID_WIDTH-1:0] launch_warp_id,
    input wire [31:0] launch_pc,
    input wire [LANES-1:0] launch_mask,
    // Assert only when an instruction is actually accepted.
    input wire issue_accept,
    input wire [WARP_ID_WIDTH-1:0] issue_warp_id,
    input wire [31:0] issue_next_pc,
    input wire mask_write_enable,
    input wire [LANES-1:0] issue_next_mask,
    input wire [WARPS-1:0] memory_wait_set, memory_wait_clear,
    input wire [WARPS-1:0] barrier_wait_set, barrier_wait_clear,
    input wire [WARPS-1:0] finish_mask,
    output reg [31:0] pc [0:WARPS-1],
    output reg [LANES-1:0] active_mask [0:WARPS-1],
    output reg [WARPS-1:0] running, memory_wait, barrier_wait,
    output wire [WARPS-1:0] ready_mask
);
    // Reset suppresses selection immediately; state resets on the clock edge.
    assign ready_mask = running & ~memory_wait & ~barrier_wait & {WARPS{!reset}};
    integer w;
    always @(posedge clk) begin
        for (w=0; w<WARPS; w=w+1) begin
            // Priority: reset > finish > launch > normal updates.
            if (reset) begin
                pc[w] <= 0;
                active_mask[w] <= 0;
                running[w] <= 0;
                memory_wait[w] <= 0;
                barrier_wait[w] <= 0;
            end else if (finish_mask[w]) begin
                running[w] <= 0;
                active_mask[w] <= 0;
                memory_wait[w] <= 0;
                barrier_wait[w] <= 0;
            end else if (launch_valid && launch_warp_id == w) begin
                pc[w] <= launch_pc;
                active_mask[w] <= launch_mask;
                running[w] <= 1;
                memory_wait[w] <= 0;
                barrier_wait[w] <= 0;
            end else if (running[w]) begin
                // Set wins over clear: a newly issued wait remains pending.
                memory_wait[w] <= (memory_wait[w] & ~memory_wait_clear[w]) | memory_wait_set[w];
                barrier_wait[w] <= (barrier_wait[w] & ~barrier_wait_clear[w]) | barrier_wait_set[w];
                if (issue_accept && issue_warp_id == w && ready_mask[w]) begin
                    pc[w] <= issue_next_pc;
                    if (mask_write_enable) active_mask[w] <= issue_next_mask;
                end
            end
        end
    end
endmodule
