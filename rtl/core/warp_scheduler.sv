// Round-robin selection; ready_mask is supplied by warp-state control.
module warp_scheduler #(
    parameter integer WARPS = 4,
    parameter integer WARP_ID_WIDTH = (WARPS > 1) ? $clog2(WARPS) : 1
) (
    input wire clk,
    input wire reset, // Synchronous, active high.
    input wire [WARPS-1:0] ready_mask,
    input wire issue_accept,
    output reg [WARP_ID_WIDTH-1:0] selected_warp,
    output reg issue_valid
);
    reg [WARP_ID_WIDTH-1:0] next_warp;
    integer offset;
    integer candidate;

    always @(*) begin
        selected_warp = 0;
        issue_valid = 0;
        candidate = 0;
        for (offset = 0; offset < WARPS; offset = offset + 1) begin
            candidate = next_warp + offset;
            if (candidate >= WARPS) candidate = candidate - WARPS;
            if (!reset && !issue_valid && ready_mask[candidate]) begin
                selected_warp = candidate;
                issue_valid = 1;
            end
        end
    end

    always @(posedge clk) begin
        if (reset)
            next_warp <= 0;
        else if (issue_valid && issue_accept) begin
            if (selected_warp == WARPS-1)
                next_warp <= 0;
            else
                next_warp <= selected_warp + 1'b1;
        end
    end
endmodule
