`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/09 12:06:41
// Design Name: 
// Module Name: seg_display
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


module seg_display(
    input clk,
    input [15:0] data,
    input [3:0] point,
    output [3:0] sm_wei,
    output [7:0] sm_duan
    );
    // --- 1. 分频模块 ---
    // 假设系统时钟为 100MHz，要得到 400Hz 的扫描频率：
    // 100,000,000 / 400 = 250,000 个时钟周期翻转一次
    // 实际上 clk_400Hz 翻转一次需要计数到 125,000 (半周期)
    integer clk_cnt = 0;
    reg clk_400Hz = 0;
    always@(posedge clk) begin
    // 这里以 100MHz 降频至 400Hz 为例，填入 124999
    if(clk_cnt == 124999) begin 
        clk_cnt <= 0;
        clk_400Hz <= ~clk_400Hz;
    end
    else
        clk_cnt <= clk_cnt + 1;
    end
    // --- 2. 位控制模块 (动态扫描) ---
    reg [3:0] wei_ctrl = 4'b0001;
    always@(posedge clk_400Hz) begin
    // 循环左移：0001 -> 0010 -> 0100 -> 1000 -> 0001
    // 这样可以依次点亮四个数码管
    wei_ctrl <= {wei_ctrl[2:0], wei_ctrl[3]}; 
end
    // --- 3. 段控制逻辑 (数据选择) ---
    reg [3:0] duan_ctrl;
    reg current_point;
    // 根据当前点亮的位，选择对应的 4 位数据进行译码
    always@(*) begin
        case(wei_ctrl)
            4'b0001: begin duan_ctrl = data[3:0]; current_point = point[0];  end// 显示第 0 位
            4'b0010: begin duan_ctrl = data[7:4]; current_point = point[1]; end// 显示第 1 位
            4'b0100: begin duan_ctrl = data[11:8]; current_point = point[2]; end// 显示第 2 位
            4'b1000: begin duan_ctrl = data[15:12];current_point = point[3]; end// 显示第 3 位
            default: begin duan_ctrl = 4'h0;current_point = 1'b0;end
        endcase
    end
    // --- 4. 七段译码器 ---
    reg [7:0] duan;
    always@(*) begin
        case(duan_ctrl)
            4'h0: duan = 8'b0011_1111; // 0 
            4'h1: duan = 8'b0000_0110; // 1
            4'h2: duan = 8'b0101_1011; // 2
            4'h3: duan = 8'b0100_1111; // 3
            4'h4: duan = 8'b0110_0110; // 4
            4'h5: duan = 8'b0110_1101; // 5
            4'h6: duan = 8'b0111_1101; // 6
            4'h7: duan = 8'b0000_0111; // 7
            4'h8: duan = 8'b0111_1111; // 8
            4'h9: duan = 8'b0110_1111; // 9
            4'ha: duan = 8'b0111_0111; // A
            4'hb: duan = 8'b0111_1100; // b
            4'hc: duan = 8'b0011_1001; // C
            4'hd: duan = 8'b0101_1110; // d
            4'he: duan = 8'b0111_1001; // E
            4'hf: duan = 8'b0111_0001; // F
            default: duan = 8'b0000_0000;
        endcase
        duan[7] = current_point;
    end

    // --- 5. 输出赋值 ---
    assign sm_wei = wei_ctrl;
    // 取反输出：通常开发板数码管是共阳极或通过反相器驱动，
    // 如果你的硬件是高电平点亮某一段，则不需要 ~
    assign sm_duan = duan;

endmodule
