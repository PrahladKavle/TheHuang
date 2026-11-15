module immediate_generator (
    input wire [31:0] instruction,
    input wire [1:0] immediate_mode,
    output reg [31:0] immediate
);
    always @(*) begin
        case (immediate_mode)
            2'd1: immediate={{18{instruction[13]}},instruction[13:0]};
            2'd2: immediate={18'd0,instruction[13:0]};
            // LUI repurposes rs1/rs2/imm as an 18-bit payload.
            2'd3: immediate={instruction[17:0],14'd0};
            default: immediate=0;
        endcase
    end
endmodule
