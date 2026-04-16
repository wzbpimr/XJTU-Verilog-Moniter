`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/16 09:11:08
// Design Name: 
// Module Name: logo_rom
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module logo_rom #(
    parameter INIT_FILE = "logo.txt" // 默认文件名，例化时可覆盖
)(
    input  wire        clk,      // 加入时钟以使用同步 BRAM (提高时序性能)
    input  wire [11:0] addr,     // 0 ~ 4095
    output reg  [11:0] color_out // 12-bit RGB
);

    // 声明深度为 4096，宽度为 12-bit 的存储器
    (* rom_style = "block" *) 
    reg [11:0] rom [0:4095];

    // 使用传入的参数名初始化 ROM
    initial begin
        $readmemh(INIT_FILE, rom);
    end

    // 使用同步读取机制 (这会导致 1 个时钟周期的延迟，我们在外层补偿)
    always @(posedge clk) begin
        color_out <= rom[addr];
    end

endmodule
