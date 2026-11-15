// One reusable barrier for the core's single block. Membership is snapshotted
// at first arrival; retired members stop participating. No launches mid-epoch.
module barrier_controller #(
    parameter integer WARPS=4,
    parameter integer WARP_ID_WIDTH=(WARPS>1)?$clog2(WARPS):1
) (
    input wire clk, reset,
    input wire [WARPS-1:0] running,
    input wire arrive_valid,
    input wire [WARP_ID_WIDTH-1:0] arrive_warp_id,
    output reg epoch_active,
    output wire [WARPS-1:0] wait_set,
    output wire [WARPS-1:0] wait_clear
);
    reg [WARPS-1:0] members, arrived;
    wire [WARPS-1:0] live_members=members & running;
    wire release_epoch=epoch_active && ((arrived & live_members)==live_members);
    assign wait_set=(!reset && arrive_valid) ? ({{(WARPS-1){1'b0}},1'b1} << arrive_warp_id) : {WARPS{1'b0}};
    assign wait_clear=(!reset && release_epoch) ? arrived : {WARPS{1'b0}};
    always @(posedge clk) begin
        if(reset) begin epoch_active<=0;members<=0;arrived<=0;end
        else if(release_epoch) begin epoch_active<=0;members<=0;arrived<=0;end
        else if(arrive_valid) begin
            if(!epoch_active) begin
                epoch_active<=1;members<=running;arrived<=wait_set;
            end else arrived<=arrived | wait_set;
        end
    end
endmodule
