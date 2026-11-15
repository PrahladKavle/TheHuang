// Custom-ISA single-cycle simulation core. ROM is asynchronous.
// Launch only inactive warps; launch_valid pauses instruction issue for that cycle.
module minimal_core #(
    parameter integer LANES=8, WARPS=4,
    parameter integer WARP_ID_WIDTH=(WARPS>1)?$clog2(WARPS):1,
    parameter integer PROGRAM_DEPTH=256, MASK_STACK_DEPTH=8,
    parameter INIT_FILE=""
) (
    input wire clk, reset,
    input wire perf_clear, perf_enable,
    output wire [63:0] total_cycles, instructions_issued, active_lane_instructions,
    output wire [63:0] scheduler_idle_cycles, memory_blocked_cycles,

    input wire launch_valid,
    input wire [WARP_ID_WIDTH-1:0] launch_warp_id,
    input wire [31:0] launch_pc,
    input wire [LANES-1:0] launch_mask,
    input wire [31:0] launch_args [0:3],
    output wire [WARPS-1:0] running,
    output wire busy,
    output reg fault,
    output reg [31:0] fault_pc,
    // Read-only register observation for simulation/host integration.
    input wire [WARP_ID_WIDTH-1:0] debug_warp_id,
    input wire [3:0] debug_register,
    output wire [31:0] debug_data [0:LANES-1],
    output wire memory_request_valid,
    input wire memory_request_ready,
    output wire [31:0] memory_address, memory_write_data,
    output wire memory_store,
    input wire memory_response_valid,
    output wire memory_response_ready,
    input wire [31:0] memory_read_data,
    input wire memory_error
);
    reg [31:0] warp_args [0:WARPS-1][0:3];
    wire [WARP_ID_WIDTH-1:0] selected_warp;
    wire barrier_active,spawn_busy,spawn_launch_valid;
    wire [WARP_ID_WIDTH-1:0] spawn_warp;
    wire [31:0] spawn_pc,spawn_args[0:3],parent_args[0:3];
    wire [LANES-1:0] spawn_mask;
    wire host_launch_error=launch_valid && (barrier_active || spawn_busy || launch_warp_id>=WARPS || running[launch_warp_id]);
    wire context_launch_valid=!reset && !fault && !host_launch_error && (launch_valid || spawn_launch_valid);
    wire [WARP_ID_WIDTH-1:0] context_warp=spawn_launch_valid ? spawn_warp : launch_warp_id;
    wire [31:0] context_pc=spawn_launch_valid ? spawn_pc : launch_pc;
    wire [LANES-1:0] context_mask=spawn_launch_valid ? spawn_mask : launch_mask;
    wire [31:0] context_args[0:3];
    for(genvar a=0;a<4;a=a+1) begin: launch_arguments
        assign context_args[a]=spawn_launch_valid ? spawn_args[a] : launch_args[a];
        assign parent_args[a]=warp_args[selected_warp][a];
    end
    wire issue_valid, issue_accept;
    wire [WARPS-1:0] ready_mask, memory_wait, barrier_wait;
    wire [31:0] pc [0:WARPS-1];
    wire [LANES-1:0] active_mask [0:WARPS-1];
    wire [31:0] instruction, immediate, next_pc;
    wire instruction_valid;
    wire [5:0] opcode;
    wire [3:0] rd, rs1, rs2, alu_ctrl;
    wire illegal_instruction, register_write, use_immediate;
    wire branch, branch_any, warp_finish, memory_read, memory_write;
    wire [1:0] immediate_mode;
    wire supported=(opcode<=26);
    // A memory context per resident warp/lane permits other warps to issue
    // memory while earlier transactions are pending. One shared memory port.
    localparam integer CLIENTS=WARPS*LANES;
    wire [CLIENTS-1:0] lsu_ready, req_valid, req_ready, req_store;
    wire [CLIENTS-1:0] resp_valid, resp_ready, comp_valid, comp_error, comp_we;
    wire [31:0] req_address [0:CLIENTS-1], req_data [0:CLIENTS-1];
    wire [31:0] comp_data [0:CLIENTS-1];
    wire [3:0] comp_rd [0:CLIENTS-1];
    wire [WARP_ID_WIDTH-1:0] comp_warp [0:CLIENTS-1];
    wire [31:0] response_data;
    wire response_error;
    reg [LANES-1:0] pending [0:WARPS-1];
    reg [31:0] memory_pc [0:WARPS-1];
    reg [WARPS-1:0] wait_clear;
    wire [WARPS-1:0] wait_set=(issue_accept && (memory_read || memory_write))
        ? ({{(WARPS-1){1'b0}},1'b1} << selected_warp) : {WARPS{1'b0}};
    integer completion_index;
    reg memory_slots_ready;
    always @(*) begin
        completion_index=-1;
        for(integer c=0;c<CLIENTS;c=c+1)
            if(completion_index==-1 && comp_valid[c]) completion_index=c;
        memory_slots_ready=1;
        for(integer l=0;l<LANES;l=l+1)
            if(!lsu_ready[selected_warp*LANES+l]) memory_slots_ready=0;
        wait_clear=0;
        if(completion_index!=-1 && !fault && !reset)
            if(pending[completion_index/LANES] == ({{(LANES-1){1'b0}},1'b1} << (completion_index%LANES)))
                wait_clear[completion_index/LANES]=1;
    end
    // Completion gets the single register write port before arithmetic issue.
    wire [31:0] lane_source [0:LANES-1];
    wire [LANES-1:0] predicates, restored_mask;
    wire [31:0] vote_mask;
    ballot_unit #(.LANES(LANES)) votes (
        .active_mask(active_mask[selected_warp]),.predicates(predicates),.vote_mask(vote_mask));
    wire stack_error;
    wire mask_update=(opcode==15 || opcode==17 || opcode==18);
    wire [LANES-1:0] updated_mask=(opcode==15) ? (active_mask[selected_warp] & predicates)
        : ((opcode==17) ? restored_mask : lane_source[0]);
    mask_stack #(.WARPS(WARPS),.LANES(LANES),.DEPTH(MASK_STACK_DEPTH)) masks (
        .clk(clk),.reset(reset),.clear_valid(context_launch_valid),.clear_warp_id(context_warp),
        .warp_id(selected_warp),.push(opcode==16),.pop(opcode==17),.commit(issue_accept),
        .current_mask(active_mask[selected_warp]),.restored_mask(restored_mask),.stack_error(stack_error));
    wire invalid_special=(opcode==14) && !(immediate<=3 || (immediate>=16 && immediate<=19));
    always @(posedge clk) begin
        for(integer w=0;w<WARPS;w=w+1)
            for(integer a=0;a<4;a=a+1)
                if(reset) warp_args[w][a]<=0;
                else if(context_launch_valid && context_warp==w) warp_args[w][a]<=context_args[a];
    end
    wire [31:0] spawn_targets=lane_source[0];
    wire [31:0] spawn_entry_pc=pc[selected_warp]+32'd4+(immediate<<2);
    wire spawn_error=(opcode==23) && (barrier_active || ((spawn_targets >> WARPS)!=0)
        || ((spawn_targets & running)!=0) || (spawn_entry_pc[1:0]!=0)
        || ((spawn_entry_pc >> 2)>=PROGRAM_DEPTH));
    wire [WARPS-1:0] barrier_set,barrier_clear;
    barrier_controller #(.WARPS(WARPS)) barriers(
        .clk(clk),.reset(reset),.running(running),
        .arrive_valid(issue_accept && opcode==24),.arrive_warp_id(selected_warp),
        .epoch_active(barrier_active),.wait_set(barrier_set),.wait_clear(barrier_clear));
    warp_spawn_controller #(.WARPS(WARPS),.LANES(LANES)) spawn_controller(
        .clk(clk),.reset(reset),.start(issue_accept && opcode==23),
        .target_mask(spawn_targets[WARPS-1:0]),.entry_pc(spawn_entry_pc),
        .parent_mask(active_mask[selected_warp]),.parent_args(parent_args),.busy(spawn_busy),
        .launch_valid(spawn_launch_valid),.launch_accept(context_launch_valid && spawn_launch_valid),
        .launch_warp_id(spawn_warp),.launch_pc(spawn_pc),.launch_mask(spawn_mask),.launch_args(spawn_args));
    wire attempt=issue_valid && !reset && !fault && !launch_valid && !spawn_busy && completion_index==-1;
    wire completion_accept=completion_index!=-1 && !fault && !reset;
    always @(posedge clk) begin
        for(integer w=0;w<WARPS;w=w+1) begin
            if(reset) begin pending[w]<=0; memory_pc[w]<=0; end
            else if(wait_set[w]) begin
                pending[w]<={LANES{1'b1}};
                memory_pc[w]<=pc[w];
            end else if(completion_accept && completion_index/LANES==w)
                pending[w][completion_index%LANES]<=0;
        end
    end
    assign issue_accept=attempt && instruction_valid && !illegal_instruction && supported && !invalid_special && !stack_error && !spawn_error && (!(memory_read || memory_write) || memory_slots_ready);
    assign busy=(|running) || spawn_busy;
    // Caller owns the measurement window. Fault freezes counters until clear/reset.
    performance_counters #(.LANES(LANES),.WARPS(WARPS)) counters (
        .clk(clk),.reset(reset),.clear(perf_clear),.enable(perf_enable && !fault),
        .issue_accept(issue_accept),.issued_active_mask(active_mask[selected_warp]),
        .running(running),.ready_mask(ready_mask),.memory_wait(memory_wait),
        .total_cycles(total_cycles),.instructions_issued(instructions_issued),
        .active_lane_instructions(active_lane_instructions),
        .scheduler_idle_cycles(scheduler_idle_cycles),.memory_blocked_cycles(memory_blocked_cycles));
    wire [WARPS-1:0] finish_mask=(issue_accept && warp_finish) ? ({{(WARPS-1){1'b0}},1'b1} << selected_warp) : {WARPS{1'b0}};
    always @(posedge clk) begin
        if(reset) begin fault<=0; fault_pc<=0; end
        else if(host_launch_error) begin
            fault<=1;fault_pc<=launch_pc;
        end else if(completion_accept && comp_error[completion_index]) begin
            fault<=1; fault_pc<=memory_pc[completion_index/LANES];
        end else if(attempt && (!instruction_valid || illegal_instruction || !supported || invalid_special || stack_error || spawn_error)) begin
            fault<=1; fault_pc<=pc[selected_warp];
        end
    end
    warp_scheduler #(.WARPS(WARPS)) scheduler(
        .clk(clk),.reset(reset),.ready_mask(ready_mask),.issue_accept(issue_accept),
        .selected_warp(selected_warp),.issue_valid(issue_valid));
    warp_state #(.WARPS(WARPS),.LANES(LANES)) state_store(
        .clk(clk),.reset(reset),.launch_valid(context_launch_valid),
        .launch_warp_id(context_warp),.launch_pc(context_pc),.launch_mask(context_mask),
        .issue_accept(issue_accept),.issue_warp_id(selected_warp),.issue_next_pc(next_pc),
        .mask_write_enable(mask_update),.issue_next_mask(updated_mask),
        .memory_wait_set(wait_set),.memory_wait_clear(wait_clear),
        .barrier_wait_set(barrier_set),.barrier_wait_clear(barrier_clear),
        .finish_mask(finish_mask),.pc(pc),.active_mask(active_mask),.running(running),
        .memory_wait(memory_wait),.barrier_wait(barrier_wait),.ready_mask(ready_mask));
    instruction_memory #(.DEPTH(PROGRAM_DEPTH),.INIT_FILE(INIT_FILE)) program_rom(
        .addr(pc[selected_warp]),.instruction(instruction),.instruction_valid(instruction_valid));
    instruction_decoder decoder(
        .instruction(instruction),.opcode(opcode),.rd(rd),.rs1(rs1),.rs2(rs2),
        .illegal_instruction(illegal_instruction),.register_write(register_write),
        .use_immediate(use_immediate),.alu_ctrl(alu_ctrl),.branch(branch),
        .branch_any(branch_any),.warp_finish(warp_finish),.immediate_mode(immediate_mode),
        .memory_read(memory_read),.memory_write(memory_write));
    immediate_generator immediates(.instruction(instruction),.immediate_mode(immediate_mode),.immediate(immediate));
    branch_unit #(.LANES(LANES)) branches(
        .pc(pc[selected_warp]),.immediate(immediate),.branch(branch),.branch_any(branch_any),
        .active_mask(active_mask[selected_warp]),.next_pc(next_pc));
    memory_arbiter #(.CLIENTS(CLIENTS)) arbiter(
        .clk(clk),.reset(reset),.client_request_valid(req_valid),.client_request_ready(req_ready),
        .client_address(req_address),.client_data(req_data),.client_store(req_store),
        .client_response_valid(resp_valid),.client_response_ready(resp_ready),
        .client_response_data(response_data),.client_response_error(response_error),
        .memory_request_valid(memory_request_valid),.memory_request_ready(memory_request_ready),
        .memory_address(memory_address),.memory_write_data(memory_write_data),.memory_store(memory_store),
        .memory_response_valid(memory_response_valid),.memory_response_ready(memory_response_ready),
        .memory_read_data(memory_read_data),.memory_error(memory_error));
    for(genvar l=0;l<LANES;l=l+1) begin: lanes
        wire [31:0] a,b,result;
        assign lane_source[l]=a;
        assign predicates[l]=(a!=0);
        wire [31:0] operand_b=use_immediate ? immediate : b;
        wire lane_completion=completion_accept && completion_index%LANES==l;
        reg [31:0] special_value;
        always @(*) begin
            special_value=0;
            case(immediate)
                0: special_value=l;
                1: special_value=selected_warp;
                2: special_value=LANES;
                3: special_value=WARPS;
                16,17,18,19: special_value=warp_args[selected_warp][immediate-16];
                default: special_value=0;
            endcase
        end
        wire [31:0] write_data=lane_completion ? comp_data[completion_index]
            : ((opcode==19) ? vote_mask : ((opcode==14) ? special_value : ((opcode==12 || opcode==13) ? immediate : result)));
        wire [WARP_ID_WIDTH-1:0] write_warp=lane_completion ? comp_warp[completion_index] : selected_warp;
        wire [3:0] write_rd=lane_completion ? comp_rd[completion_index] : rd;
        wire write_enable=lane_completion ? comp_we[completion_index]
            : (issue_accept && register_write && !memory_read && active_mask[selected_warp][l]);
        for(genvar w=0;w<WARPS;w=w+1) begin: memory_contexts
            localparam integer C=w*LANES+l;
            load_store_unit #(.WARPS(WARPS)) lsu(
                .clk(clk),.reset(reset),
                .issue_valid(issue_accept && (memory_read || memory_write) && selected_warp==(C/LANES)),
                .issue_ready(lsu_ready[C]),.lane_active(active_mask[selected_warp][l]),
                .issue_store(memory_write),.base_address(a),.offset(immediate),.store_data(b),
                .issue_warp_id(selected_warp),.issue_rd(rd),.busy(),
                .request_valid(req_valid[C]),.request_ready(req_ready[C]),
                .request_address(req_address[C]),.request_data(req_data[C]),.request_store(req_store[C]),
                .response_valid(resp_valid[C]),.response_ready(resp_ready[C]),
                .response_data(response_data),.response_error(response_error),
                .completion_valid(comp_valid[C]),.completion_ready(completion_accept && completion_index==C),
                .completion_error(comp_error[C]),.completion_write_enable(comp_we[C]),
                .completion_data(comp_data[C]),.completion_warp_id(comp_warp[C]),.completion_rd(comp_rd[C]));
        end
        register_file #(.WARPS(WARPS)) registers(
            .clk(clk),.read_warp_id(selected_warp),.write_warp_id(write_warp),
            .rs1(rs1),.rs2(rs2),.ws(write_rd),.w_data(write_data),
            .w_en(write_enable),
            .rs1_data(a),.rs2_data(b));
        alu arithmetic(.a(a),.b(operand_b),.ctrl(alu_ctrl),.result(result),.zero());
        // Observation port does not add a physical register-file write port.
        assign debug_data[l]=(debug_register==0) ? 32'd0 : registers.registers[debug_warp_id][debug_register];
    end
endmodule
