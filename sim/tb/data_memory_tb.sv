`timescale 1ns/1ps
module data_memory_tb;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,memory_request_valid=0,memory_store=0,memory_response_ready=0;
 reg [31:0] memory_address=0,memory_write_data=0;
 wire memory_request_ready,memory_response_valid,memory_error;
 wire [31:0] memory_read_data;
 integer checks=0;
 // Non-power-of-two depth exposes incorrect bounds checks.
 data_memory #(.DEPTH(3)) dut(.*);
 task tick;begin @(posedge clk);#1;end endtask
 task check(input bit ok,input string message);
 begin checks=checks+1;if(!ok)$fatal(1,"%s",message);end endtask
 task transaction(input bit store_op,input [31:0] address,data,
                  input bit error_expected,input [31:0] expected);
 begin
   @(negedge clk);memory_request_valid=1;memory_store=store_op;
   memory_address=address;memory_write_data=data;
   check(memory_request_ready && !memory_response_valid,"idle handshake");
   tick();
   check(memory_response_valid && !memory_request_ready,"registered response");
   check(memory_error===error_expected && memory_read_data===expected,"response contents");
   // Try another request while holding the response: it must not be accepted.
   @(negedge clk);memory_store=1;memory_address=4;memory_write_data=32'hbadbad00;
   repeat(3) begin
     tick();
     check(memory_response_valid && !memory_request_ready,"response backpressure");
     check(memory_error===error_expected && memory_read_data===expected,"held response changed");
   end
   @(negedge clk);memory_request_valid=0;memory_response_ready=1;tick();
   check(!memory_response_valid && memory_request_ready,"response consumed");
   @(negedge clk);memory_response_ready=0;
 end endtask
 initial begin
   tick();check(!memory_response_valid,"reset");@(negedge clk);reset=0;
   transaction(1,0,32'h12345678,0,0);
   transaction(1,4,32'h89abcdef,0,0);
   transaction(1,8,32'hffffffff,0,0);
   transaction(0,0,0,0,32'h12345678);
   transaction(0,4,0,0,32'h89abcdef);
   transaction(0,8,0,0,32'hffffffff);
   transaction(1,1,0,1,0);
   transaction(0,2,0,1,0);
   transaction(1,12,0,1,0);
   transaction(0,32'hfffffffc,0,1,0);
   transaction(0,0,0,0,32'h12345678);
   transaction(0,4,0,0,32'h89abcdef);
   // Reset discards an unconsumed response, but preserves stored words.
   @(negedge clk);memory_request_valid=1;memory_store=0;memory_address=0;
   tick();check(memory_response_valid,"pending response before reset");
   @(negedge clk);reset=1;memory_request_valid=0;tick();
   check(!memory_response_valid && !memory_request_ready,"reset flush");
   @(negedge clk);reset=0;
   transaction(0,0,0,0,32'h12345678);
   $display("PASS: data RAM, %0d checks",checks);$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
