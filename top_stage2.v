`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/09 14:33:05
// Design Name: 
// Module Name: top_stage2
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

module top_stage2(
    input  wire        clk,        // 系统时钟 100MHz
    input  wire        rst_n,      // 异步复位 (建议绑定拨码开关)
    
    // --- 通信与控制输入 ---
    input  wire        uart_rx_i,  // 串口接收 (USB-UART RX)
    input  wire [1:0]  sw,         // 拨码开关 (用于切换数码管显示内容)
    input  wire        btn_up,     // 按键：亮度加 (建议绑定 BTNU)
    input  wire        btn_down,   // 按键：亮度减 (建议绑定 BTND)
    
    // --- 状态指示与数码管 ---
    output wire [15:0] led,        // 状态指示灯
    output wire [3:0]  sm_wei,     // 数码管位选
    output wire [7:0]  sm_duan,    // 数码管段选
    
    // --- VGA 物理输出 ---
    output wire [3:0]  vga_r,      // VGA 红色 (4-bit)
    output wire [3:0]  vga_g,      // VGA 绿色 (4-bit)
    output wire [3:0]  vga_b,      // VGA 蓝色 (4-bit)
    output wire        vga_hsync,  // VGA 行同步
    output wire        vga_vsync   // VGA 场同步
);

    // =========================================================
    // 内部连线定义
    // =========================================================
    wire [7:0]  rx_data_w;
    wire        rx_done_w;
    wire        update_pulse_w;
    
    // 系统参数线
    wire [7:0]  cpu_cores_w, cpu_threads_w, cpu_usage_w, cpu_temp_w;
    wire [15:0] cpu_freq_w, ram_used_w;
    wire [7:0]  ram_total_w, ram_usage_w;
    
    // VGA 时序线
    wire [9:0]  pix_x_w;
    wire [9:0]  pix_y_w;
    wire        video_on_w;

    // =========================================================
    // 1. 底层 UART 接收
    // =========================================================
    uart_rx u_uart_rx (
        .clk        (clk),
        .rst_n      (rst_n),
        .uart_rx_i  (uart_rx_i),
        .rx_data_o  (rx_data_w),
        .rx_done    (rx_done_w)
    );

    // =========================================================
    // 2. 数据帧协议解析
    // =========================================================
    data_parser u_data_parser (
        .clk             (clk),
        .rst_n           (rst_n),
        .rx_data         (rx_data_w),
        .rx_done         (rx_done_w),
        .cpu_cores_out   (cpu_cores_w),     .cpu_threads_out (cpu_threads_w),
        .cpu_freq_out    (cpu_freq_w),      .cpu_usage_out   (cpu_usage_w),
        .cpu_temp_out    (cpu_temp_w),      .ram_total_out   (ram_total_w),
        .ram_used_out    (ram_used_w),      .ram_usage_out   (ram_usage_w),
        .update_pulse    (update_pulse_w)
    );

    // =========================================================
    // 3. VGA 时序发生器
    // =========================================================
    vga_timing u_vga_timing (
        .clk_100m (clk),
        .rst_n    (rst_n),
        .h_sync   (vga_hsync),
        .v_sync   (vga_vsync),
        .pix_x    (pix_x_w),
        .pix_y    (pix_y_w),
        .video_on (video_on_w)
    );

    // =========================================================
    // 4. VGA 赛博朋克渲染器
    // =========================================================
    vga_render u_vga_render (
        .clk             (clk),
        .rst_n           (rst_n),
        .btn_bright_up   (btn_up),       // 传入按键
        .btn_bright_down (btn_down),     // 传入按键
        .pix_x           (pix_x_w),
        .pix_y           (pix_y_w),
        .video_on        (video_on_w),

        .cpu_cores       (cpu_cores_w),
        .cpu_threads     (cpu_threads_w),
        .cpu_freq        (cpu_freq_w),
        .ram_total       (ram_total_w),
        .ram_used        (ram_used_w),


        .cpu_usage       (cpu_usage_w),  // 传入 CPU 占用率控制柱状图长度
        .ram_usage       (ram_usage_w),  // 传入 RAM 占用率控制柱状图长度
        .vga_r           (vga_r),
        .vga_g           (vga_g),
        .vga_b           (vga_b)
    );

    // =========================================================
    // 5. 调试逻辑保留 (数码管与 LED)
    // =========================================================
    assign led[15] = rst_n; // 复位存活指示灯
    
    // 每成功解析1帧翻转一次，证明通信正常
    reg frame_toggle; 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) frame_toggle <= 1'b0;
        else if (update_pulse_w) frame_toggle <= ~frame_toggle;
    end
    assign led[13] = frame_toggle;
    assign led[12:0] = 13'd0;

    // 数码管显示选择逻辑
    reg [15:0] seg_data_reg;
    always @(posedge clk) begin
        case (sw)
            // 模式 10：左边显示 CPU 使用率 (Hex)，右边显示 RAM 使用率 (Hex)
            2'b10: seg_data_reg <= {cpu_usage_w, ram_usage_w};
            // 其他模式默认显示 CPU 频率
            default: seg_data_reg <= cpu_freq_w;
        endcase
    end

    seg_display u_seg_display (
        .clk      (clk),
        .data     (seg_data_reg),
        .point    (4'b0000),
        .sm_wei   (sm_wei),
        .sm_duan  (sm_duan)
    );

endmodule
