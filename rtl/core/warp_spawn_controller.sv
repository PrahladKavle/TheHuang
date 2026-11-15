// Capture a validated WSPAWN and serialize child launches through one port.
module warp_spawn_controller #(
    parameter integer WARPS=4,LANES=8,
    parameter integer WARP_ID_WIDTH=(WARPS>1)?$clog2(WARPS):1
) (
    input wire clk,reset,start,
    input wire [WARPS-1:0] target_mask,
    input wire [31:0] entry_pc,
    input wire [LANES-1:0] parent_mask,
    input wire [31:0] parent_args[0:3],
    output wire busy,
    output wire launch_valid,
    input wire launch_accept,
    output reg [WARP_ID_WIDTH-1:0] launch_warp_id,
    output reg [31:0] launch_pc,
    output reg [LANES-1:0] launch_mask,
    output reg [31:0] launch_args[0:3]
);
    reg [WARPS-1:0] pending;
    integer selected;
    assign busy=|pending;
    assign launch_valid=busy && !reset;
    always @(*) begin
        selected=-1;launch_warp_id=0;
        for(integer w=0;w<WARPS;w=w+1)
            if(selected==-1 && pending[w]) begin selected=w;launch_warp_id=w;end
    end
    always @(posedge clk) begin
        if(reset) begin
            pending<=0;launch_pc<=0;launch_mask<=0;
            for(integer a=0;a<4;a=a+1)launch_args[a]<=0;
        end else if(start && !busy) begin
            pending<=target_mask;launch_pc<=entry_pc;launch_mask<=parent_mask;
            for(integer a=0;a<4;a=a+1)launch_args[a]<=parent_args[a];
        end else if(launch_valid && launch_accept) pending[launch_warp_id]<=0;
    end
endmodule
