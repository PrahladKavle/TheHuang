// Measurement window is controlled explicitly by enable; idle cycles inside
// that window count toward total_cycles. Reset/clear take priority over enable.
// Arithmetic wraps modulo 2^64. No division or ratios are computed in hardware.
module performance_counters #(
    parameter integer LANES=8, WARPS=4
) (
    input wire clk, reset, clear, enable,
    input wire issue_accept,
    input wire [LANES-1:0] issued_active_mask,
    input wire [WARPS-1:0] running, ready_mask, memory_wait,
    output reg [63:0] total_cycles,
    output reg [63:0] instructions_issued,
    output reg [63:0] active_lane_instructions,
    output reg [63:0] scheduler_idle_cycles,
    output reg [63:0] memory_blocked_cycles
);
    reg [63:0] active_count;
    always @(*) begin
        active_count=0;
        for(integer l=0;l<LANES;l=l+1)
            active_count=active_count+issued_active_mask[l];
    end
    always @(posedge clk) begin
        if(reset || clear) begin
            total_cycles<=0;
            instructions_issued<=0;
            active_lane_instructions<=0;
            scheduler_idle_cycles<=0;
            memory_blocked_cycles<=0;
        end else if(enable) begin
            total_cycles<=total_cycles+64'd1;
            if(issue_accept) begin
                instructions_issued<=instructions_issued+64'd1;
                active_lane_instructions<=active_lane_instructions+active_count;
            end
            if((|running) && !(|(ready_mask & running)))
                scheduler_idle_cycles<=scheduler_idle_cycles+64'd1;
            if(|(memory_wait & running))
                memory_blocked_cycles<=memory_blocked_cycles+64'd1;
        end
    end
endmodule
