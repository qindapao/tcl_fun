#!/usr/bin/env tclsh9

package require json
package require cmdline

# 模拟一个 JSON 数据
set raw_json {{"status": "success", "msg": "Tcl 9.0 电池已就绪"}}
set d [json::json2dict $raw_json]

puts "消息: [dict get $d msg]"
puts "库路径: [info library]"
puts "已加载 JSON 库位置: [package ifneeded json [package present json]]"


# --- 你的工具库过程 ---

# 过程 A: 计算百分比
# 参数: current (当前电量), total (满电量)
proc calc_battery_percent {current total} {
    if {$total == 0} { return 0 }
    set res [expr {($current * 100.0) / $total}]
    return [format "%.2f%%" $res]
}

# 过程 B: 模拟从硬件读取 JSON 原始数据
# 参数: device_id
proc get_raw_hardware_data {device_id} {
    # 模拟一个复杂的 JSON 返回
    return "{\"id\": \"$device_id\", \"volt\": 12.5, \"curr\": 4500, \"full\": 5000}"
}

# 过程 C: 业务主逻辑
proc process_battery_status {id} {
    set json_str [get_raw_hardware_data $id]
    set data [json::json2dict $json_str]
    
    set c [dict get $data curr]
    set f [dict get $data full]
    
    set p [calc_battery_percent $c $f]
    puts "设备 $id 的当前电量百分比为: $p"
}

# --- 调用演示 ---
process_battery_status "BAT_001"

