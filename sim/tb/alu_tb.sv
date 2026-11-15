`timescale 1ns/1ps

module alu_tb;
    reg [31:0] a, b;
    reg [3:0] ctrl;
    wire [31:0] result;
    wire zero;
    integer tests = 0;
    integer failures = 0;

    localparam [3:0] ADD=0, SUB=1, AND_OP=2, OR_OP=3, XOR_OP=4,
                     SLT=5, MUL=6, SHL=7, SHR=8, SEQ=9, MIN=10, MAX=11;

    alu dut (.a(a), .b(b), .ctrl(ctrl), .result(result), .zero(zero));

    task automatic check(
        input string name,
        input [3:0] op,
        input [31:0] lhs, rhs, expected
    );
        begin
            a = lhs;
            b = rhs;
            ctrl = op;
            #1;
            tests = tests + 1;
            if ((result !== expected) || (zero !== (expected == 32'd0))) begin
                failures = failures + 1;
                $display("FAIL %s: a=%h b=%h result=%h expected=%h zero=%b",
                         name, a, b, result, expected, zero);
            end
        end
    endtask

    initial begin
        check("addition", ADD, 2, 3, 5);
        check("addition wrap", ADD, 32'hffffffff, 1, 0);
        check("signed overflow", ADD, 32'h7fffffff, 1, 32'h80000000);
        check("subtraction negative", SUB, 3, 5, 32'hfffffffe);
        check("subtraction zero", SUB, 42, 42, 0);
        check("subtraction wrap", SUB, 0, 1, 32'hffffffff);
        check("and", AND_OP, 32'hf0f0f0f0, 32'hff00ff00, 32'hf000f000);
        check("or", OR_OP, 32'hf0f0f0f0, 32'h0f0f0f0f, 32'hffffffff);
        check("xor", XOR_OP, 32'haaaaaaaa, 32'h55555555, 32'hffffffff);
        check("xor zero", XOR_OP, 32'haaaaaaaa, 32'haaaaaaaa, 0);
        check("signed less", SLT, 32'hffffffff, 1, 1);
        check("signed greater", SLT, 1, 32'hffffffff, 0);
        check("signed extremes", SLT, 32'h80000000, 32'h7fffffff, 1);
        check("signed equal", SLT, 7, 7, 0);
        // Fixed-point constants: 1.5=0x18000, 2.0=0x20000.
        check("multiply positive", MUL, 32'h00018000, 32'h00020000, 32'h00030000);
        check("multiply negative", MUL, 32'hfffe8000, 32'h00020000, 32'hfffd0000);
        check("multiply two negatives", MUL, 32'hfffe8000, 32'hfffe0000, 32'h00030000);
        check("multiply zero", MUL, 0, 32'h80000000, 0);
        check("multiply fraction", MUL, 32'h00008000, 32'h00008000, 32'h00004000);
        check("multiply truncate positive", MUL, 1, 32'h00008000, 0);
        check("multiply truncate negative", MUL, 32'hffffffff, 32'h00008000, 32'hffffffff);
        check("multiply overflow wrap", MUL, 32'h40000000, 32'h00040000, 0);
        check("left zero shift", SHL, 32'h12345678, 0, 32'h12345678);
        check("left shift", SHL, 1, 4, 16);
        check("left shift 31", SHL, 1, 31, 32'h80000000);
        check("left shift 32 wraps", SHL, 1, 32, 1);
        check("left shift discarded bits", SHL, 32'h80000000, 1, 0);
        check("right zero shift", SHR, 32'h12345678, 0, 32'h12345678);
        check("logical right shift", SHR, 32'h80000000, 1, 32'h40000000);
        check("right shift 31", SHR, 32'h80000000, 31, 1);
        check("right shift 32 wraps", SHR, 32'h80000000, 32, 32'h80000000);
        check("right shift 63 masks", SHR, 32'h80000000, 63, 1);
        check("equal", SEQ, 32'hffffffff, 32'hffffffff, 1);
        check("not equal", SEQ, 1, 2, 0);
        check("min signed", MIN, 32'hffffffff, 1, 32'hffffffff);
        check("max signed", MAX, 32'hffffffff, 1, 1);
        check("min extreme", MIN, 32'h80000000, 32'h7fffffff, 32'h80000000);
        check("max extreme", MAX, 32'h80000000, 32'h7fffffff, 32'h7fffffff);
        check("min equal zero", MIN, 0, 0, 0);
        check("max equal", MAX, 7, 7, 7);
        // Undefined selectors currently return zero.
        for (integer op = 12; op < 16; op = op + 1)
            check("undefined operation", op[3:0], 32'hffffffff, 123, 0);
        if (failures != 0)
            $fatal(1, "%0d of %0d ALU tests failed", failures, tests);
        $display("PASS: all %0d ALU tests passed", tests);
        $finish;
    end
endmodule
