// Byte-addressed asynchronous ROM; aligned, in-range addresses only.
// INIT_FILE contains one 32-bit hexadecimal instruction per word.
module instruction_memory #(
    parameter integer DEPTH=16384,
    parameter integer ADDR_WIDTH=(DEPTH>1)?$clog2(DEPTH):1,
    parameter INIT_FILE=""
) (
    input wire [31:0] addr,
    output wire [31:0] instruction,
    output wire instruction_valid
);
    reg [31:0] memory [0:DEPTH-1];
    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, memory);
    end
    assign instruction_valid=(addr[1:0]==2'b00) && ((addr >> 2)<DEPTH);
    assign instruction=instruction_valid ? memory[addr >> 2] : 32'd0;
endmodule
