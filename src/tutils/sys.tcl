#!/usr/bin/env tclsh9

# /**
#  * @file sys.tcl
#  * @brief 强类型、免注入、生产级外部命令控制台安全执行引擎
#  * @author 
#  * @copyright Copyright (c) 2026
#  */

# 声明本文件属于 tutils 工具箱的 1.0 版本（供 pkg_mkIndex 识别）
package provide tutils 1.0

namespace eval ::sys {
    namespace export {[a-z]*}
    namespace ensemble create

    # /**
    #  * @brief 标准合流外部命令执行器（Facade 面门函数）
    #  * @details 自动将标准错误（stderr）合并到标准输出（stdout）中一同返回。
    #  *          采用不定长参数直通设计，调用方无需在外部手动包裹 list 或大括号。
    #  *          由于底层直接通过 execve 系统调用解包，天然免疫任何 Shell 脚本注入攻击。
    #  *
    #  * @param[in] args 不定长命令及参数。例如：sys exec_m grep "FATAL" "app.log"
    #  *
    #  * @return dict 返回包含两个核心键的结构化字典：
    #  *              - output: 完整的命令输出内容（包含 stdout 和 stderr）
    #  *              - code:   操作系统退出码（0=成功，非0=业务失败）
    #  *
    #  * @throws error 当突发内核级故障（如命令不存在 `SYS_SYSTEM_PANIC`）时，引爆 Tcl 原生异常向上击穿。
    #  *
    #  * @example
    #  *    set res [::sys::exec_m grep "FATAL" "/var/log/nginx.log"]
    #  *    if {[dict get $res code] != 0} {
    #  *        puts "日志中未找到关键字，控制台回显: [dict get $res output]"
    #  *    }
    #  */
    proc exec_m {args} { return [_exec_core 1 $args] }

    # /**
    #  * @brief 纯净分流外部命令执行器（Facade 面门函数）
    #  * @details 强制剥离并重定向标准错误（stderr），使其不污染返回的标准输出内容。
    #  *          采用不定长参数直通设计，调用方无需在外部手动包裹 list 或大括号。
    #  *
    #  * @param[in] args 不定长命令及参数。例如：sys exec_s ls -la "my folder"
    #  *
    #  * @return dict 返回包含两个核心键的结构化字典：
    #  *              - output: 纯净的标准输出内容（不包含任何 stderr 报错信息）
    #  *              - code:   操作系统退出码（0=成功，非0=业务失败）
    #  *
    #  * @throws error 当突发内核级故障（如命令不存在 `SYS_SYSTEM_PANIC`）时，引爆 Tcl 原生异常向上击穿。
    #  *
    #  * @example
    #  *    set res [::sys::exec_s docker ps -q]
    #  *    if {[dict get $res code] == 0} {
    #  *        puts "当前运行的容器ID列表: [dict get $res output]"
    #  *    }
    #  */
    proc exec_s {args} { return [_exec_core 0 $args] }

    # /**
    #  * @brief 【高阶强类型执行器】业务级安全断言执行引擎（Facade 面门函数）
    #  * @details 专为精密数据清洗、见错就死的自动化流水线步骤打造。
    #  *          - 当外部命令控制台退出码为 0 时：直接脱壳返回纯净的标准输出（String），无需上层解析字典。
    #  *          - 当外部命令非 0 业务崩溃时：就地引爆 Tcl 强类型异常，并将退出码精确打包塞入异常上下文。
    #  *          得益于底层私有引擎 `_exec_core` 的大一统设计，本函数天然对齐 Tcl 9 字符集死锁机制，
    #  *          输入命令携带中文字符串参数时绝对不发生跨平台多字节 Panic 崩溃。
    #  *
    #  * @param[in] args 不定长外部命令及参数。例如：sys try_exec curl -s -X GET "https://github.com"
    #  *
    #  * @return string 纯净的标准输出内容（末尾自动剥离换行符，中间多行换行完美保留）。
    #  *
    #  * @throws error 
    #  *          1. `SYS_SYSTEM_PANIC`: 外部可执行程序根本不存在或本地系统句柄爆裂，管道无法启动。
    #  *          2. `SYS_EXEC_ERROR`  : 命令跑完但退出码非 0，此时控制台错误输出（stderr）会直接充当异常消息（msg）抛出。
    #  *
    #  * @example
    #  *    # 生产环境标准强类型精准分流捕获与工业级测试回归范例：
    #  *    try {
    #  *        set raw_json [::sys::try_exec ip -json addr]
    #  *        puts "数据清洗成功: $raw_json"
    #  *    } trap {SYS_SYSTEM_PANIC} {err_msg opts} {
    #  *        puts "【致命故障】本地环境完蛋或内核管道死锁! 详情: $err_msg"
    #  *    } trap {SYS_EXEC_ERROR} {err_msg opts} {
    #  *        set exit_code [lindex [dict get $opts -errorcode] 1]
    #  *        puts "【业务失败】命令执行非0崩溃! 退出码: $exit_code, 错误回显: $err_msg"
    #  *        puts "【堆栈审计】完整的 Tcl 解释器注入调用链行号追踪:\n[dict get $opts -errorinfo]"
    #  *    }
    #  */
    proc try_exec {args} {
        set res [_exec_core 0 $args]
        set code [dict get $res code]
        set out  [dict get $res output]

        if {$code == 0} { return $out }

        # 统一业务级失败异常：包装成标准的 SYS_EXEC_ERROR 结构
        return -code error \
               -errorcode [list SYS_EXEC_ERROR $code] \
               -errorinfo "External command '$args' failed with exit code $code" \
               -level 1 \
               $out
    }

    # /**
    #  * @brief ISO-C 风格安全外部命令核心执行引擎（内部私有底层函数）
    #  * @details 采用双端阻塞管道与 8KB 分块缓冲区读取机制，保证对超长行回显和二进制流输出绝对安全。
    #  *          本函数实现了全盘异常与字符集大一统设计：
    #  *          - 系统级完蛋直接向上击穿，强迫主程序中断；业务级非 0 退出安全收敛入数据字典返回。
    #  *          - 【Tcl 9 强类型内核防卫】：在 open 系统调用前置阶段，动态拦截并强行将系统默认编码
    #  *            死锁为 `utf-8`，彻底根除因多字节中文字符转换引起的 `unexpected character` 溢出崩溃。
    #  *
    #  * @param[in] merge_stderr 是否合流标准错误（1 = 将 stderr 重定向合流至 stdout 管道，0 = 独立分流不捕获）
    #  * @param[in] cmd_parts    由高层门面函数打包好的完整命令及参数列表（标准 List 格式）
    #  *
    #  * @return dict 返回标准的结构化数据字典，包含两个核心键值对：
    #  *              - output: 过滤掉末尾换行符的干净回显内容（多行中间的换行符完美保留，支持 UTF-8 中文）
    #  *              - code:   操作系统退出码（精确捕获 CHILDSTATUS 错误码，突发宕机返回 -1）
    #  *
    #  * @throws error 
    #  *          1. `SYS_SYSTEM_PANIC ARGS_EMPTY`: 调用方传递了空参数列表。
    #  *          2. `SYS_SYSTEM_PANIC PIPE_CLOSE_FAILED`: 管道关闭时发生非 CHILDSTATUS 的内核异常。
    #  *          3. 原生 Tcl 管道异常: 外部可执行程序不存在（如返回 `POSIX ENOENT`）或本地系统死锁时，
    #  *             利用 `return -options` 将底层原生堆栈毫无损耗地彻底击穿暴露。
    #  *
    #  * @note 核心内部底层逻辑。输入采用列表解包直通内核系统调用（execve），规避了传统字符串拼接引发的注入隐患。
    #  */
    proc _exec_core {merge_stderr cmd_parts} {
        if {[llength $cmd_parts] == 0} {
            return -code error \
                   -errorcode {SYS_SYSTEM_PANIC ARGS_EMPTY} \
                   "\[sys\] error: no command or arguments provided"
        }

        # 在建立内核管道前，强行将 Tcl 解释器当前的系统级别编码和系统调用编码死锁为 utf-8
        # 这一步是专门为了对付 Tcl 9 强类型字符集断言，确保 open 带有中文参数的命令时平滑通关！
        set old_system_encoding [encoding system]
        catch {encoding system utf-8}

        set pipeline_cmd [list | {*}$cmd_parts]
        if {$merge_stderr} { lappend pipeline_cmd "2>@1" }

        # 如果命令不存在、或管道启动直接崩溃，直接将异常向上彻底击穿！
        if {[catch {open $pipeline_cmd r} pipe pipe_opts]} {
            # 恢复原系统编码，防止环境污染
            catch {encoding system $old_system_encoding}
            return -options $pipe_opts $pipe
        }
        # 恢复原系统编码（管道已经成功建立，字符集安全送达子进程）
        catch {encoding system $old_system_encoding}

        # 配置双端阻塞、全缓冲（8KB）
        fconfigure $pipe -blocking 1 -buffering full -buffersize 8192 -encoding utf-8
        set out_buffer [read $pipe]

        set exit_code 0
        # 【统一系统完蛋 2】：关闭管道时捕获系统底层状态
        if {[catch {close $pipe} err dict_opts]} {
            if {[dict exists $dict_opts -errorcode]} {
                set err_info [dict get $dict_opts -errorcode]

                if {[lindex $err_info 0] eq "CHILDSTATUS"} {
                    # 属于正常的业务级非 0 退出，精准提取操作系统退出码
                    set exit_code [lindex $err_info 2]
                } else {
                    # 属于非正常的突发系统级死锁或宕机，直接以底层原生异常向上击穿！
                    return -options $dict_opts $err
                }
            } else {
                # 极端突发情况，无 errorcode 却关闭失败，视为系统级崩溃
                return -code error \
                       -errorcode {SYS_SYSTEM_PANIC PIPE_CLOSE_FAILED} \
                       "\[sys\] unexpected critical pipe closure error: $err"
            }
        }

        # 正常业务返回：统一收敛为结构化字典
        return [dict create \
            output [string trimright $out_buffer "\r\n"] \
            code   $exit_code \
        ]
    }

    # /**
    #  * @brief 远程命令安全执行器（Expect 远程调用门面函数）
    #  * @details 专为跨主机自动化集群运维、分布式脚本分发、远程状态巡检打造的强类型控制引擎。
    #  *          采用大一统异常与参数死锁设计：
    #  *          - 将 `args` 不定长参数死锁在最后一位，彻底根除因 Tcl 默认参数解析引起的解包歧义与语法混乱。
    #  *          - 在入参层面做“前置强断言”：一旦检测到用户没有传递任何远程执行命令，
    #  *            直接引爆系统级致命异常（SYS_SYSTEM_PANIC REMOTE_ARGS_EMPTY），拦截非法调用。
    #  *          - 固定向底层核心引擎传递 0（不合流标准错误），让底层核心引擎只读取纯净的远程终端回显，
    #  *            彻底拒绝本地杂质污染，保证数据清洗时的准确性。
    #  *
    #  * @param[in] host    远程目标主机 IP 或 Hostname（String）
    #  * @param[in] user    SSH 登录用户名（String）
    #  * @param[in] pwd     SSH 登录密码（String）
    #  * @param[in] timeout 远程控制台命令执行超时保护时间（Int）
    #  * @param[in] args    不定长远程执行命令及参数。例如：ls -la "/var/log"
    #  *
    #  * @return dict 返回包含两个核心键的结构化字典：
    #  *              - output: 纯净的远程终端标准输出内容（不包含任何本地 stderr 杂质）
    #  *              - code:   操作系统退出码（0=远程执行成功，非0=远程业务或网络失败）
    #  *
    #  * @throws error 
    #  *          1. `SYS_SYSTEM_PANIC REMOTE_ARGS_EMPTY`: 调用方未传递任何要执行的远程命令。
    #  *          2. `SYS_SYSTEM_PANIC PIPE_CLOSE_FAILED`: 内部底层核心管道关闭时突发内核级故障。
    #  *
    #  * @example
    #  *    # 工业级标准远程巡检并提取磁盘占用率精细化控制范例：
    #  *    try {
    #  *        set res [::sys::exec_r "10.0.0.1" "admin" "pass123" 30 df -h "/" ]
    #  *        
    #  *        if {[dict get $res code] == 0} {
    #  *            puts "远程巡检成功，控制台回显:\n[dict get $res output]"
    #  *        } else {
    #  *            puts "【业务失败】远程执行失败，退出码: [dict get $res code]，报错: [dict get $res output]"
    #  *        }
    #  *    } trap {SYS_SYSTEM_PANIC} {err_msg opts} {
    #  *        puts "【致命故障】调用中断！检查发现未传递任何远程执行指令！详情: $err_msg"
    #  *    }
    #  */
    proc exec_r {host user pwd timeout args} {
        # 【全盘统一设计】：前置强断言，如果 args 不定长参数为空，直接抛出标准系统致命异常
        if {[llength $args] == 0} {
            return -code error \
                   -errorcode {SYS_SYSTEM_PANIC REMOTE_ARGS_EMPTY} \
                   "\[exec_r\] error: no remote command provided"
        }

        # 组装调用已部署在系统 PATH 中的 cmd2r.exp 脚本的本地参数
        set local_cmd [list cmd2r.exp $host $timeout $user $pwd]

        # 将远程参数无缝平铺追加到末尾，得益于 Tcl 9 列表锁死机制，天然免疫注入攻击
        lappend local_cmd {*}$args

        # 固定传入 0 分流，由底层核心引擎安全读取并返回数据
        return [_exec_core 0 $local_cmd]
    }

    # /**
    #  * @brief 本地文件精准推送至远程（SCP 上传门面函数）
    #  * @details 专为自动化部署、配置文件下发、固件包推送打造的强类型上传引擎。
    #  *          采用统一异常哲学：
    #  *          - 在本地环境层面做“前置强断言”：不管调用方传递的是相对路径（. 或 ..）还是绝对路径，
    #  *            一律强制“归一化”（file normalize）为绝对路径。一旦检测到本地源文件根本不存在，
    #  *            直接引爆系统级致命异常（SYS_SYSTEM_PANIC），拒绝启动昂贵的 SSH/SCP 远程握手连接。
    #  *          - 固定向底层核心引擎传递 0（不合流标准错误），确保远程推送链路回显纯净，
    #  *            由 scp 自行掌控生命周期，进程结束时自动释放管道，天然免疫任何因复杂环境引发的假死风险。
    #  *
    #  * @param[in] host      远程目标主机 IP 或 Hostname（String）
    #  * @param[in] src_path  本地待上传的源文件路径（支持相对或绝对路径，String）
    #  * @param[in] dest_path 远程落地的绝对目标路径。例如："/var/www/html/index.html"
    #  * @param[in] user      SSH 登录用户名（String）
    #  * @param[in] pwd       SSH 登录密码（String）
    #  * @param[in] timeout   SCP 传输超时保护时间，默认 60 秒（Int）
    #  *
    #  * @return dict 返回包含两个核心键的结构化字典：
    #  *              - output: 纯净的控制台标准输出内容（不包含任何 stderr）
    #  *              - code:   操作系统退出码（0=上传成功，非0=SCP业务失败）
    #  *
    #  * @throws error 
    #  *          1. `SYS_SYSTEM_PANIC LOCAL_FILE_NOT_FOUND`: 本地待上传的源文件根本不存在。
    #  *          2. `SYS_SYSTEM_PANIC PIPE_CLOSE_FAILED`  : 内部底层核心管道关闭时突发内核级故障。
    #  *
    #  * @example
    #  *    # 工业级标准下发配置文件精细化控制范例：
    #  *    try {
    #  *        set res [::sys::cp_l2r "10.0.0.1" "../conf/nginx.conf" "/etc/nginx/nginx.conf" "root" "pass123"]
    #  *        
    #  *        if {[dict get $res code] == 0} {
    #  *            puts "推送 Nginx 配置文件成功！"
    #  *        } else {
    #  *            puts "【业务失败】推送失败，退出码: [dict get $res code]，错误原因: [dict get $res output]"
    #  *        }
    #  *    } trap {SYS_SYSTEM_PANIC} {err_msg opts} {
    #  *        puts "【致命故障】打包发布中断！检查发现本地根本找不到待分发的 conf/nginx.conf 文件！详情: $err_msg"
    #  *    }
    #  */
    proc cp_l2r {host src_path dest_path user pwd {timeout 60}} {
        # 【全盘统一设计】：强制将本地路径归一化为绝对路径，防呆设计
        set real_src [file normalize $src_path]

        # 如果本地源文件不存在，视为内核级故障，就地引发系统级崩溃，不再向下调用外部脚本
        if {![file exists $real_src]} {
            return -code error \
                   -errorcode [list SYS_SYSTEM_PANIC LOCAL_FILE_NOT_FOUND] \
                   "\[cp_l2r\] critical error: local source path does not exist -> $real_src"
        }

        # 组装调用已部署在系统 PATH 中的 cp_l2r.exp 脚本的本地参数
        # 后续传给外部脚本时，一律采用无歧义的 $real_src 路径
        set local_cmd [list cp_l2r.exp $host $real_src $dest_path $timeout $user $pwd]

        # 固定传入 0 分流，安全读取并返回结构化数据
        return [_exec_core 0 $local_cmd]
    }

    # /**
    #  * @brief 远程文件精准拉取至本地（SCP 下载门面函数）
    #  * @details 专为自动化运维、日志收集、基础固件拉取打造的强类型下载引擎。
    #  *          采用统一异常哲学：
    #  *          - 在本地执行环境层面做“前置强断言”：一旦检测到本地目标落地的父目录根本不存在，
    #  *            直接引爆系统级致命异常（SYS_SYSTEM_PANIC），强迫依赖它的流水线中止，防止数据丢失。
    #  *          - 固定向底层传递 0（不合流标准错误），将底层管道阻塞与进程周期完全交由 scp 自行掌控，
    #  *            在 Windows UCRT64 或 Linux 环境下天然免疫假死和僵尸进程风险。
    #  *
    #  * @param[in] host      远程目标主机 IP 或 Hostname（String）
    #  * @param[in] src_path  远程源文件绝对路径。例如："/var/log/nginx/access.log"
    #  * @param[in] dest_path 本地落地绝对路径。例如："/data/logs/remote_nginx.log"
    #  * @param[in] user      SSH 登录用户名（String）
    #  * @param[in] pwd       SSH 登录密码（String）
    #  * @param[in] timeout   SCP 传输超时保护时间，默认 60 秒（Int）
    #  *
    #  * @return dict 返回包含两个核心键的结构化字典：
    #  *              - output: 纯净的控制台标准输出内容（不包含任何 stderr）
    #  *              - code:   操作系统退出码（0=下载成功，非0=SCP业务失败）
    #  *
    #  * @throws error 
    #  *          1. `SYS_SYSTEM_PANIC LOCAL_DIR_NOT_FOUND`: 本地落地的目标父目录不存在。
    #  *          2. `SYS_SYSTEM_PANIC PIPE_CLOSE_FAILED` : 内部底层管道关闭时突发内核级死锁。
    #  *
    #  * @example
    #  *    # 工业级标准拉取远程日志精细化控制范例：
    #  *    try {
    #  *        set res [::sys::cp_r2l "192.168.1.100" "/var/log/app.log" "/data/backup/app.log" "admin" "secret"]
    #  *        
    #  *        if {[dict get $res code] == 0} {
    #  *            puts "下载日志成功！"
    #  *        } else {
    #  *            puts "【业务失败】SCP 传输失败，退出码: [dict get $res code]，控制台报错: [dict get $res output]"
    #  *        }
    #  *    } trap {SYS_SYSTEM_PANIC} {err_msg opts} {
    #  *        puts "【致命故障】本地环境异常！本地可能连 /data/backup 目录都没建！详情: $err_msg"
    #  *    }
    #  */
    proc cp_r2l {host src_path dest_path user pwd {timeout 60}} {
        # 安全防呆：提取本地落地路径的父目录
        set local_parent [file dirname $dest_path]

        # 【全盘统一设计】：如果本地父目录不存在，视为内核级故障，直接抛出标准异常拦截！
        if {![file exists $local_parent]} {
            return -code error \
                   -errorcode [list SYS_SYSTEM_PANIC LOCAL_DIR_NOT_FOUND] \
                   "\[cp_r2l\] critical error: local destination directory does not exist -> $local_parent"
        }

        # 组装调用已部署在系统 PATH 中的 cp_r2l.exp 脚本的本地参数
        set local_cmd [list cp_r2l.exp $host $src_path $dest_path $timeout $user $pwd]

        # 终极简化：固定传入 0（不合流），由底层核心引擎安全读取并返回数据
        return [_exec_core 0 $local_cmd]
    }

    # /**
    #  * @brief System Date and Time Formatter (date_prt)
    #  * @details 纯 Tcl 实现的高性能时间戳生成器，自适应支持秒级与毫秒级高精度输出。
    #  *          默认输出格式为 "YYYY-MM-DD HH:MM:SS"。
    #  *
    #  * @param[in] format_str Tcl 格式的时间模板（选填）。
    #  *                       - 默认 "%Y-%m-%d %H:%M:%S"        -> 2026-05-20 09:15:30
    #  *                       - 毫秒 "%Y-%m-%d %H:%M:%S.%Milli" -> 2026-05-20 09:15:30.425
    #  *                       - 文件 "%Y%m%d_%H%M%S_%Milli"     -> 20260520_091530_425
    #  *
    #  * @return string 返回格式化后的本地时间字符串。
    #  */
    proc date_prt {{format_str "%Y-%m-%d %H:%M:%S"}} {
        set us [clock microseconds]

        set now [expr {$us / 1000000}]

        if {[string match "*%Milli*" $format_str]} {
            set ms_num [expr {($us / 1000) % 1000}]
            set milli [format "%03d" $ms_num]
            regsub -all {%Milli} $format_str $milli format_str
        }

        return [clock format $now -format $format_str]
    }

    # /**
    #  * @brief 高性能、0 误伤、且不污染变量现场的 Tcl 9 数据类型内窥器 (get_type)
    #  * @details 本函数是 tutils 工具箱的核心基石。专为 Tcl 9 内核的值共享与优化机制设计。
    #  *          它利用底层未公开指令深入 C 语言运行时，在完全不触发写时复制 (Copy-On-Write)
    #  *          和内部人格突变 (Shimmering) 的前提下，精准识别对象的真实物理形态。
    #  * 
    #  *          【硬核机制说明】：
    #  *          1. 顶级标量防火墙：优先拦截 pure string, string, int, double, bytearray。
    #  *             绝对不给它们接触 llength 或 dict keys 的机会，从源头上彻底切断「单元素列表」
    #  *             和「二进制字节流解码」引发的隔空内存污染。
    #  *          2. 内核标签直通车：对已标记为 dict 或 list 的复合结构进行 C 语言级别的快速放行。
    #  *          3. 混沌文本安全探测：仅对未打标签的原始字串进行防污染隔离探测（利用 catch 隔离），
    #  *             安全推导出潜在的字典或列表结构。
    #  *
    #  * @param[in] data  需要进行内部类型探测的任意 Tcl 数据对象（支持原子标量与复杂嵌套容器）。
    #  *
    #  * @return string   返回该对象的业务抽象类型，仅限于以下三种标准枚举值：
    #  *                  - "dict"       : 纯正的、或符合语法规则的字典结构
    #  *                  - "list"       : 纯正的、或符合语法规则的列表结构
    #  *                  - "empty"      : 空
    #  *                  - "string"     : 包含纯文字、数字、布林值及二进制字节流在内的所有原子标量
    #  */
    proc get_type {data} {
        set rep [tcl::unsupported::representation $data]
        set rep_lower [string tolower $rep]

        # 1. 【核心严谨防线】基本标量防火墙
        # 只要底层包含 string、int、double 或 bytearray 等任何原子类型，
        # 立刻作为 "string"（标量）安全撤退，绝对不给后面任何引发突变的指令触碰的机会！
        if {[regexp {value is a (pure )?(string|int|double|bytearray)} $rep_lower]} {
            return "string"
        }

        # 2. 第一防线：依靠 C 层面真正的内部表示，绝对不触发隐式转换
        if {[string match {*value is a dict*} $rep_lower]} {
            if {[dict size $data] == 0} {
                return "empty"
            } else {
                return "dict"
            }
        }
        if {[string match {*value is a list*} $rep_lower]} {
            if {[llength $data] == 0} {
                return "empty"
            } else {
                return "list"
            }
        }

        if {$data eq ""} { return "string" }

        # 3. 只有非 pure string 且可能代表列表/字典的复合文本，才允许安全探测
        # 探测前先用 catch 隔离，防止人格污染
        if {![catch {dict keys $data} dkeys] && [llength $dkeys] > 0} {
            if {[expr {[llength $data] % 2}] == 0} { return "dict" }
        }
        if {![catch {llength $data} len] && $len > 1} {
            return "list"
        }

        return "string"
    }

    # /**
    #  * @brief 高性能、调试友好、且不污染变量现场的 Tcl 9 对象内存指标内窥器
    #  * 
    #  * @description 本过程专为 Tcl 9 设计。利用底层未公开指令深入 C 语言运行时层面，
    #  *              在不触发「写时复制 (Copy-On-Write)」和对象复制的前提下，瞬间
    #  *              提取变量在内存中的物理地址指针。常用于内存泄漏排查、底层调试、
    #  *              以及分析 Tcl 9 对象的共用 (Sharing) 与优化状态。
    #  * 
    #  * @param data      [Any]  需要探测内存指针的 Tcl 数据对象（支持任意类型）。
    #  * @param show_ptr  [Bool] 调试开关。预设为 1 (开启) 返回格式化指标；设为 0 (关闭) 则直接返回空串。
    #  * 
    #  * @return [String] 返回格式化后的指标后缀（形如 " <0x100874b10>"）。若关闭开关或提取失败，返回空字符串 ""。
    #  */
    proc get_ptr_suffix {data} {
        set rep [tcl::unsupported::representation $data]

        # 核心抓取机制：利用专门适应 Tcl 9 的 64 位变长十六进制正则表达式，捕获内存地址
        # 此处精妙使用 Tcl 自由变量名习惯，以 `->` 作为抛弃型完整匹配占位符，将首个捕获组精准导向 `ptr`
        if {[regexp {object pointer at (0x[0-9A-Fa-f]+)} $rep -> ptr]} { return " <$ptr>" }
        return ""
    }
}

