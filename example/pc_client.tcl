# xx@DESKTOP-0KALMAH UCRT64 /d/code/pure_tcl# /opt/tcl9/bin/tclsh90.exe arm_server.tcl &
# [1] 19831
# xx@DESKTOP-0KALMAH UCRT64 /d/code/pure_tcl# ARM 远程端已启动！
# 本端 ID (用于 PC 连接): 9000

# xx@DESKTOP-0KALMAH UCRT64 /d/code/pure_tcl#
# xx@DESKTOP-0KALMAH UCRT64 /d/code/pure_tcl#
# xx@DESKTOP-0KALMAH UCRT64 /d/code/pure_tcl# /opt/tcl9/bin/wish90.exe pc_client.tcl
# PC 控制端已就绪。
# 收到 PC 请求: 执行 uname -a
# 收到 PC 请求: 执行 uname -a
# 收到 PC 请求: 执行 uname -a
# 收到 PC 请求: 执行 uname -a
# 收到 PC 请求: 执行 uname -a
# 收到 PC 请求: 执行 uname -a
# 收到 PC 请求: 执行 uname -a
# 收到 PC 请求: 执行 uname -a
#
#
# comm库的文档
#   https://core.tcl-lang.org/tcllib/doc/trunk/embedded/md/tcllib/files/modules/comm/comm.md

package require Tk
package require comm

# 1. 定义 ARM 的地址 (请替换为你板子的真实 IP)
set arm_ip "127.0.0.1"
set arm_node "9000 $arm_ip"

# 2. 界面布局
wm title . "Tcl 9.0 跨平台指令穿透测试"
wm geometry . 500x300

label .title -text "远程 AArch64 系统探测" -font {Helvetica 12 bold}
pack .title -pady 10

# 显示结果的文本框
text .log -height 10 -width 60 -bg "#f0f0f0"
pack .log -padx 10 -pady 10

# 3. 核心按钮逻辑
button .btn -text "点击抓取 ARM uname 信息" -command {
    .log delete 1.0 end
    .log insert end "正在连接 $arm_ip ...\n"
    update
    
    # 【黑科技时刻】：一行代码跨越网络执行
    if {[catch {
        set response [::comm::comm send $arm_node {get_remote_uname}]
        .log insert end "成功获取返回：\n$response"
    } err]} {
        .log insert end "连接失败: $err"
    }
}
pack .btn -pady 10

puts "PC 控制端已就绪。"

