`timescale 1ns/1ps
module barrier_controller_tb;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,arrive_valid=0;
 reg [3:0] running=0;
 reg [1:0] arrive_warp_id=0;
 wire epoch_active;
 wire [3:0] wait_set,wait_clear;
 barrier_controller dut(.*);
 task tick;begin @(posedge clk);#1;end endtask
 task arrive(input integer w);
 begin @(negedge clk);arrive_valid=1;arrive_warp_id=w;tick();@(negedge clk);arrive_valid=0;end
 endtask
 initial begin
   tick();@(negedge clk);reset=0;running=15;
   arrive(0);if(!epoch_active || wait_clear!==0)$fatal(1,"early release");
   arrive(2);arrive(3);
   if(wait_clear!==0)$fatal(1,"missing participant ignored");
   running=13;#1;if(wait_clear!==13)$fatal(1,"retirement did not release");
   tick();if(epoch_active)$fatal(1,"epoch not cleared");
   @(negedge clk);running=5;
   arrive(2);arrive(0);#1;
   if(wait_clear!==5)$fatal(1,"repeated barrier");
   tick();if(epoch_active)$fatal(1,"repeat clear");
   @(negedge clk);running=1;arrive(0);#1;
   if(wait_clear!==1)$fatal(1,"single participant");
   tick();@(negedge clk);running=15;arrive(0);
   reset=1;tick();if(epoch_active || wait_set!==0 || wait_clear!==0)$fatal(1,"reset");
   $display("PASS: barrier controller membership, retirement, reuse, single warp, reset");$finish;
 end
endmodule
