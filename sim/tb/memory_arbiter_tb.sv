`timescale 1ns/1ps
module memory_arbiter_tb;
 parameter integer CLIENTS=4;
 reg clk=0;always #5 clk=~clk;
 reg reset=1;
 reg [CLIENTS-1:0] client_request_valid=0,client_store=0,client_response_ready=0;
 wire [CLIENTS-1:0] client_request_ready,client_response_valid;
 reg [31:0] client_address[0:CLIENTS-1],client_data[0:CLIENTS-1];
 wire [31:0] client_response_data;
 wire client_response_error,memory_request_valid,memory_response_ready,memory_store;
 wire [31:0] memory_address,memory_write_data;
 reg memory_request_ready=0,memory_response_valid=0,memory_error=0;
 reg [31:0] memory_read_data=0;
 integer checks=0;
 memory_arbiter #(.CLIENTS(CLIENTS)) dut(.*);
 task tick;begin @(posedge clk);#1;end endtask
 task check(input bit ok,input string msg);
 begin checks=checks+1;if(!ok)$fatal(1,"%s",msg);end endtask
 initial begin
   for(integer c=0;c<CLIENTS;c=c+1) begin client_address[c]=c*4;client_data[c]=100+c;client_store[c]=c%2;end
   tick();@(negedge clk);reset=0;client_request_valid={CLIENTS{1'b1}};#1;
   for(integer n=0;n<CLIENTS*2;n=n+1) begin
     check(client_request_ready===({{(CLIENTS-1){1'b0}},1'b1}<<(n%CLIENTS)),"round robin selection");
     tick();check(memory_request_valid,"request capture");
     for(integer delay=0;delay<3;delay=delay+1) begin
       check(memory_address==4*(n%CLIENTS) && memory_write_data==100+n%CLIENTS && memory_store==(n%CLIENTS)%2,"stable payload");
       tick();
     end
     @(negedge clk);memory_request_ready=1;tick();
     check(!memory_request_valid && client_request_ready===0,"one outstanding only");
     @(negedge clk);memory_request_ready=0;
     repeat(2)tick();
     @(negedge clk);memory_response_valid=1;memory_read_data=32'h1234+n;memory_error=n%2;#1;
     check(client_response_valid===({{(CLIENTS-1){1'b0}},1'b1}<<(n%CLIENTS)),"response owner");
     check(!memory_response_ready,"response backpressure");
     repeat(2)begin tick();check(client_response_valid[n%CLIENTS],"response held");end
     check(client_response_data===32'h1234+n && client_response_error===1'(n%2),"response data/error");
     @(negedge clk);client_response_ready={CLIENTS{1'b1}};tick();
     @(negedge clk);memory_response_valid=0;client_response_ready=0;#1;
   end
   client_request_valid=0;#1;check(client_request_ready===0,"idle selection");
   reset=1;tick();check(!memory_request_valid && !memory_response_ready,"reset");
   $display("PASS: arbiter CLIENTS=%0d, %0d checks",CLIENTS,checks);$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
