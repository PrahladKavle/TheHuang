`timescale 1ns/1ps
module execution_lane_tb;
    parameter integer WARPS = 4;
    localparam integer IW = (WARPS > 1) ? $clog2(WARPS) : 1;
    reg clk = 0;
    always #5 clk = ~clk;
    reg [IW-1:0] read_warp_id = 0, write_warp_id = 0;
    reg [3:0] rs1, rs2, rd = 0, alu_ctrl = 0;
    reg write_enable = 0, lane_active = 1, external_writeback_select = 1;
    reg [31:0] external_writeback_data = 0;
    wire [31:0] read_data1, read_data2, alu_result;
    wire zero;
    integer checks = 0;
    execution_lane #(.WARPS(WARPS)) dut (.*);

    task automatic commit(input integer warp, dest, input bit external_sel,
                          input [31:0] data, input bit active, enabled);
        begin
            @(negedge clk);
            write_warp_id = warp;
            rd = dest;
            external_writeback_select = external_sel;
            external_writeback_data = data;
            lane_active = active;
            write_enable = enabled;
            @(posedge clk);
            #1;
            write_enable = 0;
        end
    endtask

    task automatic expect_read(input integer warp, regnum, input [31:0] value);
        begin
            read_warp_id = warp;
            rs1 = regnum;
            rs2 = 0;
            #1;
            checks = checks + 1;
            if (read_data1 !== value || read_data2 !== 0)
                $fatal(1, "warp %0d register %0d got %h expected %h", warp, regnum, read_data1, value);
        end
    endtask

    initial begin
        // Distinct values in each warp expose accidental register sharing.
        for (integer w=0; w<WARPS; w=w+1) begin
            commit(w, 1, 1, 2+w, 1, 1);
            commit(w, 2, 1, 3+w, 1, 1);
            commit(w, 3, 1, 99, 1, 1);
        end
        for (integer w=0; w<WARPS; w=w+1) begin
            read_warp_id = w;
            rs1 = 1; rs2 = 2; alu_ctrl = 0;
            commit(w, 3, 0, 0, 1, 1);
            expect_read(w, 3, 5+2*w);
            rs1 = 1; rs2 = 2;
            commit(w, 3, 0, 0, 0, 1); // Masked ALU write.
            expect_read(w, 3, 5+2*w);
            commit(w, 3, 1, 123, 0, 1); // Masked external write.
            expect_read(w, 3, 5+2*w);
            commit(w, 3, 1, 123, 1, 0); // Disabled write.
            expect_read(w, 3, 5+2*w);
            commit(w, 0, 1, 32'hffffffff, 1, 1);
            expect_read(w, 0, 0);
        end
        // Independent write warp: model a returning memory result.
        read_warp_id = 0;
        commit(WARPS-1, 4, 1, 32'hdeadbeef, 1, 1);
        expect_read(WARPS-1, 4, 32'hdeadbeef);
        for (integer w=0; w<WARPS; w=w+1)
            expect_read(w, 3, 5+2*w);
        // Exercise fixed-point arithmetic through register reads/write-back.
        commit(0, 1, 1, 32'hfffe8000, 1, 1);
        commit(0, 2, 1, 32'h00020000, 1, 1);
        read_warp_id = 0; rs1 = 1; rs2 = 2; alu_ctrl = 6;
        commit(0, 3, 0, 0, 1, 1);
        expect_read(0, 3, 32'hfffd0000);
        rs1 = 0; rs2 = 0; alu_ctrl = 0;
        #1;
        if (alu_result !== 0 || zero !== 1) $fatal(1, "zero output incorrect");
        $display("PASS: execution lane WARPS=%0d, %0d read checks", WARPS, checks);
        $finish;
    end
endmodule
