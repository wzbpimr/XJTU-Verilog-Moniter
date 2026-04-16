`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/09 11:19:59
// Design Name: 
// Module Name: data_parser
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


module data_parser(
    input  wire        clk,          // 系统时钟 (100MHz)
    input  wire        rst_n,        // 异步复位 (低电平有效)
    
    // 连接到底层的 uart_rx 模块
    input  wire [7:0]  rx_data,      // 接收到的单字节数据
    input  wire        rx_done,      // 单字节接收完成脉冲
    
    // 输出给 VGA 或者 LED 的系统参数
    output reg  [7:0]  cpu_cores_out,
    output reg  [7:0]  cpu_threads_out,
    output reg  [15:0] cpu_freq_out,
    output reg  [7:0]  cpu_usage_out,
    output reg  [7:0]  cpu_temp_out,
    output reg  [7:0]  ram_total_out,
    output reg  [15:0] ram_used_out,
    output reg  [7:0]  ram_usage_out,
    
    output reg         update_pulse  // 一帧数据成功解析后的更新脉冲
);

    // --- 状态机定义 (One-Hot 编码或者参数化定义) ---
    localparam S_WAIT_H1  = 3'd0; // 等待包头1 (0xAA)
    localparam S_WAIT_H2  = 3'd1; // 等待包头2 (0xBB)
    localparam S_RCV_DATA = 3'd2; // 接收有效负载(Payload)
    localparam S_WAIT_T1  = 3'd3; // 等待包尾1 (0x55)
    localparam S_WAIT_T2  = 3'd4; // 等待包尾2 (0xCC)
    
    reg [2:0] state, next_state;
    
    // 计数器：记录当前正在接收第几个有效负载字节
    reg [3:0] byte_cnt; 
    
    // 内部暂存寄存器 (防止数据在未校验完成前污染输出)
    reg [7:0]  temp_cpu_cores;
    reg [7:0]  temp_cpu_threads;
    reg [15:0] temp_cpu_freq;
    reg [7:0]  temp_cpu_usage;
    reg [7:0]  temp_cpu_temp;
    reg [7:0]  temp_ram_total;
    reg [15:0] temp_ram_used;
    reg [7:0]  temp_ram_usage;

    // --- 状态机：状态跳转逻辑 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_WAIT_H1;
        end else if (rx_done) begin // 只有当新字节到来时才发生跳转
            case (state)
                S_WAIT_H1: begin
                    if (rx_data == 8'hAA) state <= S_WAIT_H2;
                    else                  state <= S_WAIT_H1;
                end
                
                S_WAIT_H2: begin
                    if (rx_data == 8'hBB) state <= S_RCV_DATA;
                    else if (rx_data == 8'hAA) state <= S_WAIT_H2; // 处理连续AA的意外
                    else                  state <= S_WAIT_H1;
                end
                
                S_RCV_DATA: begin
                    // payload共10个字节(索引从0到9)
                    if (byte_cnt == 4'd9) state <= S_WAIT_T1;
                    else                  state <= S_RCV_DATA;
                end
                
                S_WAIT_T1: begin
                    if (rx_data == 8'h55) state <= S_WAIT_T2;
                    else                  state <= S_WAIT_H1; // 错误，重新开始
                end
                
                S_WAIT_T2: begin
                    if (rx_data == 8'hCC) state <= S_WAIT_H1; // 完整接收一帧，回到开头
                    else                  state <= S_WAIT_H1;
                end
                
                default: state <= S_WAIT_H1;
            endcase
        end
    end

    // --- 状态机：数据暂存与计数逻辑 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_cnt <= 4'd0;
            update_pulse <= 1'b0;
            // 初始化暂存器
            temp_cpu_cores <= 0; temp_cpu_threads <= 0; temp_cpu_freq <= 0;
            temp_cpu_usage <= 0; temp_cpu_temp <= 0; temp_ram_total <= 0;
            temp_ram_used <= 0; temp_ram_usage <= 0;
            // 初始化输出
            cpu_cores_out <= 0; cpu_threads_out <= 0; cpu_freq_out <= 0;
            cpu_usage_out <= 0; cpu_temp_out <= 0; ram_total_out <= 0;
            ram_used_out <= 0; ram_usage_out <= 0;
        end else begin
            update_pulse <= 1'b0; // 默认拉低脉冲
            
            if (rx_done) begin
                if (state == S_WAIT_H2 && rx_data == 8'hBB) begin
                    byte_cnt <= 4'd0; // 准备接收有效数据，计数器清零
                end 
                else if (state == S_RCV_DATA) begin
                    byte_cnt <= byte_cnt + 1'b1;
                    // 根据当前字节索引，存入对应的暂存寄存器
                    case (byte_cnt)
                        4'd0: temp_cpu_cores   <= rx_data;
                        4'd1: temp_cpu_threads <= rx_data;
                        4'd2: temp_cpu_freq[15:8] <= rx_data; // 高8位
                        4'd3: temp_cpu_freq[7:0]  <= rx_data; // 低8位
                        4'd4: temp_cpu_usage   <= rx_data;
                        4'd5: temp_cpu_temp    <= rx_data;
                        4'd6: temp_ram_total   <= rx_data;
                        4'd7: temp_ram_used[15:8] <= rx_data; // 高8位
                        4'd8: temp_ram_used[7:0]  <= rx_data; // 低8位
                        4'd9: temp_ram_usage   <= rx_data;
                        default: ; 
                    endcase
                end
                else if (state == S_WAIT_T2 && rx_data == 8'hCC) begin
                    // 校验尾部成功！证明这一帧数据完全可靠
                    // 将暂存器的数据批量写入输出寄存器
                    cpu_cores_out   <= temp_cpu_cores;
                    cpu_threads_out <= temp_cpu_threads;
                    cpu_freq_out    <= temp_cpu_freq;
                    cpu_usage_out   <= temp_cpu_usage;
                    cpu_temp_out    <= temp_cpu_temp;
                    ram_total_out   <= temp_ram_total;
                    ram_used_out    <= temp_ram_used;
                    ram_usage_out   <= temp_ram_usage;
                    
                    update_pulse <= 1'b1; // 产生一个时钟周期的高电平脉冲，通知VGA更新
                end
            end
        end
    end

endmodule