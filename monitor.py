import serial
import psutil
import time
import wmi

# ================= 配置区 =================
COM_PORT = 'COM8'     # 连板子的时候修改此端口
BAUD_RATE = 115200
UPDATE_RATE = 0.5     
# ==========================================

print("正在初始化 Windows 性能计数器 (WMI PerfData)...")
try:
    w = wmi.WMI()
    # 1. 获取 CPU 的基准物理频率 (Base Clock)
    # 这个值是恒定的，比如 2500 (对应 2.5GHz)
    cpu_base_clock = int(w.Win32_Processor()[0].MaxClockSpeed)
    wmi_perf_available = True
    print(f"初始化成功！检测到 CPU 基准频率: {cpu_base_clock} MHz")
except Exception as e:
    wmi_perf_available = False
    cpu_base_clock = 3000 # 兜底值
    print(f"WMI 初始化失败: {e}")

# ================= 串口初始化 (测试时不连板子可注释掉) =================
ser = None
try:
    ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=1)
    print(f"成功打开串口: {COM_PORT} @ {BAUD_RATE} bps")
except Exception as e:
    print(f"警告：串口打开失败 ({e})。进入纯软件测试模式！")
# ======================================================================

cpu_cores = psutil.cpu_count(logical=False)
cpu_threads = psutil.cpu_count(logical=True)
ram_total_gb = int(psutil.virtual_memory().total / (1024 ** 3))

def get_cpu_temp():
    if hasattr(psutil, "sensors_temperatures"):
        temps = psutil.sensors_temperatures()
        if "coretemp" in temps:
            return int(temps["coretemp"][0].current)
        elif "k10temp" in temps: 
            return int(temps["k10temp"][0].current)
    return 0 

def get_taskmanager_freq():
    """终极算法：复刻任务管理器的频率计算公式"""
    if wmi_perf_available:
        try:
            # 2. 读取 Windows 内核性能计数器中的“_Total”总处理器性能百分比
            # 这个值会非常细腻地跳动，比如 123%, 85%, 168%
            perf_info = w.Win32_PerfFormattedData_Counters_ProcessorInformation(Name="_Total")
            if perf_info:
                perf_percent = int(perf_info[0].PercentProcessorPerformance)
                
                # 3. 实时频率 = 基准频率 * (性能百分比 / 100)
                real_freq = int(cpu_base_clock * (perf_percent / 100.0))
                return real_freq
        except Exception:
            pass
            
    # 如果计数器崩溃，退回 psutil
    cpu_freq_info = psutil.cpu_freq()
    return int(cpu_freq_info.current) if cpu_freq_info else 0

print("-" * 50)
print("开始采集真实动态数据... (按 Ctrl+C 停止)")
print("-" * 50)

while True:
    try:
        start_time = time.time()

        # --- 1. 获取核心数据 ---
        cpu_freq_mhz = get_taskmanager_freq() # 使用终极算法
        cpu_usage = int(psutil.cpu_percent(interval=None))
        cpu_temp = get_cpu_temp()

        mem_info = psutil.virtual_memory()
        ram_used_mb = int(mem_info.used / (1024 ** 2))
        ram_usage = int(mem_info.percent)

        # 打印调试信息，你可以直接对比任务管理器
        print(f"动态监测 -> CPU: {cpu_usage:02d}% | 频率: {cpu_freq_mhz} MHz | RAM: {ram_usage:02d}% ({ram_used_mb} MB) | Temp: {cpu_temp}")

        # --- 2. 组装并发送数据 (如果串口打开了) ---
        if ser and ser.is_open:
            cpu_freq_h = (cpu_freq_mhz >> 8) & 0xFF
            cpu_freq_l = cpu_freq_mhz & 0xFF
            ram_used_h = (ram_used_mb >> 8) & 0xFF
            ram_used_l = ram_used_mb & 0xFF

            frame = bytearray([
                0xAA, 0xBB,
                cpu_cores, cpu_threads,
                cpu_freq_h, cpu_freq_l,
                cpu_usage, cpu_temp,
                ram_total_gb,
                ram_used_h, ram_used_l,
                ram_usage,
                0x55, 0xCC
            ])
            ser.write(frame)

        # --- 3. 动态延时补偿 ---
        elapsed = time.time() - start_time
        sleep_time = UPDATE_RATE - elapsed
        if sleep_time > 0:
            time.sleep(sleep_time)

    except KeyboardInterrupt:
        print("\n停止发送。")
        break
    except Exception as e:
        print(f"\n发生错误: {e}")
        break

if ser and ser.is_open:
    ser.close()