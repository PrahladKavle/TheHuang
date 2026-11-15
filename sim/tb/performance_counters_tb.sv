`timescale 1ns/1ps
module performance_counters_tb;
    parameter integer LANES=8,WARPS=4;
    reg clk=0;always #5 clk=~clk;
    reg reset=1,clear=0,enable=0,issue_accept=0;
    reg [LANES-1:0] issued_active_mask=0;
    reg [WARPS-1:0] running=0,ready_mask=0,memory_wait=0;
    wire [63:0] total_cycles,instructions_issued,active_lane_instructions;
    wire [63:0] scheduler_idle_cycles,memory_blocked_cycles;
    performance_counters #(.LANES(LANES),.WARPS(WARPS)) dut(.*);
    task tick;begin @(posedge clk);#1;end endtask
    task expect_counts(input [63:0] cycles,issues,lanes,idle,blocked);
        begin
            if(total_cycles!==cycles || instructions_issued!==issues ||
               active_lane_instructions!==lanes || scheduler_idle_cycles!==idle ||
               memory_blocked_cycles!==blocked)
                $fatal(1,"got cycles=%0d issues=%0d lanes=%0d idle=%0d blocked=%0d expected=%0d,%0d,%0d,%0d,%0d",
                    total_cycles,instructions_issued,active_lane_instructions,
                    scheduler_idle_cycles,memory_blocked_cycles,cycles,issues,lanes,idle,blocked);
        end
    endtask
    initial begin
        tick();expect_counts(0,0,0,0,0);
        @(negedge clk);reset=0;enable=1;running=1;ready_mask=1;
        issue_accept=1;issued_active_mask={LANES{1'b1}};
        tick();expect_counts(1,1,LANES,0,0);
        @(negedge clk);issued_active_mask=1;
        tick();expect_counts(2,2,LANES+1,0,0);
        @(negedge clk);issued_active_mask=0;
        tick();expect_counts(3,3,LANES+1,0,0);
        @(negedge clk);issue_accept=0;issued_active_mask={LANES{1'b1}};
        tick();expect_counts(4,3,LANES+1,0,0); // Ready but no issue is not scheduler-idle.
        @(negedge clk);ready_mask=0;memory_wait=1;
        tick();expect_counts(5,3,LANES+1,1,1);
        @(negedge clk);memory_wait=0;
        tick();expect_counts(6,3,LANES+1,2,1); // Barrier-only wait.
        @(negedge clk);running=0;memory_wait={WARPS{1'b1}};
        tick();expect_counts(7,3,LANES+1,2,1); // Stale waits on inactive warps ignored.
        @(negedge clk);enable=0;issue_accept=1;
        tick();expect_counts(7,3,LANES+1,2,1);
        @(negedge clk);clear=1;
        tick();expect_counts(0,0,0,0,0); // Clear works while disabled.
        @(negedge clk);enable=1;running={WARPS{1'b1}};ready_mask=1;
        tick();expect_counts(0,0,0,0,0); // Clear beats events.
        @(negedge clk);clear=0;issued_active_mask={LANES{1'b1}};
        memory_wait=(WARPS>1)?2:0;
        tick();expect_counts(1,1,LANES,0,(WARPS>1)?1:0); // Issue overlaps another warp's wait.
        @(negedge clk);reset=1;
        tick();expect_counts(0,0,0,0,0);
        $display("PASS: performance counters LANES=%0d WARPS=%0d exact counts, gating, priority, overlaps",LANES,WARPS);
        $finish;
    end
endmodule
