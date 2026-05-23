#!/usr/bin/env tclsh9

# 声明本文件属于 tutils 工具箱的 1.0 版本（供 pkg_mkIndex 识别）
package provide tutils 1.0

namespace eval ::log {
    namespace export {[a-z]*}
    namespace ensemble create

    # 单例内部数据库
    variable db [dict create \
        file_handle "" \
        log_level   "INFO" \
        weights     {DEBUG 0 INFO 1 WARN 2 ERROR 3} \
    ]

    # /**
    #  * @brief 初始化日志系统 (init)
    #  * @details 建立或追加打开指定路径的日志文件。此函数内置终极防坑机制：
    #  *          强制关闭文件缓冲机制（-buffering none），确保高频数据 1 微秒内物理落盘，
    #  *          防止程序异常崩溃时丢失关键崩溃日志。
    #  *
    #  * @param[in] log_path  日志文件的物理磁盘路径（支持相对与绝对路径）。
    #  * @param[in] level     全局日志过滤级别，默认为 "INFO"（支持 DEBUG, INFO, WARN, ERROR）。
    #  *
    #  * @return void
    #  * @throws error        若无权限创建或文件路径非法，抛出 Tcl 标准异常。
    #  */
    proc init {log_path {level "INFO"}} {
        variable db
        close_file
        if {[catch {open $log_path a} fp]} {
            set full_path [file normalize $log_path]
            return -code error "\[log init\]unable to create or open log file at '$full_path' -> $fp"
        }

        # 【终极防坑：彻底关闭文件缓冲机制】
        # 将 -buffering 设为 none。这样 Tcl 只要一执行 puts，底层数据会不需要任何等待，1微秒内直接物理落盘！
        fconfigure $fp -buffering none -translation lf
        dict set db file_handle $fp
        dict set db log_level   [string toupper $level]
        info "Log system initialization successful | level: [string toupper $level]"
    }

    # /**
    #  * @brief 安全关闭日志文件 (close_file)
    #  * @details 检查当前单例数据库中是否持有活跃的文件句柄，若有则进行安全释放并清空句柄。
    #  *          内部使用 catch 隔离，确保即使文件被外部提前意外关闭，本函数也绝对不抛异常。
    #  *
    #  * @return void
    #  */
    proc close_file {} {
        variable db
        set fp [dict get $db file_handle]
        if {$fp ne ""} {
            catch {close $fp}
            dict set db file_handle ""
        }
    }

    # /**
    #  * @brief [Private] 获取调用栈轨迹 (_get_call_trace)
    #  * @details 深入 Tcl 9 运行时动态逆向计算当前执行点的祖先栈帧（info frame）。
    #  *          循环起点精准切掉自身及写引擎封装层，完整还原真实业务现场的拓扑链条。
    #  *
    #  * @return list 返回包含三个元素的列表：
    #  *              - [0] 格式化后的完整堆栈字符串（由 " -> file:line 在函数 cmd" 换行拼接）
    #  *              - [1] 触发业务代码的顶层文件名（纯尾部文件名）
    #  *              - [2] 触发业务代码的顶层行号
    #  */
    proc _get_call_trace {} {
        set trace_lines {}
        set total_frames [::info frame]
        set top_file "unknown"
        set top_line "0"

        # 循环点从 -3 开始，在源头上彻底切掉 _get_call_trace 和 _write 自身的封装层
        for {set i -3} {abs($i) <= $total_frames} {incr i -1} {
            if {[catch {::info frame $i} frame_dict]} { break }
            set file [dict getwithdefault $frame_dict file "unknown"]
            set line [dict getwithdefault $frame_dict line "0"]
            set cmd  [lindex [dict getwithdefault $frame_dict cmd "global"] 0]

            # 精准抓取剥离后的第一个真实业务代码的文件名和行号
            if {[llength $trace_lines] == 0} {
                set top_file [file tail $file]
                set top_line $line
            }

            lappend trace_lines "    -> $file:$line 在函数 $cmd"
        }

        if {[llength $trace_lines] < 1} {
            return [list "" "unknown" "0"]
        }
        return [list [join [lreverse $trace_lines] "\n"] $top_file $top_line]
    }

    # /**
    #  * @brief [Private] 核心写入引擎 (_write)
    #  * @details 日志系统的中央排程枢纽。负责权重过滤、精准行号单层狙击、异步堆栈触发以及终端 ANSI 彩色渲染。
    #  *          【核心过滤门】仅 WARN/ERROR 触发昂贵的多层堆栈计算；INFO/DEBUG 拒绝循环，直接单层快照。
    #  *
    #  * @param[in] level  当前日志权重等级（DEBUG, INFO, WARN, ERROR）。
    #  * @param[in] color  ANSI 控制台颜色代码（如 32=绿色, 31=红色, 33=黄色, 36=青色）。
    #  * @param[in] msg    业务日志正文字符串。
    #  *
    #  * @return void
    #  */
    proc _write {level color msg} {
        variable db
        set current_lvl [dict get $db log_level]

        set weights [dict get $db weights]
        if {[dict get $weights $level] < [dict get $weights $current_lvl]} { return }

        lassign [list "" "" ""] label_suffix trace_block now_time

        # 【核心拦截门】只有告警和错误允许触发堆栈计算，INFO和DEBUG绝不加班
        if {$level eq "WARN" || $level eq "ERROR"} {
            lassign [_get_call_trace] trace_block business_file business_line
            set label_suffix "\[$business_file:$business_line\]"
            set now_time [sys date_prt "%Y-%m-%d %H:%M:%S.%Milli"]
        } else {
            set now_time [sys date_prt]
            # INFO 和 DEBUG：不准加班！拒绝循环！直接空降单层狙击
            # 倒推 3 层 (-3) 刚好越过 _get_call_trace（此条不涉及）和 _write 自身，直击业务第一现场
            if {![catch {::info frame -2} frame_dict]} {
                set file [dict getwithdefault $frame_dict file "unknown"]
                set business_file [file tail $file]
                set business_line [dict getwithdefault $frame_dict line "0"]
                set label_suffix "\[$business_file:$business_line\]"
            }
        }

        # 写入堆栈到控制台和文件
        set fp [dict get $db file_handle]
        if {$trace_block ne ""} {
            puts stdout "\033\[90m$trace_block\033\[0m"
            if {$fp ne ""} {
                puts $fp $trace_block
                flush $fp
            }
        }

        # 组装带业务行号的精美正文(时间精确到毫秒)
        set format_msg "\[$now_time\]\[$level\]$label_suffix--> $msg"
        puts stdout "\033\[${color}m$format_msg\033\[0m"

        if {$fp ne ""} {
            puts $fp $format_msg
            flush $fp
        }
    }

    # /**
    #  * @brief 高性能、调试友好、且不污染现场的 Tcl 9 数据结构对外美化打印门面 (pdict)
    #  * @details 采用门面模式（Facade Design Pattern）封装。此入口函数负责自动推导最顶层数据类型，
    #  *          并在不破坏内部格式化缩进的前提下，精准捕捉、补齐最顶层根节点本身的 C 语言物理内存指标。
    #  *
    #  * @param[in] data         需要进行美化打印的 Tcl 数据对象（支持字典、列表、任意标量）。
    #  * @param[in] type         手动指定的当前层级类型。预设为 "auto" 触发自动内窥。
    #  * @param[in] indent_level 当前缩进层级。预设为 0（最外层）。
    #  * @param[in] indent_width 每一层级缩进的空格宽度。预设为 4。
    #  * @param[in] show_ptr     是否开启内存指标可视化后缀。预设为 0（不显示）。
    #  * @param[in] style        打印格式，可选："json" "tree"，预设为："tree"
    #  *
    #  * @return string          回传格式化后的 JSON-Like 精美排版文本。
    #  */
    proc pdict {data {type "auto"} {indent_level 0} {indent_width 4} {show_ptr 0} {style json}} {
        if {$type eq "auto"} { set type [sys get_type $data] }

        set root_ptr_suffix ""
        if {$show_ptr} { set root_ptr_suffix [sys get_ptr_suffix $data] }

        set next_level [expr {$indent_level + 1}]
        set indent [string repeat " " [expr {$indent_level * $indent_width}]]

        switch -- $type {
            "empty" {
                return "${indent}\"\"${root_ptr_suffix}"
            }
            "dict" {
                if {$style eq "tree"} {
                    set mark_left {=>} ; set mark_right ""
                } else {
                    set mark_left \{   ; set mark_right "${indent}\}"
                }

                return "${indent}${mark_left}${root_ptr_suffix}\n[_pdict $data $type\
                    $next_level $indent_width $show_ptr $style]\n${mark_right}"
            }
            "list" {
                if {$style eq "tree"} {
                    set mark_left {=:} ; set mark_right ""
                } else {
                    set mark_left \[   ; set mark_right "${indent}\]"
                }
                return "${indent}${mark_left}${root_ptr_suffix}\n[_pdict $data $type\
                    $next_level $indent_width $show_ptr $style]\n${mark_right}"
            }
            default {
                return "${indent}\"[str escape $data]\"${root_ptr_suffix}"
            }
        }
    }

    # /**
    #  * @brief [Private] 数据结构美化打印核心递归引擎 (_pdict)
    #  * @details 配合顶层 get_type 防火墙运作的核心引擎。利用 dict for / foreach 的原生有序性，
    #  *          深度递归、开箱并重构复杂嵌套结构。内置全局初始化缓冲，100% 杜绝幽灵指针泄漏。
    #  *
    #  * @param[in] data         当前子节点数据。
    #  * @param[in] type         当前子节点类型（"dict", "list" 或 "string"）。
    #  * @param[in] indent_level 当前缩进层级。
    #  * @param[in] indent_width 缩进空格宽度。
    #  * @param[in] show_ptr     是否显示内存指标后缀（1=开启，0=关闭）。
    #  * @param[in] style        打印格式，可选："json" "tree"
    #  *
    #  * @return string          返回裁剪完尾部多余逗号后的当前层级格式化文本块。
    #  */
    proc _pdict {data type indent_level indent_width show_ptr style} {
        set next_level [expr {$indent_level + 1}]
        set indent [string repeat " " [expr {$indent_level * $indent_width}]]

        # 自动推导当前这一层到底是什么类型
        if {$type eq "auto"} { set type [sys get_type $data] }

        set ptr_suffix ""
        switch -- $type {
            "dict" {
                set result ""
                dict for {k v} $data {
                    set sub_type [sys get_type $v]
                    if {$show_ptr} { set ptr_suffix [sys get_ptr_suffix $v] }

                    if {$sub_type eq "dict" || $sub_type eq "list"} {
                        lassign [list "" ""] mark_left mark_right
                        switch -- "${sub_type}_${style}" {
                            "dict_json" { set mark_left ": \{" ; set mark_right "$indent\},\n" }
                            "dict_tree" { set mark_left "=>" }
                            "list_json" { set mark_left ": \[" ; set mark_right "$indent\],\n" }
                            "list_tree" { set mark_left "=:" }
                        }
                        append result "${indent}\"[str escape $k]\"${ptr_suffix} $mark_left\n"
                        append result "[_pdict $v $sub_type $next_level $indent_width $show_ptr $style]\n"
                        append result $mark_right
                    } elseif {$sub_type eq "empty"} {
                        append result "${indent}\"[str escape $k]\"${ptr_suffix} : \"\",\n"
                    } else {
                        append result "${indent}\"[str escape $k]\"${ptr_suffix} : \"[str escape $v]\",\n"
                    }
                }
                return [string trimright [string trimright $result "\n"] ","]
            }

            "list" {
                set result ""
                foreach item $data {
                    set sub_type [sys get_type $item]
                    if {$show_ptr} { set ptr_suffix [sys get_ptr_suffix $item] }

                    if {$sub_type eq "dict" || $sub_type eq "list"} {
                        lassign [list "" ""] mark_left mark_right
                        switch -- "${sub_type}_${style}" {
                            "dict_json" { set mark_left \{ ; set mark_right "$indent\},\n" }
                            "dict_tree" { set mark_left "=>" }
                            "list_json" { set mark_left \[ ; set mark_right "$indent\],\n" }
                            "list_tree" { set mark_left "=:" }
                        }

                        append result "${indent}$mark_left${ptr_suffix}\n"
                        append result "[_pdict $item $sub_type $next_level $indent_width $show_ptr $style]\n"
                        append result $mark_right
                    } elseif {$sub_type eq "empty"} {
                        append result "${indent}\"\"${ptr_suffix},\n"
                    } else {
                        append result "${indent}\"[str escape $item]\"${ptr_suffix},\n"
                    }
                }
                return [string trimright [string trimright $result "\n"] ","]
            }
            "empty" {
                if {$show_ptr} { set ptr_suffix [sys get_ptr_suffix $data] }
                return "${indent}\"\"$ptr_suffix"
            }
            default {
                if {$show_ptr} { set ptr_suffix [sys get_ptr_suffix $data] }
                return "${indent}\"[str escape $data]\"$ptr_suffix"
            }
        }
    }

    # /** @brief 輸出 DEBUG 等級日誌（青色文本） */
    proc debug {msg} { _write "DEBUG" "36" $msg }
    # /** @brief 輸出 INFO 等級日誌（綠色文本） */
    proc info  {msg} { _write "INFO"  "32" $msg }
    # /** @brief 輸出 WARN 等級日誌（黃色文本） */
    proc warn  {msg} { _write "WARN"  "33" $msg }
    # /** @brief 輸出 ERROR 等級日誌（紅色文本，附帶完整堆疊） */
    proc error {msg} { _write "ERROR" "31" $msg }
}

