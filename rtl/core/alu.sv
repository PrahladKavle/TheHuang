module alu (
    input wire [31:0] a,
    input wire [31:0] b,
    input wire [3:0] ctrl,

    output reg [31:0] result,
    output reg zero
);
    localparam [3:0] ADD = 4'b0000, SUB = 4'b0001,
    AND = 4'b0010, OR = 4'b0011, XOR = 4'b0100, SLT = 4'b0101,
    MUL = 4'b0110, SHL = 4'b0111, SHR = 4'b1000, SEQ = 4'b1001, MIN = 4'd10, MAX = 4'd11;

    wire signed [63:0] product = $signed(a) * $signed(b);

    always @(*) begin
        case (ctrl)
            ADD:
                result = a + b;
                
            SUB:
                result = a - b;
            
            AND:
                result = a & b;
            
            OR:
                result = a | b;
        
            XOR:
                result = a ^ b;

            SLT:
                result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;

            MUL:
                result = product[47:16];

            SHL:
                result = a << b[4:0];
            
            SHR:
                result = a >> b[4:0];
            
            SEQ:
                result = (a == b) ? 32'd1 : 32'd0;

            MIN:
                result = ($signed(a) < $signed(b)) ? a : b;
            MAX:
                result = ($signed(a) > $signed(b)) ? a : b;

            default:
                result = 32'b0;
        endcase

        zero = (result == 0) ? 1'b1 : 1'b0;

        end
endmodule