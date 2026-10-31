#!/usr/bin/env tclsh9

package require tcltest
namespace import ::tcltest::*

# 测试入口 I/O 编码设置：尽早执行，先于 tcltest 任何输出。
# - encoding utf-8 : 保证中文输出不乱码
# - translation lf : 保证换行符是 \n，避免 Windows 下 \r\n
#                    导致 tcltest 的 -result 比较假失败
# catch 包住：终端不支持时静默降级，不阻断测试
if {$::tcl_platform(platform) eq "unix"} {
    catch {fconfigure stdout -encoding utf-8 -translation lf}
    catch {fconfigure stderr -encoding utf-8 -translation lf}
}

# 优雅配置全盘白盒审计大盘
# -verbose "start error" 会让 tcltest 建立内部管道审计
configure -verbose "start error"

runAllTests

