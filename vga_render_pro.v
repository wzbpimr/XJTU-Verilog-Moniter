`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/16 09:09:37
// Design Name: 
// Module Name: vga_render_pro
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

module vga_render(
    input  wire clk,
    input  wire rst_n,
    input  wire btn_bright_up,
    input  wire btn_bright_down,
    input  wire [9:0] pix_x,
    input  wire [9:0] pix_y,
    input  wire video_on,
    
    input  wire [7:0]  cpu_cores,
    input  wire [7:0]  cpu_threads,
    input  wire [15:0] cpu_freq,
    input  wire [7:0]  cpu_usage,
    input  wire [7:0]  ram_total,
    input  wire [15:0] ram_used,
    input  wire [7:0]  ram_usage,
    
    output wire [3:0] vga_r,
    output wire [3:0] vga_g,
    output wire [3:0] vga_b
);

    // =========================================================
    // 1. 硬件亮度控制 (保持不变)
    // =========================================================
    reg [3:0] brightness = 4'd15;
    reg [19:0] btn_delay;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin brightness <= 4'd15; btn_delay <= 0; end 
        else begin
            if (btn_delay > 0) btn_delay <= btn_delay - 1'b1;
            else begin
                if (btn_bright_up && brightness < 4'd15) begin brightness <= brightness + 1'b1; btn_delay <= 20'd1000_000; end 
                else if (btn_bright_down && brightness > 4'd0) begin brightness <= brightness - 1'b1; btn_delay <= 20'd1000_000; end
            end
        end
    end

    // =========================================================
    // 2. 流水线时序对齐 (Pipeline Alignment) - 核心修复区！
    // =========================================================
    // 将所有的 VGA 扫描信号打一拍，延迟 1 个 100MHz 周期 (10ns)
    // 这刚好与 BRAM 的 1 拍读取延迟完美匹配
    reg [9:0] pix_x_d1;
    reg [9:0] pix_y_d1;
    reg       video_on_d1;

    always @(posedge clk) begin
        pix_x_d1    <= pix_x;
        pix_y_d1    <= pix_y;
        video_on_d1 <= video_on;
    end

    // =========================================================
    // 3. BRAM 寻址区 (必须使用原始未延迟的 pix_x, pix_y)
    // =========================================================
    localparam LOGO_SIZE = 64;
    localparam MARGIN    = 16;
    localparam TL_X = MARGIN;               localparam TL_Y = MARGIN;
    localparam TR_X = 640 - MARGIN - 64;    localparam TR_Y = MARGIN;
    localparam BL_X = MARGIN;               localparam BL_Y = 480 - MARGIN - 64;
    localparam BR_X = 640 - MARGIN - 64;    localparam BR_Y = 480 - MARGIN - 64;

    wire [11:0] addr_tl = (pix_y - TL_Y) * LOGO_SIZE + (pix_x - TL_X);
    wire [11:0] addr_tr = (pix_y - TR_Y) * LOGO_SIZE + (pix_x - TR_X);
    wire [11:0] addr_bl = (pix_y - BL_Y) * LOGO_SIZE + (pix_x - BL_X);
    wire [11:0] addr_br = (pix_y - BR_Y) * LOGO_SIZE + (pix_x - BR_X);

    wire [11:0] color_tl, color_tr, color_bl, color_br;

    // ROM 读取自带 1 拍延迟，输出的 color 与下面的 pix_x_d1 刚好在同一个时钟边沿生效
    logo_rom #(.INIT_FILE("logo_tl.txt")) u_logo_tl (.clk(clk), .addr(addr_tl), .color_out(color_tl));
    logo_rom #(.INIT_FILE("logo_tr.txt")) u_logo_tr (.clk(clk), .addr(addr_tr), .color_out(color_tr));
    logo_rom #(.INIT_FILE("logo_bl.txt")) u_logo_bl (.clk(clk), .addr(addr_bl), .color_out(color_bl));
    logo_rom #(.INIT_FILE("logo_br.txt")) u_logo_br (.clk(clk), .addr(addr_br), .color_out(color_br));

    // =========================================================
    // 4. UI 渲染区 (必须全部使用延迟对齐后的 pix_x_d1, pix_y_d1)
    // =========================================================
    localparam BAR_X_START = 150;
    localparam BAR_WIDTH   = 400;
    localparam BAR_HEIGHT  = 40;
    localparam CPU_Y_START = 150;
    localparam RAM_Y_START = 300;
    localparam TEXT_CPU_Y  = 130; 
    localparam TEXT_RAM_Y  = 280;

    // --- 四角区域判定 ---
    wire in_tl = (pix_x_d1 >= TL_X && pix_x_d1 < TL_X + LOGO_SIZE && pix_y_d1 >= TL_Y && pix_y_d1 < TL_Y + LOGO_SIZE);
    wire in_tr = (pix_x_d1 >= TR_X && pix_x_d1 < TR_X + LOGO_SIZE && pix_y_d1 >= TR_Y && pix_y_d1 < TR_Y + LOGO_SIZE);
    wire in_bl = (pix_x_d1 >= BL_X && pix_x_d1 < BL_X + LOGO_SIZE && pix_y_d1 >= BL_Y && pix_y_d1 < BL_Y + LOGO_SIZE);
    wire in_br = (pix_x_d1 >= BR_X && pix_x_d1 < BR_X + LOGO_SIZE && pix_y_d1 >= BR_Y && pix_y_d1 < BR_Y + LOGO_SIZE);

    // --- 进度条判定 ---
    wire [7:0] safe_cpu = (cpu_usage > 100) ? 8'd100 : cpu_usage;
    wire [7:0] safe_ram = (ram_usage > 100) ? 8'd100 : ram_usage;
    wire [9:0] cpu_bar_len = {safe_cpu, 2'b00}; 
    wire [9:0] ram_bar_len = {safe_ram, 2'b00};

    wire in_cpu_border = (pix_x_d1 >= BAR_X_START-2 && pix_x_d1 <= BAR_X_START+BAR_WIDTH+2 && pix_y_d1 >= CPU_Y_START-2 && pix_y_d1 <= CPU_Y_START+BAR_HEIGHT+2);
    wire in_ram_border = (pix_x_d1 >= BAR_X_START-2 && pix_x_d1 <= BAR_X_START+BAR_WIDTH+2 && pix_y_d1 >= RAM_Y_START-2 && pix_y_d1 <= RAM_Y_START+BAR_HEIGHT+2);
    wire in_cpu_bar = (pix_x_d1 >= BAR_X_START && pix_x_d1 < BAR_X_START + cpu_bar_len && pix_y_d1 >= CPU_Y_START && pix_y_d1 < CPU_Y_START + BAR_HEIGHT);
    wire in_ram_bar = (pix_x_d1 >= BAR_X_START && pix_x_d1 < BAR_X_START + ram_bar_len && pix_y_d1 >= RAM_Y_START && pix_y_d1 < RAM_Y_START + BAR_HEIGHT);

    // --- 文字 BCD 提取与映射 ---
    wire [7:0] ram_used_gb = ram_used >> 10;
    wire [3:0] c_c1=(cpu_cores/10)%10; wire [3:0] c_c0=cpu_cores%10; wire [3:0] c_t1=(cpu_threads/10)%10; wire [3:0] c_t0=cpu_threads%10;
    wire [3:0] c_f3=(cpu_freq/1000)%10; wire [3:0] c_f2=(cpu_freq/100)%10; wire [3:0] c_f1=(cpu_freq/10)%10; wire [3:0] c_f0=cpu_freq%10;
    wire [3:0] c_u2=(safe_cpu/100)%10; wire [3:0] c_u1=(safe_cpu/10)%10; wire [3:0] c_u0=safe_cpu%10;
    wire [3:0] r_u1=(ram_used_gb/10)%10; wire [3:0] r_u0=ram_used_gb%10; wire [3:0] r_t1=(ram_total/10)%10; wire [3:0] r_t0=ram_total%10;
    wire [3:0] r_p2=(safe_ram/100)%10; wire [3:0] r_p1=(safe_ram/10)%10; wire [3:0] r_p0=safe_ram%10;

    wire in_cpu_text = (pix_x_d1 >= BAR_X_START && pix_x_d1 < BAR_X_START + 27*8) && (pix_y_d1 >= TEXT_CPU_Y && pix_y_d1 < TEXT_CPU_Y + 16);
    wire in_ram_text = (pix_x_d1 >= BAR_X_START && pix_x_d1 < BAR_X_START + 22*8) && (pix_y_d1 >= TEXT_RAM_Y && pix_y_d1 < TEXT_RAM_Y + 16);
    wire [4:0] char_index = (pix_x_d1 - BAR_X_START) >> 3;

    reg [7:0] target_char;
    always @(*) begin
        target_char = 8'h20;
        if (in_cpu_text) begin
            case(char_index)
                0: target_char=8'h43; 1: target_char=8'h50; 2: target_char=8'h55; 
                6: target_char=8'h30+c_c1; 7: target_char=8'h30+c_c0; 8: target_char=8'h43; 
                9: target_char=8'h30+c_t1; 10: target_char=8'h30+c_t0; 11: target_char=8'h54; 
                14: target_char=8'h30+c_f3; 15: target_char=8'h30+c_f2; 16: target_char=8'h30+c_f1; 17: target_char=8'h30+c_f0; 
                18: target_char=8'h4D; 19: target_char=8'h48; 20: target_char=8'h7A; 
                23: target_char=(c_u2==0)?8'h20:8'h30+c_u2; 24: target_char=8'h30+c_u1; 25: target_char=8'h30+c_u0; 26: target_char=8'h25; 
            endcase
        end else if (in_ram_text) begin
            case(char_index)
                0: target_char=8'h52; 1: target_char=8'h41; 2: target_char=8'h4D; 
                6: target_char=8'h30+r_u1; 7: target_char=8'h30+r_u0; 8: target_char=8'h47; 9: target_char=8'h42; 10: target_char=8'h2F; 
                11: target_char=8'h30+r_t1; 12: target_char=8'h30+r_t0; 13: target_char=8'h47; 14: target_char=8'h42; 
                18: target_char=(r_p2==0)?8'h20:8'h30+r_p2; 19: target_char=8'h30+r_p1; 20: target_char=8'h30+r_p0; 21: target_char=8'h25; 
            endcase
        end
    end

    wire [3:0] font_row = in_cpu_text ? (pix_y_d1 - TEXT_CPU_Y) : (pix_y_d1 - TEXT_RAM_Y);
    wire [2:0] font_col = (pix_x_d1 - BAR_X_START) & 3'b111; 
    wire [7:0] font_row_data;
    mini_font_rom u_font (.char_code(target_char), .row(font_row), .row_data(font_row_data));
    wire text_pixel_on = font_row_data[7 - font_col]; 

    // --- 背景特效计算 ---
    wire is_grid = (pix_x_d1[5:0] == 0) || (pix_y_d1[5:0] == 0); 
    wire [3:0] bg_gradient_b = pix_y_d1[8:6] + 4'd2; 

    // --- 渐变色计算 ---
    // 由于使用了 pix_x_d1，当 in_cpu_bar 成立时，pix_x_d1 必然 >= BAR_X_START。
    // 因此这里绝对不可能再发生数学下溢出（Underflow）！
    wire [8:0] x_rel = pix_x_d1 - BAR_X_START; 
    wire [4:0] calc_r = (x_rel >> 4); 
    wire [3:0] grad_r = (calc_r > 15) ? 4'd15 : calc_r[3:0]; 
    wire [3:0] grad_g = 4'd15 - grad_r;

    // =========================================================
    // 5. 像素混合器 (Z-Index)
    // =========================================================
    reg [3:0] raw_r, raw_g, raw_b;

    always @(*) begin
        if (!video_on_d1) begin // 必须使用延迟后的有效信号
            raw_r = 4'h0; raw_g = 4'h0; raw_b = 4'h0;
        end
        else if ((in_cpu_text || in_ram_text) && text_pixel_on) begin
            raw_r = 4'hF; raw_g = 4'hF; raw_b = 4'hF;
        end
        else if (in_cpu_bar || in_ram_bar) begin
            raw_r = grad_r; raw_g = grad_g; raw_b = 4'h0; // 这里的红色溢出 Bug 已彻底修复
        end
        else if (in_cpu_border || in_ram_border) begin
            raw_r = 4'h0; raw_g = 4'h8; raw_b = 4'hF;
        end
        // Logo 色键透明混合 (如果你的背景是白的，把 12'h000 改为 12'hFFF)
        else if (in_tl && color_tl != 12'h000) begin
            raw_r = color_tl[11:8]; raw_g = color_tl[7:4]; raw_b = color_tl[3:0];
        end
        else if (in_tr && color_tr != 12'h000) begin
            raw_r = color_tr[11:8]; raw_g = color_tr[7:4]; raw_b = color_tr[3:0];
        end
        else if (in_bl && color_bl != 12'h000) begin
            raw_r = color_bl[11:8]; raw_g = color_bl[7:4]; raw_b = color_bl[3:0];
        end
        else if (in_br && color_br != 12'h000) begin
            raw_r = color_br[11:8]; raw_g = color_br[7:4]; raw_b = color_br[3:0];
        end
        else if (is_grid) begin
            raw_r = 4'h2; raw_g = 4'h2; raw_b = 4'h5;
        end
        else begin
            raw_r = 4'h0; raw_g = 4'h0; raw_b = bg_gradient_b;
        end
    end

    // =========================================================
    // 6. 最终亮度输出
    // =========================================================
    wire [7:0] final_r = (raw_r * brightness);
    wire [7:0] final_g = (raw_g * brightness);
    wire [7:0] final_b = (raw_b * brightness);

    assign vga_r = final_r[7:4];
    assign vga_g = final_g[7:4];
    assign vga_b = final_b[7:4];

endmodule