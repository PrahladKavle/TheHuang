`timescale 1ns/1ps
module assembled_program_tb;
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
 gpu_top #(.LANES(LANES),.WARPS(WARPS),.PROGRAM_DEPTH(4),.PROGRAM_INIT_FILE("output/programs/add.hex"),.DATA_DEPTH(16)) dut(.*);
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
   launch_mask={LANES{1'b1}};
   for(integer a=0;a<4;a=a+1)launch_args[a]=0;
   tick();@(negedge clk);reset=0;
   launch_all();run_done();
   for(integer w=0;w<WARPS;w=w+1)begin
     debug_warp_id=w;debug_register=3;#1;
     for(integer l=0;l<LANES;l=l+1)
       if(debug_data[l]!==5)$fatal(1,"assembled ADD failed warp=%0d lane=%0d",w,l);
   end
   if(instructions_issued!==4*WARPS)$fatal(1,"unexpected instruction count");
   $display("PASS: assembled add.hex LANES=%0d WARPS=%0d: all active lanes r3=5",LANES,WARPS);$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
