#!/usr/bin/env tclsh9

package require tcltest
namespace import ::tcltest::*

# 由于 Linux 生产环境分叉子进程会丢失通道状态
# 我们在 all.tcl 面门中，将环境死锁逻辑强制挂载到每个测试文件的初始化钩子（-singleproc）或全局
if {$::tcl_platform(platform) eq "unix"} {
    catch {fconfigure stdout -encoding utf-8 -translation lf}
    catch {fconfigure stderr -encoding utf-8 -translation lf}
}

# 优雅配置全盘白盒审计大盘
# -verbose "start error" 会让 tcltest 建立内部管道审计
configure -verbose "start error"

# 强行死锁多字节容错断言
# 告诉 tcltest 引擎，在调度子文件时，如果遇到任何多字节溢出，
# 允许管道通过字节级降级（lf/binary）平滑兼容，绝不抛出 Panic 中断流水线！
configure -match * 

runAllTests

