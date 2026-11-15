`timescale 1ns/1ps
module simd_core_tb;
    parameter integer LANES=8, WARPS=4;
    localparam integer IW=(WARPS>1)?$clog2(WARPS):1;
    reg clk=0;
    always #5 clk=~clk;
    reg [IW-1:0] read_warp_id=0, write_warp_id=0;
    reg [3:0] rs1, rs2, rd=0, alu_ctrl=0;
    reg write_enable=0, external_writeback_select=1;
    reg [LANES-1:0] active_mask={LANES{1'b1}};
    reg [31:0] external_writeback_data [0:LANES-1];
    wire [31:0] read_data1 [0:LANES-1], read_data2 [0:LANES-1];
    wire [31:0] alu_result [0:LANES-1];
    wire [LANES-1:0] zero;
    reg [31:0] expected [0:WARPS-1][0:LANES-1][0:15];
    integer checks=0;
    simd_core #(.LANES(LANES), .WARPS(WARPS)) dut (.*);

    task automatic commit(input integer warp, dest, input bit ext_sel,
                          input [LANES-1:0] mask, input bit enable);
        begin
            @(negedge clk);
            write_warp_id=warp; rd=dest;
            external_writeback_select=ext_sel;
            active_mask=mask; write_enable=enable;
            #1;
            for (integer l=0;l<LANES;l=l+1)
                if (enable && mask[l] && dest!=0)
                    expected[warp][l][dest]=ext_sel ? external_writeback_data[l] : alu_result[l];
            @(posedge clk); #1; write_enable=0;
        end
    endtask

    task automatic check_regs(input integer warp, r1, r2);
        begin
            read_warp_id=warp; rs1=r1; rs2=r2; #1;
            for (integer l=0;l<LANES;l=l+1) begin
                checks=checks+1;
                if (read_data1[l] !== expected[warp][l][r1] ||
                    read_data2[l] !== expected[warp][l][r2])
                    $fatal(1,"warp=%0d lane=%0d r%0d=%h expected=%h r%0d=%h expected=%h",
                        warp,l,r1,read_data1[l],expected[warp][l][r1],r2,read_data2[l],expected[warp][l][r2]);
            end
        end
    endtask

    initial begin
        for (integer w=0;w<WARPS;w=w+1) begin
            for (integer l=0;l<LANES;l=l+1) expected[w][l][0]=0;
            for (integer r=1;r<=3;r=r+1) begin
                for (integer l=0;l<LANES;l=l+1)
                    external_writeback_data[l]=100*w+10*r+l;
                commit(w,r,1,{LANES{1'b1}},1);
            end
        end
        for (integer w=0;w<WARPS;w=w+1) begin
            check_regs(w,1,2);
            alu_ctrl=0; #1;
            // Independent expected sum, before the shared ADD commits.
            for (integer l=0;l<LANES;l=l+1) begin
                if (alu_result[l] !== (200*w+30+2*l))
                    $fatal(1,"lane %0d ADD incorrect",l);
            end
            commit(w,3,0,{LANES{1'b1}},1);
            check_regs(w,3,0);
            // Different operation and alternating lanes: masked lanes retain ADD.
            check_regs(w,2,1); alu_ctrl=1; #1;
            for (integer l=0;l<LANES;l=l+1)
                if (alu_result[l] !== 32'd10) $fatal(1,"SUB incorrect");
            begin : masked_sub
                reg [LANES-1:0] mask;
                for (integer l=0;l<LANES;l=l+1) mask[l]=(l%2==0);
                commit(w,3,0,mask,1);
                check_regs(w,3,0);
            end
            for (integer l=0;l<LANES;l=l+1) external_writeback_data[l]=32'hdeadbeef;
            commit(w,3,1,{LANES{1'b0}},1);
            check_regs(w,3,0);
            commit(w,3,1,{LANES{1'b1}},0);
            check_regs(w,3,0);
            commit(w,0,1,{LANES{1'b1}},1);
            check_regs(w,0,3);
        end
        // A write response can target a different warp from the read selector.
        read_warp_id=0;
        for (integer l=0;l<LANES;l=l+1) external_writeback_data[l]=32'h12340000+l;
        commit(WARPS-1,1,1,{LANES{1'b1}},1);
        for (integer w=0;w<WARPS;w=w+1) check_regs(w,1,3);
        rs1=0; rs2=0; alu_ctrl=0; #1;
        if (zero !== {LANES{1'b1}}) $fatal(1,"zero flags incorrect");
        $display("PASS: LANES=%0d WARPS=%0d: %0d lane read checks",LANES,WARPS,checks);
        $finish;
    end
endmodule
