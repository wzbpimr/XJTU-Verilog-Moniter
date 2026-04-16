`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/09 11:23:07
// Design Name: 
// Module Name: uart_rx
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


module uart_rx(
    input  wire       clk,          // 系统时钟 100MHz
    input  wire       rst_n,        // 异步复位 (低电平有效)
    input  wire       uart_rx_i,    // 串口输入信号 RX
    output reg  [7:0] rx_data_o,    // 接收到的 8-bit 数据
    output reg        rx_done       // 接收完成标志，产生1个时钟周期的高电平脉冲
);

    // 参数定义：100MHz 时钟下，115200波特率的计数值
    // 100,000,000 / 115200 ≈ 868
    localparam BAUD_CNT_MAX = 13'd868;
    localparam BAUD_CNT_MID = 13'd434; // 半个波特率周期（用于定位到数据位中间）

    // 状态机定义
    localparam S_IDLE  = 3'd0; // 空闲状态
    localparam S_START = 3'd1; // 接收起始位
    localparam S_DATA  = 3'd2; // 接收8个数据位
    localparam S_STOP  = 3'd3; // 接收停止位

    reg [2:0]  state, next_state;
    reg [12:0] baud_cnt;       // 波特率计数器
    reg [2:0]  bit_cnt;        // 接收数据位计数器 (0~7)
    
    reg [7:0]  rx_data_temp;   // 数据接收移位寄存器

    // =========================================================
    // 1. 信号同步与下降沿检测 (防亚稳态处理) - 答辩亮点
    // =========================================================
    reg rx_d0, rx_d1, rx_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_d0 <= 1'b1;
            rx_d1 <= 1'b1;
            rx_d2 <= 1'b1;
        end else begin
            rx_d0 <= uart_rx_i; // 采样外部信号
            rx_d1 <= rx_d0;     // 打第一拍
            rx_d2 <= rx_d1;     // 打第二拍
        end
    end
    
    // 当上一拍是高电平，当前拍是低电平时，说明出现了下降沿（起始位特征）
    wire rx_fall = rx_d2 & (~rx_d1);

    // =========================================================
    // 2. 状态机跳转逻辑 (三段式状态机写法)
    // =========================================================
    // 状态寄存器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // 次态组合逻辑
    always @(*) begin
        next_state = state; // 默认保持当前状态
        case (state)
            S_IDLE: begin
                if (rx_fall) 
                    next_state = S_START;
            end
            S_START: begin
                // 在起始位中间点判断是否仍为低电平（过滤毛刺）
                if (baud_cnt == BAUD_CNT_MID) begin
                    if (rx_d1 == 1'b0) next_state = S_DATA;
                    else               next_state = S_IDLE; // 毛刺，回到空闲
                end
            end
            S_DATA: begin
                // 接收完 8 个 bit 且处于最后一个 bit 的中间时，准备进入停止位
                if (bit_cnt == 3'd7 && baud_cnt == BAUD_CNT_MAX)
                    next_state = S_STOP;
            end
            S_STOP: begin
                // 在停止位正中间完成整个接收周期，回到空闲
                if (baud_cnt == BAUD_CNT_MID)
                    next_state = S_IDLE;
            end
            default: next_state = S_IDLE;
        endcase
    end

    // =========================================================
    // 3. 状态机输出与计数逻辑
    // =========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt     <= 13'd0;
            bit_cnt      <= 3'd0;
            rx_data_temp <= 8'd0;
            rx_data_o    <= 8'd0;
            rx_done      <= 1'b0;
        end else begin
            rx_done <= 1'b0; // 默认拉低完成脉冲

            case (state)
                S_IDLE: begin
                    baud_cnt <= 13'd0;
                    bit_cnt  <= 3'd0;
                end
                
                S_START: begin
                    if (baud_cnt == BAUD_CNT_MID) begin
                        baud_cnt <= 13'd0; // 计数器清零，为接收第一个数据位对齐时间
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end
                
                S_DATA: begin
                    if (baud_cnt == BAUD_CNT_MAX) begin
                        baud_cnt <= 13'd0; // 计满一个波特率周期，清零
                        bit_cnt  <= bit_cnt + 1'b1;
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                    
                    // 在每个数据位的正中间进行采样
                    if (baud_cnt == BAUD_CNT_MID) begin
                        // UART 协议是低位先发 (LSB first)，所以新数据放在最高位，向右移位
                        rx_data_temp <= {rx_d1, rx_data_temp[7:1]}; 
                    end
                end
                
                S_STOP: begin
                    if (baud_cnt == BAUD_CNT_MID) begin
                        baud_cnt <= 13'd0;
                        rx_data_o <= rx_data_temp; // 输出稳定的数据
                        rx_done   <= 1'b1;         // 产生完成脉冲
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end
            endcase
        end
    end

endmodule