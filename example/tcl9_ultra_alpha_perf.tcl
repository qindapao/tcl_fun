#!/usr/bin/env wish9.0
package require Tk

# 1. 初始化界面
set cvs [canvas .c -width 500 -height 400 -bg "#222" -highlightthickness 0]
pack $cvs -fill both -expand 1

# 2. 【核心优化】：在全局作用域只创建一次「透明模板」
# 创建一个 100x100 的半透明黄色模板
set yellow_mask [image create photo -width 100 -height 100]
$yellow_mask put "#FFFF0080" -to 0 0 100 100

# 3. 绘制底层背景（模拟复杂工程图）
for {set i 0} {$i < 10} {incr i} {
    $cvs create rectangle [expr {$i*50}] 50 [expr {$i*50+40}] 350 -fill "#000088" -outline "#0000FF"
}

# 4. 【多次引用】：用同一个 image 句柄创建几千个对象（这里演示 50 个）
# 在 Tk 内部，这些对象都指向同一个内存地址 $yellow_mask，极省内存
for {set j 0} {$j < 50} {incr j} {
    set x [expr {rand() * 400}]
    set y [expr {rand() * 300}]
    # 所有的图形对象都引用同一个 image 变量
    $cvs create image $x $y -image $yellow_mask -tags "glitter"
}

# 5. 性能测试：让这堆透明方块飞起来
proc animate {} {
    global cvs
    foreach id [$cvs find withtag glitter] {
        $cvs move $id [expr {rand()*4-2}] [expr {rand()*4-2}]
    }
    after 20 animate
}

# 启动动画
animate

puts "单实例透明模板已就绪，内存占用极低。"

