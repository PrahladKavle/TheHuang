`timescale 1ns/1ps
module branch_unit_tb;
    parameter integer LANES=8;
    reg [31:0] pc, immediate;
    reg branch, branch_any;
    reg [LANES-1:0] active_mask;
    wire branch_taken;
    wire [31:0] sequential_pc, branch_target, next_pc;
    integer checks=0;
    branch_unit #(.LANES(LANES)) dut(.*);
    task automatic check(input [31:0] address, offset,
        input bit unconditional, conditional,
        input [LANES-1:0] mask,
        input bit taken,
        input [31:0] target, expected);
        begin
            pc=address; immediate=offset; branch=unconditional;
            branch_any=conditional; active_mask=mask; #1;
            checks=checks+1;
            if(branch_taken !== taken || branch_target !== target || next_pc !== expected || sequential_pc !== address+32'd4)
                $fatal(1,"next PC=%h expected=%h target=%h expected=%h taken=%b",next_pc,expected,branch_target,target,branch_taken);
        end
    endtask
    initial begin
        check(32'h100,3,0,0,0,0,32'h110,32'h104);
        check(32'h100,3,1,0,0,1,32'h110,32'h110);
        check(32'h100,32'hfffffffe,1,0,0,1,32'hfc,32'hfc);
        check(32'h100,32'hffffffff,1,0,0,1,32'h100,32'h100);
        check(32'h100,0,1,0,0,1,32'h104,32'h104);
        check(32'h100,3,0,1,0,0,32'h110,32'h104);
        for(integer l=0;l<LANES;l=l+1)
            check(32'h100,3,0,1,{{(LANES-1){1'b0}},1'b1}<<l,1,32'h110,32'h110);
        check(32'h100,3,0,1,{LANES{1'b1}},1,32'h110,32'h110);
        check(32'h100,8191,1,0,0,1,32'h8100,32'h8100);
        check(32'h10000,32'hffffe000,1,0,0,1,32'h8004,32'h8004);
        check(32'hfffffffc,1,1,0,0,1,4,4);
        check(0,32'hfffffffe,1,0,0,1,32'hfffffffc,32'hfffffffc);
        $display("PASS: branch unit LANES=%0d, %0d checks",LANES,checks);
        $finish;
    end
endmodule
