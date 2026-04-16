`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/09 14:28:19
// Design Name: 
// Module Name: vga_timing
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


module vga_timing(
    input  wire clk_100m,    // 开发板 100MHz 时钟
    input  wire rst_n,
    output wire h_sync,      // 行同步
    output wire v_sync,      // 场同步
    output wire [9:0] pix_x, // 当前绘制的 X 坐标 (0~639)
    output wire [9:0] pix_y, // 当前绘制的 Y 坐标 (0~479)
    output wire video_on     // 显示有效区域标志 (为1时才能输出颜色)
);

    // --- 1. 时钟分频：100MHz 四分频得到 25MHz 像素时钟 ---
    reg [1:0] clk_div;
    wire clk_25m = (clk_div == 2'b11); // 每4个周期产生一个脉冲
    always @(posedge clk_100m or negedge rst_n) begin
        if(!rst_n) clk_div <= 2'd0;
        else       clk_div <= clk_div + 1'b1;
    end

    // --- 2. 640x480 @ 60Hz 工业标准参数 ---
    localparam H_DISPLAY = 640, H_FRONT = 16,  H_SYNC = 96,  H_BACK = 48,  H_TOTAL = 800;
    localparam V_DISPLAY = 480, V_FRONT = 10,  V_SYNC = 2,   V_BACK = 33,  V_TOTAL = 525;

    reg [9:0] h_cnt, v_cnt;

    // --- 3. 扫描计数器 ---
    always @(posedge clk_100m or negedge rst_n) begin
        if(!rst_n) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else if(clk_25m) begin
            if(h_cnt == H_TOTAL - 1) begin
                h_cnt <= 10'd0;
                if(v_cnt == V_TOTAL - 1) v_cnt <= 10'd0;
                else                     v_cnt <= v_cnt + 1'b1;
            end else begin
                h_cnt <= h_cnt + 1'b1;
            end
        end
    end

    // --- 4. 同步信号与有效标志 ---
    // 根据 VGA 标准，Sync 信号在同步期内为低电平
    assign h_sync = ~((h_cnt >= H_DISPLAY + H_FRONT) && (h_cnt < H_DISPLAY + H_FRONT + H_SYNC));
    assign v_sync = ~((v_cnt >= V_DISPLAY + V_FRONT) && (v_cnt < V_DISPLAY + V_FRONT + V_SYNC));
    
    assign video_on = (h_cnt < H_DISPLAY) && (v_cnt < V_DISPLAY);
    
    assign pix_x = h_cnt;
    assign pix_y = v_cnt;

endmodule