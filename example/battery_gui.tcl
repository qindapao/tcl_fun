#!/usr/bin/env wish9

# GUI程序优先用这个调用
# /opt/tcl9/bin/wish90.exe battery_gui.tcl
# 命令行程序优先用这个调用
# /opt/tcl9/bin/tclsh90.exe battery_gui.tcl
# 1. 加载核心和 tklib 2.0 扩展
# 如果这里报错，请检查你的 TCLLIBPATH 是否包含 tklib 的安装目录
package require Tk
package require canvas::gradient
package require autoscroll

# 设置窗口属性
wm title . "Tcl/Tk 9.0 + tklib 2.0 终极完美版"
wm geometry . 500x450
update

# 2. 核心过程：使用 tklib 的渐变引擎绘制电池
proc draw_fancy_battery {percent} {
    global bc
    # 清理旧画布内容
    $bc delete all
    
    # 绘制电池外壳 (深灰色)
    $bc create rectangle 10 20 410 120 -outline "#333333" -width 3
    $bc create rectangle 410 45 425 95 -fill "#333333" -outline "#333333"
    
    # 计算填充宽度 (最大 395 像素)
    set fill_w [expr {3.95 * $percent}]
    if {$fill_w < 2} { set fill_w 2 }
    
    # 颜色逻辑：电量高时绿变深绿，电量低时红变深红
    if {$percent > 20} {
        set c1 "#00FF00"; set c2 "#008800"
    } else {
        set c1 "#FF0000"; set c2 "#880000"
    }
    
    # 【调用 tklib 核心功能】：绘制渐变色块
    # -direction x 代表水平渐变
    ::canvas::gradient $bc 15 25 [expr {15 + $fill_w}] 115 \
        -direction x -color1 $c1 -color2 $c2
}

# 3. 界面布局
set f [frame .main]
pack $f -fill both -expand 1 -padx 20 -pady 10

label $f.title -text "Tcl 9.0 动力仪表盘" -font {Helvetica 14 bold}
pack $f.title -pady 10

# 画布设置
set bc [canvas $f.cvs -width 440 -height 140 -bg "#FFFFFF" -highlightthickness 1 -highlightbackground "#CCCCCC"]
pack $f.cvs -pady 10

# 4. 系统日志列表 (测试 autoscroll)
label $f.log_lbl -text "系统实时事件日志 (自动隐藏滚动条):"
pack $f.log_lbl -anchor w -pady {10 0}

frame $f.sw
listbox $f.sw.lb -height 6 -width 50 -borderwidth 1 -relief sunken
scrollbar $f.sw.sb -orient vertical -command [list $f.sw.lb yview]
$f.sw.lb configure -yscrollcommand [list $f.sw.sb set]

# 【调用 tklib 核心功能】：让滚动条在内容不足时自动消失
::autoscroll::autoscroll $f.sw.sb

pack $f.sw.sb -side right -fill y
pack $f.sw.lb -side left -fill both -expand 1
pack $f.sw -fill both -expand 1

# 5. 控制逻辑
set current_val 85
scale $f.scl -from 0 -to 100 -orient horizontal -length 400 -command {apply {v {
    # 更新电池图形
    draw_fancy_battery $v
    # 向列表框插入日志
    .main.sw.lb insert end "\[[clock format [clock seconds] -format %H:%M:%S]\] 状态更新: $v%"
    .main.sw.lb see end
}}}
$f.scl set $current_val
pack $f.scl -pady 10

# 退出按钮
button $f.btn -text "完美收工，关机睡觉！" -command { exit }
pack $f.btn -pady 10

# 初始化第一次绘制
draw_fancy_battery $current_val

