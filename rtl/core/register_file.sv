module register_file #(
    parameter integer WARPS = 4,
    parameter integer WARP_ID_WIDTH = (WARPS > 1) ? $clog2(WARPS) : 1
) (
    input wire clk,
    input wire [3:0] rs1, // Read Address 1
    input wire [3:0] rs2, // Read Address 2
    input wire [3:0] ws, // Write Address
    input wire [31:0] w_data, //  Write Data
    input wire w_en, // Write Enable

    output reg [31:0] rs1_data, 
    output reg [31:0] rs2_data, 

    input wire [WARP_ID_WIDTH-1:0] read_warp_id,
    input wire [WARP_ID_WIDTH-1:0] write_warp_id
);
    reg [31:0] registers [0:WARPS-1][0:15];

    always @(posedge clk) begin
        if (w_en && ws != 4'b0) begin 
            registers[write_warp_id][ws] <= w_data;
        end
    end

    always @(*) begin
        rs1_data = (rs1 == 4'd0) ? 32'd0 : registers[read_warp_id][rs1];
        rs2_data = (rs2 == 4'd0) ? 32'd0 : registers[read_warp_id][rs2];
    end

endmodule