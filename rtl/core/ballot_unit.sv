// One bit per active lane with a nonzero predicate. Supported LANES: 1..32.
module ballot_unit #(
    parameter integer LANES=8
) (
    input wire [LANES-1:0] active_mask,
    input wire [LANES-1:0] predicates,
    output wire [31:0] vote_mask
);
    assign vote_mask=active_mask & predicates;
endmodule
