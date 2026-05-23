#!/usr/bin/env tclsh9

package require comm

# 1. 启动 comm 服务，监听 9000 端口
::comm::comm config -port 9000 -listen 1

# 2. 定义一个获取系统信息的函数
proc get_remote_uname {} {
    puts "收到 PC 请求: 执行 uname -a"
    # 执行系统命令并抓取返回字符串
    set result [exec uname -a]
    return $result
}

puts "ARM 远程端已启动！"
puts "本端 ID (用于 PC 连接): [::comm::comm self]"
vwait forever

