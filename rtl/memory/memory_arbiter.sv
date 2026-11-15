// Round-robin, one in-flight memory transaction. Captures a selected
// request before presenting it so payload stays stable under backpressure.
// Reset must also reset/flush the connected memory's outstanding response.
module memory_arbiter #(
    parameter integer CLIENTS=8,
    parameter integer ID_WIDTH=(CLIENTS>1)?$clog2(CLIENTS):1
) (
    input wire clk, reset,
    input wire [CLIENTS-1:0] client_request_valid,
    output reg [CLIENTS-1:0] client_request_ready,
    input wire [31:0] client_address [0:CLIENTS-1],
    input wire [31:0] client_data [0:CLIENTS-1],
    input wire [CLIENTS-1:0] client_store,
    output reg [CLIENTS-1:0] client_response_valid,
    input wire [CLIENTS-1:0] client_response_ready,
    output wire [31:0] client_response_data,
    output wire client_response_error,
    output wire memory_request_valid,
    input wire memory_request_ready,
    output reg [31:0] memory_address, memory_write_data,
    output reg memory_store,
    input wire memory_response_valid,
    output wire memory_response_ready,
    input wire [31:0] memory_read_data,
    input wire memory_error
);
    localparam [1:0] SELECT=0, REQUEST=1, RESPONSE=2;
    reg [1:0] state;
    reg [ID_WIDTH-1:0] pointer, owner;
    integer selected, candidate;
    always @(*) begin
        selected=-1;
        client_request_ready=0;
        client_response_valid=0;
        candidate=0;
        for(integer i=0;i<CLIENTS;i=i+1) begin
            candidate=pointer+i;
            if(candidate>=CLIENTS) candidate=candidate-CLIENTS;
            if(selected==-1 && client_request_valid[candidate]) selected=candidate;
        end
        if(!reset && state==SELECT && selected!=-1)
            client_request_ready[selected]=1;
        if(!reset && state==RESPONSE)
            client_response_valid[owner]=memory_response_valid;
    end
    assign memory_request_valid=(state==REQUEST) && !reset;
    assign memory_response_ready=(state==RESPONSE) && !reset && client_response_ready[owner];
    assign client_response_data=memory_read_data;
    assign client_response_error=memory_error;
    always @(posedge clk) begin
        if(reset) begin
            state<=SELECT; pointer<=0; owner<=0;
            memory_address<=0; memory_write_data<=0; memory_store<=0;
        end else case(state)
            SELECT: if(selected!=-1) begin
                owner<=selected;
                memory_address<=client_address[selected];
                memory_write_data<=client_data[selected];
                memory_store<=client_store[selected];
                state<=REQUEST;
            end
            REQUEST: if(memory_request_ready) state<=RESPONSE;
            RESPONSE: if(memory_response_valid && memory_response_ready) begin
                pointer <= (owner==CLIENTS-1) ? 0 : owner+1'b1;
                state<=SELECT;
            end
            default: state<=SELECT;
        endcase
    end
endmodule
