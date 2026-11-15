// One outstanding transaction per physical lane. No new issue until completion.
// Request and response use valid/ready handshakes. Responses cannot arrive
// in the request-acceptance cycle: the memory system must buffer them.
module load_store_unit #(
    parameter integer WARPS=4,
    parameter integer WARP_ID_WIDTH=(WARPS>1)?$clog2(WARPS):1
) (
    input wire clk, reset,
    input wire issue_valid,
    output wire issue_ready,
    input wire lane_active, issue_store,
    input wire [31:0] base_address, offset, store_data,
    input wire [WARP_ID_WIDTH-1:0] issue_warp_id,
    input wire [3:0] issue_rd,
    output wire busy,
    output wire request_valid,
    input wire request_ready,
    output reg [31:0] request_address, request_data,
    output reg request_store,
    input wire response_valid,
    output wire response_ready,
    input wire [31:0] response_data,
    input wire response_error,
    // Completion is held until consumed, so load writeback can arbitrate.
    output wire completion_valid,
    input wire completion_ready,
    output reg completion_error, completion_write_enable,
    output reg [31:0] completion_data,
    output reg [WARP_ID_WIDTH-1:0] completion_warp_id,
    output reg [3:0] completion_rd
);
    localparam [1:0] IDLE=0, REQUEST=1, RESPONSE=2, COMPLETE=3;
    reg [1:0] state;
    wire [31:0] address=base_address+offset;
    assign issue_ready=(state==IDLE) && !reset;
    assign busy=(state!=IDLE);
    assign request_valid=(state==REQUEST) && !reset;
    assign response_ready=(state==RESPONSE) && !reset;
    assign completion_valid=(state==COMPLETE) && !reset;
    always @(posedge clk) begin
        if(reset) begin
            state<=IDLE;
            request_address<=0; request_data<=0; request_store<=0;
            completion_error<=0; completion_write_enable<=0;
            completion_data<=0; completion_warp_id<=0; completion_rd<=0;
        end else case(state)
            IDLE: if(issue_valid) begin
                completion_warp_id<=issue_warp_id;
                completion_rd<=issue_rd;
                completion_data<=0;
                completion_write_enable<=0;
                completion_error<=0;
                request_address<=address;
                request_data<=store_data;
                request_store<=issue_store;
                // Masked lanes complete locally, even for unaligned addresses.
                if(!lane_active) state<=COMPLETE;
                else if(address[1:0]!=0) begin
                    completion_error<=1;
                    state<=COMPLETE;
                end else state<=REQUEST;
            end
            REQUEST: if(request_ready) state<=RESPONSE;
            RESPONSE: if(response_valid) begin
                completion_error<=response_error;
                completion_data<=response_data;
                completion_write_enable<=!request_store && !response_error && completion_rd!=0;
                state<=COMPLETE;
            end
            COMPLETE: if(completion_ready) state<=IDLE;
            default: state<=IDLE;
        endcase
    end
endmodule
