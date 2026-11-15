// Custom ISA: opcode[31:26], rd[25:22], rs1[21:18], rs2[17:14], imm[13:0].
// Special control outputs are requests; the core must gate effects on accepted issue.
module instruction_decoder (
    input wire [31:0] instruction,
    output wire [5:0] opcode,
    output wire [3:0] rd, rs1, rs2,
    output reg illegal_instruction,
    output reg register_write, use_immediate,
    output reg [3:0] alu_ctrl,
    output reg memory_read, memory_write,
    output reg branch, branch_any, warp_finish, warp_spawn, barrier, present,
    output reg mask_set, mask_push, mask_pop, mask_replace, ballot, special_read,
    output reg [1:0] immediate_mode
);
    assign opcode = instruction[31:26];
    assign rd = instruction[25:22];
    assign rs1 = instruction[21:18];
    assign rs2 = instruction[17:14];
    // immediate_mode: 0=none, 1=signed14, 2=unsigned14, 3=upper18.
    always @(*) begin
        illegal_instruction=0;
        register_write=0; use_immediate=0; alu_ctrl=0;
        memory_read=0; memory_write=0;
        branch=0; branch_any=0; warp_finish=0; warp_spawn=0;
        barrier=0; present=0; mask_set=0; mask_push=0;
        mask_pop=0; mask_replace=0; ballot=0; special_read=0;
        immediate_mode=0;
        case (opcode)
            6'd0: begin register_write=1; alu_ctrl=4'd0; end // ADD
            6'd1: begin register_write=1; alu_ctrl=4'd1; end // SUB
            6'd2: begin register_write=1; alu_ctrl=4'd2; end // AND
            6'd3: begin register_write=1; alu_ctrl=4'd3; end // OR
            6'd4: begin register_write=1; alu_ctrl=4'd4; end // XOR
            6'd5: begin register_write=1; alu_ctrl=4'd5; end // SLT
            6'd6: begin register_write=1; alu_ctrl=4'd6; end // MUL
            6'd7: begin register_write=1; alu_ctrl=4'd7; end // SHL
            6'd8: begin register_write=1; alu_ctrl=4'd8; end // SHR
            6'd9: begin register_write=1; alu_ctrl=4'd9; end // SEQ
            // Signed minimum and maximum.
            6'd10: begin register_write=1; alu_ctrl=10; end
            6'd11: begin register_write=1; alu_ctrl=11; end
            6'd12: begin register_write=1; use_immediate=1; immediate_mode=2; end
            6'd13: begin register_write=1; use_immediate=1; immediate_mode=3; end
            6'd14: begin register_write=1; special_read=1; immediate_mode=2; end
            6'd15: mask_set=1;
            6'd16: mask_push=1;
            6'd17: mask_pop=1;
            6'd18: mask_replace=1;
            6'd19: begin register_write=1; ballot=1; end
            6'd20: begin branch_any=1; immediate_mode=1; end
            6'd21: begin branch=1; immediate_mode=1; end
            6'd22: warp_finish=1;
            6'd23: begin warp_spawn=1; immediate_mode=1; end
            6'd24: barrier=1;
            6'd25: begin memory_read=1; register_write=1; use_immediate=1; immediate_mode=1; end
            6'd26: begin memory_write=1; use_immediate=1; immediate_mode=1; end
            6'd27: present=1;
            default: illegal_instruction=1;
        endcase
        // Shift instructions use an immediate shift count, not rs2.
        if (opcode==7 || opcode==8) begin use_immediate=1; immediate_mode=2; end
    end
endmodule
