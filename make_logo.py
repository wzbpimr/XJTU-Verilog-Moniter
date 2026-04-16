from PIL import Image
import os

# ================= 配置区 =================
# 在这里填入你要转换的 4 张图片的文件名（支持 jpg, png, jpeg）
# 即使你只有 1 张图，也可以把它填 4 次
IMAGE_FILES = [
    ("test_1.jpg", "logo_1.txt"), # 左上角
    ("test_2.jpg", "logo_2.txt"), # 右上角
    ("test_3.jpg", "logo_3.txt"), # 左下角
    ("test_4.jpg", "logo_4.txt"),  # 右下角
    ("XJTU.jpg", "logo_xjtu.txt")
]

# 是否开启“自动去除白色背景”功能
# 如果你的 Logo 本身就包含必须保留的大面积白色，请改为 False
REMOVE_WHITE_BG = True 
# ==========================================

def process_logo(input_path, output_path):
    if not os.path.exists(input_path):
        print(f"❌ 找不到图片: {input_path}")
        return

    try:
        # 1. 打开图片并强制转换为 RGBA (包含透明通道)
        img = Image.open(input_path).convert("RGBA")

        # 2. 等比例智能缩放 (Thumbnail)
        # 这会将图片的最长边缩放到 64，另一边按比例缩小
        img.thumbnail((64, 64), Image.Resampling.LANCZOS)

        # 3. 创建一个 64x64 的纯黑画布 (RGB: 0,0,0 代表 FPGA 中的透明)
        canvas = Image.new("RGBA", (64, 64), (0, 0, 0, 255))

        # 4. 计算居中粘贴的坐标
        offset_x = (64 - img.width) // 2
        offset_y = (64 - img.height) // 2

        # 5. 将缩放后的图片粘贴到纯黑画布的中心，使用自身的 Alpha 通道作为遮罩
        canvas.paste(img, (offset_x, offset_y), img)

        # 6. 像素级处理 (去背与位深转换)
        pixels = canvas.load()
        with open(output_path, "w") as f:
            for y in range(64):
                for x in range(64):
                    r, g, b, a = pixels[x, y]

                    # 规则 A：如果原来 PNG 是透明的 (Alpha < 128)，直接变纯黑
                    if a < 128:
                        r, g, b = 0, 0, 0
                    
                    # 规则 B：如果开启了去白底，且像素接近纯白 (RGB均大于 240)
                    elif REMOVE_WHITE_BG and r > 240 and g > 240 and b > 240:
                        r, g, b = 0, 0, 0

                    # 转换为 FPGA 支持的 12-bit 色彩 (RGB444)
                    r4 = r >> 4
                    g4 = g >> 4
                    b4 = b >> 4
                    
                    # 写入 3 位的十六进制字符串 (例如: F0A)
                    f.write(f"{r4:X}{g4:X}{b4:X}\n")
                    
        print(f"✅ 成功处理: {input_path} -> {output_path} (64x64)")

    except Exception as e:
        print(f"❌ 处理 {input_path} 时出错: {e}")

# 执行批量处理
print("开始生成 FPGA 字库文件...")
print("-" * 40)
for in_img, out_txt in IMAGE_FILES:
    process_logo(in_img, out_txt)
print("-" * 40)
print("全部完成！请将生成的 txt 文件放入 Vivado 工程目录下。")