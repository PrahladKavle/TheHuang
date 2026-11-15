`timescale 1ns/1ps
module mask_stack_tb;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,clear_valid=0,push=0,pop=0,commit=0;
 reg [1:0] clear_warp_id=0,warp_id=0;
 reg [7:0] current_mask=0;
 wire [7:0] restored_mask;
 wire stack_error;
 mask_stack #(.DEPTH(2)) dut(.*);
 task tick;begin @(posedge clk);#1;end endtask
 initial begin
   tick();@(negedge clk);reset=0;pop=1;#1;
   if(!stack_error)$fatal(1,"underflow");
   commit=1;tick(); // Invalid committed operation must not change count.
   @(negedge clk);pop=0;push=1;current_mask=8'hff;tick();
   @(negedge clk);current_mask=8'h55;tick();
   if(!stack_error || restored_mask!==8'h55)$fatal(1,"full stack");
   @(negedge clk);current_mask=8'h11;tick();
   if(restored_mask!==8'h55)$fatal(1,"overflow corrupted top");
   @(negedge clk);push=0;pop=1;tick();
   if(restored_mask!==8'hff)$fatal(1,"nested restore");
   @(negedge clk);warp_id=1;#1;
   if(!stack_error)$fatal(1,"warp isolation");
   pop=0;push=1;current_mask=8'haa;tick();
   @(negedge clk);warp_id=0;push=0;pop=1;commit=0;tick();
   if(restored_mask!==8'hff)$fatal(1,"unaccepted pop");
   @(negedge clk);clear_valid=1;clear_warp_id=0;tick();
   if(!stack_error)$fatal(1,"launch clear");
   @(negedge clk);clear_valid=0;warp_id=1;#1;
   if(restored_mask!==8'haa || stack_error)$fatal(1,"other warp cleared");
   @(negedge clk);reset=1;tick();
   if(!stack_error)$fatal(1,"reset clear");
   $display("PASS: mask stack nesting, bounds, isolation, acceptance, reset");$finish;
 end
endmodule
