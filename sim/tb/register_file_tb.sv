`timescale 1ns/1ps
module register_file_tb;
    parameter integer WARPS = 4;
    localparam integer ID_WIDTH = (WARPS > 1) ? $clog2(WARPS) : 1;
    reg clk = 0;
    always #5 clk = ~clk;
    reg [3:0] rs1, rs2, ws = 0;
    reg [31:0] w_data = 0;
    reg w_en = 0;
    reg [ID_WIDTH-1:0] read_warp_id = 0, write_warp_id = 0;
    wire [31:0] rs1_data, rs2_data;
    reg [31:0] expected [0:WARPS-1][0:15];
    integer checks = 0;

    register_file #(.WARPS(WARPS)) dut (
        .clk(clk), .rs1(rs1), .rs2(rs2), .ws(ws), .w_data(w_data),
        .w_en(w_en), .read_warp_id(read_warp_id),
        .write_warp_id(write_warp_id), .rs1_data(rs1_data), .rs2_data(rs2_data)
    );

    task automatic check_read(input integer warp, r1, r2);
        begin
            read_warp_id = warp;
            rs1 = r1;
            rs2 = r2;
            #1;
            checks = checks + 1;
            if (rs1_data !== expected[warp][r1] || rs2_data !== expected[warp][r2])
                $fatal(1, "warp=%0d rs1=%0d got=%h expected=%h rs2=%0d got=%h expected=%h",
                    warp, r1, rs1_data, expected[warp][r1], r2, rs2_data, expected[warp][r2]);
        end
    endtask

    task automatic write_reg(input integer warp, addr, input [31:0] value, input bit enable);
        begin
            @(negedge clk);
            write_warp_id = warp;
            ws = addr;
            w_data = value;
            w_en = enable;
            @(posedge clk);
            #1; // Wait for nonblocking writes to commit.
            if (enable && addr != 0) expected[warp][addr] = value;
            w_en = 0;
        end
    endtask

    initial begin
        for (integer w=0; w<WARPS; w=w+1) begin
            expected[w][0] = 0;
            check_read(w, 0, 0);
            for (integer r=1; r<16; r=r+1)
                write_reg(w, r, (w+1)*32'h10000+r, 1);
        end
        // Check every pair of read addresses, across every warp.
        for (integer w=0; w<WARPS; w=w+1)
            for (integer r=0; r<16; r=r+1)
                for (integer s=0; s<16; s=s+1)
                    check_read(w, r, s);
        for (integer w=0; w<WARPS; w=w+1) begin
            write_reg(w, 0, 32'hffffffff, 1);
            check_read(w, 0, 15);
            write_reg(w, 15, 32'hdeadbeef, 0);
            check_read(w, 15, 1);
        end
        // Setup alone must not write before a rising edge. Read and write
        // selectors deliberately target different warps when available.
        @(negedge clk);
        read_warp_id = 0;
        rs1 = 1;
        rs2 = 2;
        write_warp_id = WARPS-1;
        ws = 1;
        w_data = 32'hcafebabe;
        w_en = 1;
        #1;
        check_read(WARPS-1, 1, 2);
        check_read(0, 1, 2);
        @(posedge clk);
        #1;
        expected[WARPS-1][1] = 32'hcafebabe;
        w_en = 0;
        for (integer w=0; w<WARPS; w=w+1)
            check_read(w, 1, 2);
        $display("PASS: WARPS=%0d, %0d read checks", WARPS, checks);
        $finish;
    end
endmodule
