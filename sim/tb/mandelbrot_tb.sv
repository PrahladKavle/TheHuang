`timescale 1ns/1ps
module mandelbrot_tb;
 parameter integer WIDTH=16,HEIGHT=16,PROGRAM_WORDS=87,MAX_CYCLES=1000000;
 parameter PROGRAM_FILE="output/mandelbrot/16x16/seahorse_step0/program.hex";
 parameter EXPECTED_FILE="output/mandelbrot/16x16/seahorse_step0/expected.hex";
 parameter ARGS_FILE="output/mandelbrot/16x16/seahorse_step0/launch_args.hex";
 parameter FRAME_FILE="output/mandelbrot/16x16/seahorse_step0/rtl_frame.hex";
 localparam integer PIXELS=WIDTH*HEIGHT;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,launch_valid=0,perf_clear=0,perf_enable=0;
 reg [1:0] launch_warp_id=0,debug_warp_id=0;
 reg [31:0] launch_pc=0,launch_args[0:3];
 reg [7:0] launch_mask=255;
 reg [3:0] debug_register=0;
 wire [3:0] running;
 wire busy,fault;
 wire [31:0] fault_pc,debug_data[0:7];
 wire [63:0] total_cycles,instructions_issued,active_lane_instructions;
 wire [63:0] scheduler_idle_cycles,memory_blocked_cycles;
 reg [31:0] expected[0:2*PIXELS-1];
 gpu_top #(.PROGRAM_DEPTH(PROGRAM_WORDS),.DATA_DEPTH(2*PIXELS),
     .PROGRAM_INIT_FILE(PROGRAM_FILE)) dut(.*);
 initial begin
   $readmemh(EXPECTED_FILE,expected);
   $readmemh(ARGS_FILE,launch_args);
   @(posedge clk);#1;@(negedge clk);reset=0;
   for(integer w=0;w<4;w=w+1)begin
     launch_valid=1;launch_warp_id=w;@(posedge clk);#1;@(negedge clk);
   end
   launch_valid=0;perf_enable=1;
   begin: run
     for(integer c=0;c<MAX_CYCLES;c=c+1)begin
       @(posedge clk);#1;
       if(fault)$fatal(1,"fault at PC=%h",fault_pc);
       if(!busy)disable run;
     end
     $fatal(1,"Mandelbrot execution timeout");
   end
   perf_enable=0;
   for(integer i=0;i<2*PIXELS;i=i+1)
     if(dut.data_ram.memory[i]!==expected[i])
       $fatal(1,"word %0d got=%h expected=%h",i,dut.data_ram.memory[i],expected[i]);
   $writememh(FRAME_FILE,dut.data_ram.memory,0,2*PIXELS-1);
   $display("PASS: Mandelbrot %0dx%0d: %0d RGB pixels and iteration counts match",WIDTH,HEIGHT,PIXELS);
   $display("COUNTERS cycles=%0d instructions=%0d active_lane_instructions=%0d scheduler_idle=%0d memory_blocked=%0d",
     total_cycles,instructions_issued,active_lane_instructions,scheduler_idle_cycles,memory_blocked_cycles);
   $finish;
 end
endmodule
