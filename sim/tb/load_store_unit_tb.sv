`timescale 1ns/1ps
module load_store_unit_tb;
 reg clk=0; always #5 clk=~clk;
 reg reset=1,issue_valid=0,lane_active=1,issue_store=0;
 reg [31:0] base_address=0,offset=0,store_data=0;
 reg [1:0] issue_warp_id=0;
 reg [3:0] issue_rd=0;
 wire issue_ready,busy,request_valid,request_store,response_ready,completion_valid;
 reg request_ready=0,response_valid=0,response_error=0,completion_ready=0;
 reg [31:0] response_data=0;
 wire [31:0] request_address,request_data,completion_data;
 wire completion_error,completion_write_enable;
 wire [1:0] completion_warp_id;
 wire [3:0] completion_rd;
 integer checks=0;
 load_store_unit dut(.*);
 task tick; begin @(posedge clk); #1; end endtask
 task check(input bit ok,input string msg);
 begin checks=checks+1; if(!ok) $fatal(1,"%s",msg); end endtask
 task launch(input bit active,store_op,input [31:0] base,offs,input [3:0] dest);
 begin
   @(negedge clk);issue_valid=1;lane_active=active;issue_store=store_op;
   base_address=base;offset=offs;store_data=32'hdeadbeef;issue_warp_id=3;issue_rd=dest;
   check(issue_ready,"not ready to issue");tick();
   @(negedge clk);issue_valid=0;
 end endtask
 task consume;
 begin
   repeat(3) begin tick();check(completion_valid && !issue_ready,"completion not held");end
   @(negedge clk);completion_ready=1;tick();
   check(issue_ready && !busy,"did not return idle");
   @(negedge clk);completion_ready=0;
 end endtask
 task memory_reply(input bit err);
 begin
   repeat(3) begin tick();check(request_valid && request_address==32'hfc && request_data==32'hdeadbeef,"request unstable");end
   @(negedge clk);request_ready=1;tick();
   check(response_ready && !request_valid,"request handshake");
   @(negedge clk);request_ready=0;
   repeat(3) begin tick();check(busy && !completion_valid,"response delay");end
   @(negedge clk);response_valid=1;response_data=32'h12345678;response_error=err;
   tick();check(completion_valid && completion_data==32'h12345678,"response capture");
   check(completion_warp_id==3 && completion_rd==issue_rd,"response metadata");
   @(negedge clk);response_valid=0;response_error=0;
 end endtask
 initial begin
   tick();check(!busy,"reset idle");@(negedge clk);reset=0;
   launch(1,0,256,32'hfffffffc,5);
   // Inputs may change while pending; the saved transaction must not change.
   base_address=999;offset=7;store_data=0;issue_warp_id=0;
   memory_reply(0);check(completion_write_enable && !completion_error,"load completion");consume();
   launch(1,1,256,32'hfffffffc,0);memory_reply(0);
   check(!completion_write_enable && !completion_error && request_store,"store completion");consume();
   launch(1,0,256,32'hfffffffc,5);memory_reply(1);
   check(completion_error && !completion_write_enable,"bus error");consume();
   launch(1,0,256,32'hfffffffc,0);memory_reply(0);
   check(!completion_write_enable,"zero register write");consume();
   launch(0,1,1,0,5);
   check(completion_valid && !request_valid && !completion_error && !completion_write_enable,"masked lane");consume();
   launch(1,0,1,0,5);
   check(completion_valid && completion_error && !request_valid,"unaligned load");consume();
   launch(1,1,2,0,0);
   check(completion_valid && completion_error && !request_valid,"unaligned store");consume();
   launch(1,0,0,0,5);
   @(negedge clk);reset=1;tick();check(!busy && !request_valid && !completion_valid,"reset cancels request");
   $display("PASS: load/store unit, %0d checks",checks);$finish;
 end
 initial begin #10000; $fatal(1,"timeout");end
endmodule
