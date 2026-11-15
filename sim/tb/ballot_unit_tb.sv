`timescale 1ns/1ps
module ballot_unit_tb;
 reg [3:0] active_mask,predicates;
 wire [31:0] vote_mask;
 ballot_unit #(.LANES(4)) dut(.*);
 initial begin
   for(integer m=0;m<16;m=m+1)
     for(integer p=0;p<16;p=p+1)begin
       active_mask=m;predicates=p;#1;
       if(vote_mask!==(m&p))$fatal(1,"vote incorrect");
     end
   $display("PASS: ballot unit, all 256 predicate/mask combinations");$finish;
 end
endmodule
