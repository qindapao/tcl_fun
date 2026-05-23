#!/usr/bin/env wish9
package require Tk

# 窗口设置
wm title . "Tk 9.0 性能巅峰测试"
wm geometry . 500x350
. configure -bg "#222"

# 1. 创建 UI 基础
set f [frame .m -bg "#222"]
pack $f -fill both -expand 1 -padx 20 -pady 20

label $f.t -text "超流畅动力仪表 (对象重用模式)" -fg "white" -bg "#222" -font {Helvetica 14 bold}
pack $f.t -pady 10

# 2. 初始化画布
set cvs [canvas $f.c -width 400 -height 100 -bg "#333" -highlightthickness 0]
pack $f.c -pady 10

# 预先绘制所有静态对象（只画一次）
# 画电池外壳
$cvs create rectangle 5 5 385 95 -outline "#555" -width 3
# 画电池正极
$cvs create rectangle 385 30 395 70 -fill "#555" -outline ""

# 【关键点】：预先创建电量矩形，并给它一个唯一标签 "bar"
# 初始宽度设为 0
$cvs create rectangle 10 10 10 90 -fill "#00FF00" -outline "" -tags bar

# 3. 极速更新函数 (不再 delete，只改坐标和颜色)
proc fast_update {val} {
    global cvs last_val
    if {[info exists last_val] && $val == $last_val} return
    set last_val $val
    
    # 3.1 仅修改现有对象的坐标 (coords 速度极快)
    set x2 [expr {10 + (3.7 * $val)}]
    $cvs coords bar 10 10 $x2 90
    
    # 3.2 动态计算颜色
    set r [expr {int(255 * (100-$val)/100.0)}]
    set g [expr {int(255 * $val/100.0)}]
    set color [format "#%02x%02x00" $r $g]
    
    # 修改对象属性而不是重画
    $cvs itemconfigure bar -fill $color
    
    # 3.3 异步更新文字 (避免阻塞 UI)
    .m.info configure -text "当前负载: $val %"
}

# 4. 信息展示
label $f.info -text "当前负载: 0 %" -fg "#00FF00" -bg "#222" -font {Courier 12 bold}
pack $f.info -pady 5

# 5. 控制滑块 (设置 -repeatinterval 提高响应)
scale $f.s -from 0 -to 100 -orient horizontal -length 400 \
    -bg "#222" -fg "white" -highlightthickness 0 \
    -showvalue 0 -command fast_update
$f.s set 80
pack $f.s -pady 10

button $f.b -text "完美谢幕" -highlightthickness 0 -command { exit }
pack $f.b -pady 10

# 初始触发
fast_update 80

