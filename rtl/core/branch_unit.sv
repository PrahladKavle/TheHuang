// Calculates where a warp executes next

// Combinational next-PC calculation. Commit next_pc only on accepted issue.
module branch_unit #(
    parameter integer LANES=8
) (
    input wire [31:0] pc,
    // Already sign-extended by immediate_generator; measured in instructions.
    input wire [31:0] immediate,
    input wire branch,
    input wire branch_any,
    input wire [LANES-1:0] active_mask,
    output wire branch_taken,
    output wire [31:0] sequential_pc,
    output wire [31:0] branch_target,
    output wire [31:0] next_pc
);
    assign sequential_pc=pc+32'd4;
    assign branch_target=sequential_pc+(immediate << 2);
    assign branch_taken=branch | (branch_any & (|active_mask));
    assign next_pc=branch_taken ? branch_target : sequential_pc;
endmodule
