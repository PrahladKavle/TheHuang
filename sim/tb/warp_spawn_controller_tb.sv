`timescale 1ns/1ps
module warp_spawn_controller_tb;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,start=0,launch_accept=0;
 reg [2:0] target_mask=0;
 reg [31:0] entry_pc=0,parent_args[0:3];
 reg [7:0] parent_mask=0;
 wire busy,launch_valid;
 wire [1:0] launch_warp_id;
 wire [31:0] launch_pc,launch_args[0:3];
 wire [7:0] launch_mask;
 warp_spawn_controller #(.WARPS(3)) dut(.*);
 task tick;begin @(posedge clk);#1;end endtask
 initial begin
   tick();@(negedge clk);reset=0;start=1;target_mask=5;
   entry_pc=64;parent_mask=8'h55;
   for(integer a=0;a<4;a=a+1)parent_args[a]=100+a;
   tick();@(negedge clk);start=0;entry_pc=999;parent_mask=0;
   for(integer a=0;a<4;a=a+1)parent_args[a]=0;
   repeat(3)begin
     tick();if(!busy || !launch_valid || launch_warp_id!==0 || launch_pc!==64 || launch_mask!==8'h55)$fatal(1,"launch backpressure");
     for(integer a=0;a<4;a=a+1)if(launch_args[a]!==100+a)$fatal(1,"captured args");
   end
   @(negedge clk);launch_accept=1;tick();
   if(!busy || launch_warp_id!==2)$fatal(1,"target enumeration");
   tick();if(busy || launch_valid)$fatal(1,"spawn not completed");
   @(negedge clk);start=1;target_mask=0;tick();
   if(busy)$fatal(1,"zero mask no-op");
   @(negedge clk);target_mask=7;tick();
   @(negedge clk);start=0;reset=1;tick();
   if(busy || launch_valid)$fatal(1,"reset pending launches");
   $display("PASS: spawn controller capture, backpressure, ordering, no-op, reset");$finish;
 end
endmodule
