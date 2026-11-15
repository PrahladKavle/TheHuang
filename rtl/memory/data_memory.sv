// Single-port word RAM with one registered response at a time.
// Byte-addressed; no memory-array reset, so unwritten words are undefined.
module data_memory #(
    parameter integer DEPTH=16384,
    parameter INIT_FILE=""
) (
    input wire clk, reset,
    input wire memory_request_valid,
    output wire memory_request_ready,
    input wire [31:0] memory_address, memory_write_data,
    input wire memory_store,
    output wire memory_response_valid,
    input wire memory_response_ready,
    output reg [31:0] memory_read_data,
    output reg memory_error
);
    reg [31:0] memory [0:DEPTH-1];
    reg response_pending;
    wire address_valid=(memory_address[1:0]==0) && ((memory_address >> 2)<DEPTH);
    initial begin
        if(INIT_FILE!="") $readmemh(INIT_FILE,memory);
    end
    assign memory_request_ready=!reset && !response_pending;
    assign memory_response_valid=!reset && response_pending;
    always @(posedge clk) begin
        if(reset) begin
            response_pending<=0;
            memory_read_data<=0;
            memory_error<=0;
        end else if(memory_request_valid && memory_request_ready) begin
            response_pending<=1;
            memory_error<=!address_valid;
            memory_read_data<=0;
            if(address_valid) begin
                if(memory_store) memory[memory_address >> 2]<=memory_write_data;
                else memory_read_data<=memory[memory_address >> 2];
            end
        end else if(memory_response_valid && memory_response_ready)
            response_pending<=0;
    end
endmodule
