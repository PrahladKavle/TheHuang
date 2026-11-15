`timescale 1ns/1ps
module performance_core_tb;
 parameter integer LANES=8,WARPS=4;
 localparam integer IW=(WARPS>1)?$clog2(WARPS):1;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,launch_valid=0,perf_enable=0,perf_clear=0;
 reg [IW-1:0] launch_warp_id=0,debug_warp_id=0;
 reg [31:0] launch_pc=0,launch_args[0:3];
 reg [LANES-1:0] launch_mask;
 reg [3:0] debug_register=3;
 wire [WARPS-1:0] running;
 wire busy,fault;
 wire [31:0] fault_pc,debug_data[0:LANES-1];
 wire [63:0] total_cycles,instructions_issued,active_lane_instructions;
 wire [63:0] scheduler_idle_cycles,memory_blocked_cycles;
 integer active_count=0,elapsed=0,idle=0,blocked=0;
 reg scoreboard=0;
 gpu_top #(.LANES(LANES),.WARPS(WARPS),.PROGRAM_DEPTH(32),.DATA_DEPTH(16)) dut(.*);
 function automatic [31:0] enc(input integer op,d,a,b,imm);
 enc=(op<<26)|(d<<22)|(a<<18)|(b<<14)|(imm&16383);
 endfunction
 // Independent cycle observation; instruction/lane counts checked by program length.
 always @(posedge clk) if(scoreboard && perf_enable && !reset && !perf_clear && !fault) begin
   elapsed=elapsed+1;
   if((|running) && !(|dut.core.ready_mask))idle=idle+1;
   if(|(running & dut.core.memory_wait))blocked=blocked+1;
 end
 task tick;begin @(posedge clk);#1;end endtask
 task launch_all;
 begin
   for(integer w=0;w<WARPS;w=w+1)begin
     @(negedge clk);launch_valid=1;launch_warp_id=w;tick();
   end
   @(negedge clk);launch_valid=0;perf_enable=1;
 end
 endtask
 task run_done;
 begin: run
   for(integer c=0;c<2000;c=c+1)begin
     tick();if(fault)$fatal(1,"unexpected fault");
     if(!busy)disable run;
   end
   $fatal(1,"timeout");
 end
 endtask
 initial begin
   for(integer a=0;a<4;a=a+1)launch_args[a]=0;
   for(integer l=0;l<LANES;l=l+1)begin launch_mask[l]=(l%2==0);if(l%2==0)active_count=active_count+1;end
   dut.core.program_rom.memory[0]=enc(12,1,0,0,2);
   dut.core.program_rom.memory[1]=enc(12,2,0,0,3);
   dut.core.program_rom.memory[2]=enc(0,3,1,2,0);
   dut.core.program_rom.memory[3]=enc(22,0,0,0,0);
   tick();@(negedge clk);reset=0;
   launch_all();run_done();
   if(total_cycles!==4*WARPS || instructions_issued!==4*WARPS ||
      active_lane_instructions!==4*WARPS*active_count || scheduler_idle_cycles!==0 || memory_blocked_cycles!==0)
     $fatal(1,"exact arithmetic counts cycles=%0d issues=%0d lanes=%0d",total_cycles,instructions_issued,active_lane_instructions);
   @(negedge clk);perf_enable=0;repeat(3)tick();
   if(total_cycles!==4*WARPS)$fatal(1,"disabled counters changed");
   @(negedge clk);perf_clear=1;tick();
   if(total_cycles!==0 || instructions_issued!==0)$fatal(1,"clear while disabled");
   @(negedge clk);perf_clear=0;
   dut.core.program_rom.memory[0]=enc(12,1,0,0,0);
   dut.core.program_rom.memory[1]=enc(12,2,0,0,42);
   dut.core.program_rom.memory[2]=enc(26,0,1,2,0);
   dut.core.program_rom.memory[3]=enc(25,3,1,0,0);
   dut.core.program_rom.memory[4]=enc(22,0,0,0,0);
   scoreboard=1;launch_all();run_done();
   if(total_cycles!==elapsed || instructions_issued!==5*WARPS || active_lane_instructions!==5*WARPS*active_count ||
      scheduler_idle_cycles!==idle || memory_blocked_cycles!==blocked || blocked==0 || idle==0)
     $fatal(1,"memory measurements incorrect");
   @(negedge clk);perf_enable=0;
   // A terminal instruction fault freezes further counting while enable stays high.
   dut.core.program_rom.memory[8]=enc(63,0,0,0,0);
   launch_pc=32;launch_warp_id=0;launch_valid=1;tick();
   @(negedge clk);launch_valid=0;perf_enable=1;tick();
   if(!fault)$fatal(1,"missing fault");
   begin
     reg [63:0] snapshot;
     snapshot=total_cycles;repeat(3)tick();
     if(total_cycles!==snapshot)$fatal(1,"fault did not freeze counters");
   end
   @(negedge clk);reset=1;tick();
   if(total_cycles!==0 || instructions_issued!==0 || active_lane_instructions!==0 || scheduler_idle_cycles!==0 || memory_blocked_cycles!==0)
     $fatal(1,"reset did not clear counters");
   $display("PASS: core counters LANES=%0d WARPS=%0d exact issue counts, memory cycles, freeze/clear/reset",LANES,WARPS);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
