`timescale 1ns/1ps
module warp_state_tb;
    parameter integer WARPS=4, LANES=8;
    localparam integer IW=(WARPS>1)?$clog2(WARPS):1;
    reg clk=0;
    always #5 clk=~clk;
    reg reset=1, launch_valid=0, issue_accept=0, mask_write_enable=0;
    reg [IW-1:0] launch_warp_id=0, issue_warp_id=0;
    reg [31:0] launch_pc=0, issue_next_pc=0;
    reg [LANES-1:0] launch_mask=0, issue_next_mask=0;
    reg [WARPS-1:0] memory_wait_set=0, memory_wait_clear=0;
    reg [WARPS-1:0] barrier_wait_set=0, barrier_wait_clear=0, finish_mask=0;
    wire [31:0] pc [0:WARPS-1];
    wire [LANES-1:0] active_mask [0:WARPS-1];
    wire [WARPS-1:0] running, memory_wait, barrier_wait, ready_mask;
    wire [IW-1:0] selected_warp;
    wire issue_valid;
    integer checks=0;
    warp_state #(.WARPS(WARPS),.LANES(LANES)) dut (.*);
    warp_scheduler #(.WARPS(WARPS)) scheduler (
        .clk(clk),.reset(reset),.ready_mask(ready_mask),
        .issue_accept(issue_accept),.selected_warp(selected_warp),.issue_valid(issue_valid)
    );
    task tick; begin @(posedge clk); #1; end endtask
    task check(input bit ok, input string message);
        begin checks=checks+1; if (!ok) $fatal(1,"%s",message); end
    endtask
    initial begin
        tick(); check(running===0 && ready_mask===0,"reset");
        @(negedge clk); reset=0;
        for (integer w=0;w<WARPS;w=w+1) begin
            launch_valid=1; launch_warp_id=w; launch_pc=256+4*w;
            launch_mask={LANES{1'b1}};
            tick(); check(pc[w]===256+4*w && running[w] && ready_mask[w],"launch");
            @(negedge clk);
        end
        launch_valid=0; issue_warp_id=0; issue_next_pc=512;
        mask_write_enable=1; issue_next_mask=1;
        tick(); check(pc[0]===256,"unaccepted issue changed PC");
        @(negedge clk); issue_accept=1;
        tick(); check(pc[0]===512 && active_mask[0]===1,"accepted PC/mask update");
        @(negedge clk); issue_accept=0; memory_wait_set=1;
        tick(); check(!ready_mask[0] && memory_wait[0],"memory block");
        if (WARPS>1) check(issue_valid && selected_warp!=0,"scheduler must skip blocked warp");
        else check(!issue_valid,"single blocked warp must idle");
        @(negedge clk); memory_wait_set=0; issue_accept=1; issue_next_pc=999;
        tick(); check(pc[0]===512,"blocked warp PC changed");
        @(negedge clk); issue_accept=0; memory_wait_clear=1; barrier_wait_set=1;
        tick(); check(!memory_wait[0] && barrier_wait[0] && !ready_mask[0],"independent wait flags");
        @(negedge clk); memory_wait_clear=0; barrier_wait_set=0; barrier_wait_clear=1;
        tick(); check(ready_mask[0],"barrier release");
        @(negedge clk); barrier_wait_clear=0; memory_wait_set=1; memory_wait_clear=1;
        tick(); check(memory_wait[0],"wait set priority");
        @(negedge clk); finish_mask=1; launch_valid=1; launch_warp_id=0;
        tick(); check(!running[0] && !memory_wait[0] && active_mask[0]===0,"finish priority");
        @(negedge clk); finish_mask=0; launch_pc=1024;
        tick(); check(ready_mask[0] && pc[0]===1024 && !memory_wait[0],"clean relaunch");
        for (integer w=1;w<WARPS;w=w+1)
            check(pc[w]===256+4*w && ready_mask[w],"warp isolation");
        @(negedge clk); reset=1;
        tick(); check(running===0 && memory_wait===0 && barrier_wait===0,"final reset");
        $display("PASS: warp state WARPS=%0d LANES=%0d, %0d checks",WARPS,LANES,checks);
        $finish;
    end
endmodule
