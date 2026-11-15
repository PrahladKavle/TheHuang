`timescale 1ns/1ps
module core_memory_tb;
 parameter integer LANES=8,WARPS=4;
 localparam integer IW=(WARPS>1)?$clog2(WARPS):1;
 reg [31:0] launch_args [0:3];
 reg perf_clear=0,perf_enable=0;
 wire [63:0] total_cycles,instructions_issued,active_lane_instructions;
 wire [63:0] scheduler_idle_cycles,memory_blocked_cycles;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,launch_valid=0;
 reg [IW-1:0] launch_warp_id=0,debug_warp_id=0;
 reg [31:0] launch_pc=0;
 reg [LANES-1:0] launch_mask;
 reg [3:0] debug_register=4;
 wire [WARPS-1:0] running;
 wire busy,fault;
 wire [31:0] fault_pc,debug_data[0:LANES-1];
 wire memory_request_valid,memory_store,memory_response_ready;
 wire [31:0] memory_address,memory_write_data;
 reg memory_request_ready=0,memory_response_valid=0,memory_error=0;
 reg [31:0] memory_read_data=0;
 reg [31:0] memory[0:255];
 integer delay_count=0,cycle=0,transactions=0,active_lanes=0;
 integer issues_while_waiting=0;
 reg waiting=0;
 reg [31:0] saved_address,saved_data;
 reg saved_store;
 minimal_core #(.LANES(LANES),.WARPS(WARPS),.PROGRAM_DEPTH(256)) dut(.*);
 function automatic [31:0] enc(input integer op,d,a,b,imm);
 enc=(op<<26)|(d<<22)|(a<<18)|(b<<14)|(imm&16383);
 endfunction
 // Memory model: variable request backpressure plus delayed response.
 always @(posedge clk) begin
   if(reset)begin
     memory_request_ready<=0;memory_response_valid<=0;
     waiting<=0;cycle<=0;delay_count<=0;
   end else begin
     cycle<=cycle+1;
     memory_request_ready<=!waiting && !memory_response_valid && cycle%3==0;
     if(memory_request_valid && memory_request_ready) begin
       saved_address<=memory_address;saved_data<=memory_write_data;saved_store<=memory_store;
       delay_count<=3+(transactions%4);waiting<=1;memory_request_ready<=0;
       transactions<=transactions+1;
     end
     if(waiting)begin
       if(delay_count==0)begin
         waiting<=0;memory_response_valid<=1;memory_error<=0;
         if(saved_store)begin memory[saved_address>>2]<=saved_data;memory_read_data<=0;end
         else memory_read_data<=memory[saved_address>>2];
       end else delay_count<=delay_count-1;
     end
     if(memory_response_valid && memory_response_ready)memory_response_valid<=0;
     if((|dut.memory_wait) && dut.issue_accept)issues_while_waiting<=issues_while_waiting+1;
   end
 end
 task tick;begin @(posedge clk);#1;end endtask
 initial begin
   for(integer l=0;l<LANES;l=l+1)begin launch_mask[l]=(l%2==0);if(l%2==0)active_lanes=active_lanes+1;end
   for(integer w=0;w<WARPS;w=w+1)begin
     dut.program_rom.memory[w*16]=enc(12,1,0,0,w*64);
     dut.program_rom.memory[w*16+1]=enc(12,2,0,0,100+w);
     dut.program_rom.memory[w*16+2]=enc(26,0,1,2,0);
     dut.program_rom.memory[w*16+3]=enc(12,3,0,0,77);
     dut.program_rom.memory[w*16+4]=enc(25,3,1,0,0);
     dut.program_rom.memory[w*16+5]=enc(0,4,3,2,0);
     dut.program_rom.memory[w*16+6]=enc(22,0,0,0,0);
   end
   tick();@(negedge clk);reset=0;
   for(integer w=0;w<WARPS;w=w+1)begin
     launch_valid=1;launch_warp_id=w;launch_pc=w*64;tick();@(negedge clk);
   end
   launch_valid=0;
   begin: run
     for(integer i=0;i<10000;i=i+1)begin
       tick();if(fault)$fatal(1,"fault PC=%h",fault_pc);
       if(!busy)disable run;
     end
     $fatal(1,"execution timeout");
   end
   if(transactions!=2*WARPS*active_lanes)$fatal(1,"masked lanes issued memory: count=%0d",transactions);
   for(integer w=0;w<WARPS;w=w+1)begin
     if(memory[w*16]!==100+w)$fatal(1,"store data");
     debug_warp_id=w;debug_register=4;#1;
     for(integer l=0;l<LANES;l=l+1)
       if(launch_mask[l] && debug_data[l]!==200+2*w)$fatal(1,"load/writeback warp=%0d lane=%0d got=%h",w,l,debug_data[l]);
   end
   if(WARPS>1 && issues_while_waiting==0)$fatal(1,"no latency hiding");
   // Misaligned load must fault at the original memory PC and not write.
   dut.program_rom.memory[200]=enc(25,4,0,0,1);
   @(negedge clk);launch_valid=1;launch_warp_id=0;launch_pc=800;tick();
   @(negedge clk);launch_valid=0;
   begin: fault_wait
     for(integer i=0;i<100;i=i+1)begin tick();if(fault)disable fault_wait;end
     $fatal(1,"missing alignment fault");
   end
   if(fault_pc!==800)$fatal(1,"wrong fault PC");
   debug_warp_id=0;#1;
   for(integer l=0;l<LANES;l=l+1)
     if(launch_mask[l] && debug_data[l]!==200)$fatal(1,"fault corrupted destination");
   $display("PASS: memory core LANES=%0d WARPS=%0d transactions=%0d other issues while waiting=%0d",LANES,WARPS,transactions,issues_while_waiting);
   $finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
