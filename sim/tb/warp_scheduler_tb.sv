`timescale 1ns/1ps
module warp_scheduler_tb;
    parameter integer WARPS=4;
    localparam integer IW=(WARPS>1)?$clog2(WARPS):1;
    reg clk=0;
    always #5 clk=~clk;
    reg reset=1, issue_accept=0;
    reg [WARPS-1:0] ready_mask=0;
    wire [IW-1:0] selected_warp;
    wire issue_valid;
    integer pointer=0, checks=0, expected, candidate;
    warp_scheduler #(.WARPS(WARPS)) dut (.*);

    task automatic cycle(input [WARPS-1:0] mask, input bit accept, rst);
        begin
            @(negedge clk);
            ready_mask=mask; issue_accept=accept; reset=rst;
            #1;
            expected=-1;
            // Independent reference: scan absolute IDs from pointer through
            // the end, then wrap to IDs below pointer.
            if (!rst) begin
                for (integer i=0;i<WARPS;i=i+1) begin
                    candidate=(pointer+i)%WARPS;
                    if (expected==-1 && mask[candidate]) expected=candidate;
                end
            end
            checks=checks+1;
            if (issue_valid !== (expected!=-1)) $fatal(1,"valid mismatch");
            if (expected!=-1 && selected_warp !== IW'(expected))
                $fatal(1,"selected %0d expected %0d",selected_warp,expected);
            @(posedge clk); #1;
            if (rst) pointer=0;
            else if (accept && expected!=-1) pointer=(expected+1)%WARPS;
        end
    endtask

    initial begin
        cycle(0,0,1);
        for (integer i=0;i<3*WARPS;i=i+1) cycle({WARPS{1'b1}},1,0);
        // Unaccepted selections must not consume a turn.
        repeat (4) cycle({WARPS{1'b1}},0,0);
        cycle({WARPS{1'b1}},1,0);
        repeat (3) cycle(0,1,0);
        for (integer w=0;w<WARPS;w=w+1) begin
            cycle({{(WARPS-1){1'b0}},1'b1} << w,1,0);
            cycle({{(WARPS-1){1'b0}},1'b1} << w,1,0);
        end
        // Exercise every ready-mask pattern, including gaps and all-idle.
        for (integer mask=0;mask<(1<<WARPS);mask=mask+1)
            for (integer j=0;j<WARPS+1;j=j+1) cycle(mask,1,0);
        cycle({WARPS{1'b1}},1,1);
        cycle({WARPS{1'b1}},1,0);
        $display("PASS: scheduler WARPS=%0d, %0d cycles",WARPS,checks);
        $finish;
    end
endmodule
