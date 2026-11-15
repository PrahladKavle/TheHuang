// Per-warp saved masks. Only accepted push/pop changes stack state.
module mask_stack #(
    parameter integer WARPS=4, LANES=8, DEPTH=8,
    parameter integer WARP_ID_WIDTH=(WARPS>1)?$clog2(WARPS):1,
    parameter integer COUNT_WIDTH=$clog2(DEPTH+1)
) (
    input wire clk, reset,
    input wire clear_valid,
    input wire [WARP_ID_WIDTH-1:0] clear_warp_id,
    input wire [WARP_ID_WIDTH-1:0] warp_id,
    input wire push, pop, commit,
    input wire [LANES-1:0] current_mask,
    output reg [LANES-1:0] restored_mask,
    output wire stack_error
);
    reg [LANES-1:0] saved [0:WARPS-1][0:DEPTH-1];
    reg [COUNT_WIDTH-1:0] count [0:WARPS-1];
    assign stack_error=(push && pop) || (push && count[warp_id]==DEPTH)
                       || (pop && count[warp_id]==0);
    always @(*) begin
        restored_mask=0;
        if(count[warp_id]!=0) restored_mask=saved[warp_id][count[warp_id]-1];
    end
    always @(posedge clk) begin
        for(integer w=0;w<WARPS;w=w+1) begin
            if(reset || (clear_valid && clear_warp_id==w)) count[w]<=0;
            else if(commit && warp_id==w && !stack_error) begin
                if(push) begin saved[w][count[w]]<=current_mask;count[w]<=count[w]+1'b1;end
                else if(pop) count[w]<=count[w]-1'b1;
            end
        end
    end
endmodule
