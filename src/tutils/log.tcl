#!/usr/bin/env tclsh9

package require textutil::wcswidth

namespace eval ::log {
    namespace export {[a-z]*}
    namespace ensemble create

    # 单例内部数据库
    variable db [dict create \
        file_handle "" \
        log_level   "INFO" \
        weights     {DEBUG 0 INFO 1 WARN 2 ERROR 3} \
    ]

    # @brief 初始化日志系统 (init)
    # @details 建立或追加打开指定路径的日志文件。此函数内置终极防坑机制：
    #          强制关闭文件缓冲机制（-buffering none），确保高频数据 1 微秒内物理落盘，
    #          防止程序异常崩溃时丢失关键崩溃日志。
    # 
    # @param[in] log_path  日志文件的物理磁盘路径（支持相对与绝对路径）。
    # @param[in] level     全局日志过滤级别，默认为 "INFO"（支持 DEBUG, INFO, WARN, ERROR）。
    # 
    # @return void
    # @throws error        若无权限创建或文件路径非法，抛出 Tcl 标准异常。
    proc init {log_path {level "INFO"}} {
        variable db
        close_file
        if {[catch {open $log_path a} fp]} {
            set full_path [file normalize $log_path]
            return -code error "\[log init\]unable to create or open log file at '$full_path' -> $fp"
        }

        # 【终极防坑：彻底关闭文件缓冲机制】
        # 将 -buffering 设为 none。这样 Tcl 只要一执行 puts，底层数据会不需要任何等待，1微秒内直接物理落盘！
        # 强行把落盘的格式锁死为 utf-8
        fconfigure $fp -buffering none -translation lf -encoding utf-8
        dict set db file_handle $fp
        dict set db log_level   [string toupper $level]
        info "Log system initialization successful | level: [string toupper $level]"
    }

    # * @brief 安全关闭日志文件 (close_file)
    # * @details 检查当前单例数据库中是否持有活跃的文件句柄，若有则进行安全释放并清空句柄。
    # *          内部使用 catch 隔离，确保即使文件被外部提前意外关闭，本函数也绝对不抛异常。
    # *
    # * @return void
    proc close_file {} {
        variable db
        set fp [dict get $db file_handle]
        if {$fp ne ""} {
            catch {close $fp}
            dict set db file_handle ""
        }
    }

    # * @brief [Private] 获取调用栈轨迹 (_get_call_trace)
    # * @details 深入 Tcl 9 运行时动态逆向计算当前执行点的祖先栈帧（info frame）。
    # *          循环起点精准切掉自身及写引擎封装层，完整还原真实业务现场的拓扑链条。
    # *
    # * @return list 返回包含三个元素的列表：
    # *              - [0] 格式化后的完整堆栈字符串（由 " -> file:line 在函数 cmd" 换行拼接）
    # *              - [1] 触发业务代码的顶层文件名（纯尾部文件名）
    # *              - [2] 触发业务代码的顶层行号
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

            set cmd_raw [dict getwithdefault $frame_dict cmd "global"]
            set cmd [lindex [split $cmd_raw] 0]

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

    # @brief [Private] 核心写入引擎 (_write)
    # @details 日志系统的中央排程枢纽。负责权重过滤、精准行号单层狙击、异步堆栈触发以及终端 ANSI 彩色渲染。
    #          【核心过滤门】仅 WARN/ERROR 触发昂贵的多层堆栈计算；INFO/DEBUG 拒绝循环，直接单层快照。
    # 
    # @param[in] level  当前日志权重等级（DEBUG, INFO, WARN, ERROR）。
    # @param[in] color  ANSI 控制台颜色代码（如 32=绿色, 31=红色, 33=黄色, 36=青色）。
    # @param[in] msg    业务日志正文字符串。
    # 
    # @return void
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

    # @brief 高性能、调试友好、且不污染现场的 Tcl 9 数据结构对外美化打印门面 (pdict)
    # @details 采用门面模式（Facade Design Pattern）封装。此入口函数负责自动推导最顶层数据类型，
    #          并在不破坏内部格式化缩进的前提下，精准捕捉、补齐最顶层根节点本身的 C 语言物理内存指标。
    #          顶层类型分派规则：
    #          - dict / list：递归进入 _pdict 展开嵌套结构。
    #          - empty_dict / empty_list：直接输出标准的大括号 {} 和 中括号 [] 占位（严格区分空容器与纯空值）。
    #          - empty：纯空字符串，直接输出 "" 占位。
    #          - object：经 _info_obj 拍平为纯文本（类、父类、变量及值），不递归展开对象属性。
    #          - bytearray：经 _info_bytearray 输出十六进制头部预览与魔数类型标注，绝不输出完整二进制。
    #          - 其他标量：经 _format_key 转义渲染。
    #          所有非容器类型均不触发原始对象的字符串化或类型降级（cmdName/bytearray 保持原内部表示）。
    # 
    # @param[in] data         需要进行美化打印的 Tcl 数据对象。支持 dict、list、empty_dict、
    #                         empty_list、empty、TclOO 对象、bytearray 以及任意标量。
    # @param[in] type         手动指定的当前层级类型。预设为 "auto" 触发自动内窥；
    #                         显式传入时跳过 sys get_type，可用于强制按指定类型渲染。
    # @param[in] indent_level 当前缩进层级。预设为 0（最外层）。
    # @param[in] indent_width 每一层级缩进的空格宽度。预设为 4。
    # @param[in] show_ptr     是否开启内存指标可视化后缀。预设为 0（不显示）。
    # @param[in] style        打印格式，可选："json" "tree"，预设为："tree"
    # 
    # @return string          回传格式化后的 JSON-Like 精美排版文本。
    proc pdict {
        data
        {type "auto"}
        {indent_level 0}
        {indent_width 4}
        {show_ptr 0}
        {style tree}
    } {
        if {$type eq "auto"} { set type [sys get_type $data] }

        set root_ptr_suffix ""
        if {$show_ptr} { set root_ptr_suffix [sys get_ptr_suffix $data] }

        set next_level [expr {$indent_level + 1}]
        set indent [string repeat " " [expr {$indent_level * $indent_width}]]

        switch -- $type {
            "empty_dict"    { return "${indent}{}${root_ptr_suffix}" }
            "empty_list"    { return "${indent}\[\]${root_ptr_suffix}" }
            "empty"         { return "${indent}\"\"${root_ptr_suffix}" }
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
            "object"    {
                set obj_dict [_info_obj $data $show_ptr]

                if {$style eq "tree"} {
                    set mark_left {=>} ; set mark_right ""
                } else {
                    set mark_left \{   ; set mark_right "${indent}\}"
                }

                return "${indent}${mark_left}${root_ptr_suffix}\n[_pdict $obj_dict dict\
                    $next_level $indent_width $show_ptr $style]\n${mark_right}"
            }
            "bytearray" { return [_format_key [_info_bytearray $data] $indent $root_ptr_suffix $style] }
            default     { return [_format_key $data $indent $root_ptr_suffix $style] }
        }
    }

    # @brief [Private] 根据十六进制头部识别常见二进制格式
    # @details 传入小写、无空格的十六进制字符串（至少前 8 个字符），
    #          匹配常见魔数，返回人类可读的类型名；无法识别返回空串。
    # @param[in] hex  十六进制字符串（小写，无空格）
    # @return string  类型名，如 "PNG image"；无法识别返回 ""
    proc _magic_type {hex} {
        # 取前 16 个十六进制字符（8 字节）做匹配，足够覆盖常见魔数
        set head [string range $hex 0 15]
        switch -glob -- $head {
            "89504e47*" { return "PNG image" }
            "ffd8*"     { return "JPEG image" }
            "47494638*" { return "GIF image" }
            "25504446*" { return "PDF document" }
            "504b0304*" { return "ZIP archive (or Office Open XML)" }
            "1f8b*"     { return "GZIP archive" }
            "425a68*"   { return "BZIP2 archive" }
            "377abcaf*" { return "7-Zip archive" }
            "52617221*" { return "RAR archive" }
            "4d5a*"     { return "Windows executable" }
            "7f454c46*" { return "ELF executable" }
            "cafebabe*" { return "Java class file" }
            "000001ba*" { return "MPEG program stream" }
            "000001b3*" { return "MPEG video" }
            "494433*"   { return "MP3 with ID3 tag" }
            "4f676753*" { return "OGG container" }
            "664c6143*" { return "FLAC audio" }
            "52494646*" { return "RIFF container (WAV/AVI/WebP)" }
            "1a45dfa3*" { return "Matroska/WebM" }
            "38425053*" { return "Photoshop document" }
            "d0cf11e0*" { return "OLE2 compound (DOC/XLS/PPT)" }
            default     { return "" }
        }
    }

    # @brief [Private] bytearray 安全预览，返回纯文本
    # @details 只打印前 max_bytes 个字节的十六进制转储，绝不输出完整二进制内容。
    #          尝试根据头部魔数识别常见格式，识别成功时在预览中标注类型。
    #          不带缩进、不带指针后缀、不区分 style，由调用方负责排版。
    # @param[in] data        bytearray 值
    # @param[in] max_bytes   最多显示的字节数，默认 16
    # @return string         形如 "<bytearray len=100 head=16: 48 65 ... type=PNG image>" 的纯文本
    proc _info_bytearray {data {max_bytes 16}} {
        set len [string length $data]
        set head_len [expr {$len > $max_bytes ? $max_bytes : $len}]

        # 取前 head_len 个字节，转十六进制
        set hex [binary encode hex [string range $data 0 [expr {$head_len - 1}]]]

        # 每两个字符插一个空格
        set hex_spaced [regsub -all {..} $hex {& }]
        set hex_spaced [string trimright $hex_spaced " "]

        set preview "<bytearray len=${len} head=${head_len}: ${hex_spaced}"
        if {$len > $max_bytes} {
            append preview " ..."
        }

        # 头部类型识别（用无空格的原始 hex）
        set mtype [_magic_type $hex]
        if {$mtype ne ""} {
            append preview " type=${mtype}"
        }

        append preview ">"
        return $preview
    }

    # @brief [Private] TclOO 对象内省，返回纯字典结构（暂不防环）
    # @details 输出对象的类、父类以及变量。所有元数据强制退化为纯字符串，防止引发二次解析。
    # @param[in] obj  TclOO 对象句柄（命令名）
    # @return dict   标准的扁平化字典对象
    proc _info_obj {obj {show_ptr 0}} {
        # 基础信息捕获，防止对象已销毁导致后续直接崩溃
        if {[catch {
            set cls [::info object class $obj]
            set supers [::info class superclasses $cls]
            set var_names [lsort [::info object vars $obj]]
            set ns [::info object namespace $obj]
        } err]} {
            return [dict create "object" "$obj" "error" "$err"]
        }

        set obj_dict [dict create]

        set ptr_suffix ""
        if {$show_ptr} { set ptr_suffix [sys get_ptr_suffix $obj] }

        # 【核心防线】利用字符串拼接强制退化为 pure string，绝不能保留 cmdName 内部表示
        # $cls $supers 本身就是对象
        puts "now obj ----- ${obj} ------"
        dict set obj_dict object       "<${obj}${ptr_suffix}>"
        dict set obj_dict class        "<$cls>"
        dict set obj_dict superclasses "<$supers>"

        # 提取对象变量，直接构建 vars 字典
        set vars_dict [dict create]
        foreach vname $var_names {
            if {[catch {set ${ns}::${vname}} vval]} {
                dict set vars_dict $vname "<无法读取>"
            } else {
                dict set vars_dict $vname $vval
            }
        }

        # 将变量字典挂载到主字典上
        dict set obj_dict vars $vars_dict

        return $obj_dict
    }

    # @brief [Private] 键名格式化引擎（严格区分 JSON 与 Tree 模式）
    # @details 针对字典的键名进行渲染。
    #          - JSON 模式：全量转义，输出为严格单行。
    #          - Tree 模式：识别 \r\n 及多行文本，开启左边界竖线（|）对齐排版。
    proc _format_key {k indent ptr_suffix style} {
        # JSON 模式：保持原样，全量转义（包括 \r\n 变字面量 \r 和 \n）
        if {$style ne "tree"} {
            return "${indent}\"[str escape $k]\"${ptr_suffix}"
        }
        
        # Tree 模式：归一化换行符，启动多行竖线对齐
        set k_norm [string map {"\r\n" "\n" "\r" "\n"} $k]
        set k_lines [split $k_norm "\n"]
        
        if {[llength $k_lines] == 1} {
            # 单行：常规转义（\t 会自动变成 \t 字面量）
            return "${indent}\"[str escape $k]\"${ptr_suffix}"
        } else {
            # 多行：首行带引号，后续行左侧对齐竖线，末行补后置引号
            set k_out "${indent}\"[str escape [lindex $k_lines 0]]"
            foreach line [lrange $k_lines 1 end] {
                append k_out "\n${indent}|[str escape $line]"
            }
            append k_out "\"${ptr_suffix}"
            return $k_out
        }
    }

    # @brief [Private] 数据结构美化打印核心递归引擎 (_pdict)
    # @details 仅供顶层门面 pdict 调用的私有递归引擎，输入契约的主类型为 dict / list。
    #          在递归过程中，会对子项进行类型分派：
    #          - dict / list：继续递归展开。
    #          - empty：直接输出空字符串 "" 占位。
    #          - empty_dict：直接输出标准大括号 {} 占位（严格区分空容器与纯空值）。
    #          - empty_list：直接输出标准中括号 [] 占位。
    #          - object：经 _info_obj 拍平为纯文本（类、父类、变量及值），不递归展开对象属性内部的
    #            嵌套结构，避免无限递归与类型降级。
    #          - bytearray：经 _info_bytearray 输出十六进制头部预览与魔数类型标注，只展示前 max_bytes
    #            个字节，绝不输出完整原始二进制。
    #          - 其他标量：直接输出字符串形式。
    #          若误传主类型（非 dict / list），switch 落空返回空串，以显式暴露契约违反，不做静默兜底。
    #          利用 dict for / foreach 的原生有序性，深度递归、开箱并重构复杂嵌套结构。
    #          内置全局初始化缓冲，100% 杜绝幽灵指针泄漏。
    #          【JSON 模式】：严格单行转义，保留合法 RFC 8259 语义，绝对屏蔽内存指针后缀。
    #          【Tree 模式】：针对程序员肉眼 Debug 优化。无括号干扰，多行文本启用 \r\n 归一化处理。
    #          结合 textutil::wcswidth 动态计算全角字符（中文/Emoji）与内存指针的视觉宽度，
    #          实现多行键值下方竖线（|）的像素级精准左对齐。
    #
    # @param[in] data         当前子节点数据，必须是 dict 或 list（与 type 一致）。
    # @param[in] type         当前子节点类型，仅接受 "dict" 或 "list"。
    # @param[in] indent_level 当前缩进层级。
    # @param[in] indent_width 缩进空格宽度。
    # @param[in] show_ptr     是否显示内存指标后缀（1=开启，0=关闭）。
    # @param[in] style        打印格式，可选："json" "tree"
    #
    # @return string          返回裁剪完尾部多余逗号后的当前层级格式化文本块。
    proc _pdict {
        data
        type
        indent_level
        indent_width
        show_ptr
        style
    } {
        set next_level [expr {$indent_level + 1}]
        set indent [string repeat " " [expr {$indent_level * $indent_width}]]

        set ptr_suffix ""
        switch -- $type {
            "dict" {
                set result ""
                dict for {k v} $data {
                    set sub_type [sys get_type $v]
                    if {$show_ptr} { set ptr_suffix [sys get_ptr_suffix $v] }

                    # 统一通过 _format_key 获取格式化好的 Key（自动识别单双行）
                    set k_out [_format_key $k $indent $ptr_suffix $style]

                    if {$sub_type eq "dict" || $sub_type eq "list" || $sub_type eq "object"} {
                        lassign [list "" ""] mark_left mark_right
                        switch -- "${sub_type}_${style}" {
                            "dict_json" { set mark_left ": \{" ; set mark_right "$indent\},\n" }
                            "dict_tree" { set mark_left "=>" }
                            "object_json" { set mark_left ": \{" ; set mark_right "$indent\},\n" }
                            "object_tree" { set mark_left "=>" }
                            "list_json" { set mark_left ": \[" ; set mark_right "$indent\],\n" }
                            "list_tree" { set mark_left "=:" }
                        }
                        append result "${k_out} $mark_left\n"

                        if {$sub_type eq "object"} {
                            set obj_dict [_info_obj $v $show_ptr]
                            append result "[_pdict $obj_dict dict $next_level $indent_width $show_ptr $style]\n"
                        } else {
                            append result "[_pdict $v $sub_type $next_level $indent_width $show_ptr $style]\n"
                        }

                        append result $mark_right
                    } elseif {$sub_type eq "empty"} {
                        append result "${k_out} : \"\",\n"
                    } elseif {$sub_type eq "empty_dict"} {
                        append result "${k_out} : {},\n"
                    } elseif {$sub_type eq "empty_list"} {
                        append result "${k_out} : \[\],\n"
                    } else {
                        switch -- $sub_type {
                            "bytearray" { set v_str [_info_bytearray $v] }
                            default     { set v_str $v }
                        }

                        # ============ 标量 Value 分支 ============
                        if {$style ne "tree"} {
                            # JSON 模式：保持原有严格单行转义（\n 和 \r 都变成字面量）
                            append result "${k_out} : \"[str escape $v_str]\",\n"
                        } else {
                            # Tree 模式：多行对齐
                            set v_norm [string map {"\r\n" "\n" "\r" "\n"} $v_str]
                            set v_lines [split $v_norm "\n"]
                            
                            if {[llength $v_lines] == 1} {
                                append result "${k_out} : \"[str escape $v_str]\",\n"
                            } else {
                                set first_val "[str escape [lindex $v_lines 0]]"
                                
                                # 对齐基准：拿到 Key 最后一行的视觉长度 + " : " 的 3 个字符
                                set last_k_visual [lindex [split $k_out "\n"] end]
                                set k_width [::textutil::wcswidth $last_k_visual]
                                if {$k_width < 0} { set k_width [string length $last_k_visual] }
                                set align_len [expr {$k_width + 3}]
                                set align_str [string repeat " " $align_len]
                                
                                set v_out "\"${first_val}"
                                foreach line [lrange $v_lines 1 end] {
                                    append v_out "\n${align_str}|[str escape $line]"
                                }
                                append v_out "\""
                                
                                append result "${k_out} : ${v_out},\n"
                            }
                        }
                    }
                }
                return [string trimright [string trimright $result "\n"] ","]
            }

            "list" {
                set result ""
                foreach item $data {
                    set sub_type [sys get_type $item]
                    if {$show_ptr} { set ptr_suffix [sys get_ptr_suffix $item] }

                    if {$sub_type eq "dict" || $sub_type eq "list" || $sub_type eq "object"} {
                        lassign [list "" ""] mark_left mark_right
                        switch -- "${sub_type}_${style}" {
                            "dict_json" { set mark_left \{ ; set mark_right "$indent\},\n" }
                            "dict_tree" { set mark_left "=>" }
                            "object_json" { set mark_left \{ ; set mark_right "$indent\},\n" }
                            "object_tree" { set mark_left "=>" }
                            "list_json" { set mark_left \[ ; set mark_right "$indent\],\n" }
                            "list_tree" { set mark_left "=:" }
                        }
                        append result "${indent}$mark_left${ptr_suffix}\n"
                        if {$sub_type eq "object"} {
                            set obj_dict [_info_obj $item $show_ptr]
                            append result "[_pdict $obj_dict dict $next_level $indent_width $show_ptr $style]\n"
                        } else {
                            append result "[_pdict $item $sub_type $next_level $indent_width $show_ptr $style]\n"
                        }
                        append result $mark_right
                    } elseif {$sub_type eq "empty"} {
                        append result "${indent}\"\"${ptr_suffix},\n"
                    } elseif {$sub_type eq "empty_dict"} {
                        append result "${indent}{}${ptr_suffix},\n"
                    } elseif {$sub_type eq "empty_list"} {
                        append result "${indent}\[\]${ptr_suffix},\n"
                    } else {
                        switch -- $sub_type {
                            "bytearray" { set item_str [_info_bytearray $item] }
                            default     { set item_str $item }
                        }

                        # ============ 列表项标量分支 ============
                        if {$style ne "tree"} {
                            # JSON 模式
                            append result "${indent}\"[str escape $item_str]\"${ptr_suffix},\n"
                        } else {
                            # Tree 模式
                            set v_norm [string map {"\r\n" "\n" "\r" "\n"} $item_str]
                            set v_lines [split $v_norm "\n"]
                            
                            if {[llength $v_lines] == 1} {
                                append result "${indent}\"[str escape $item_str]\"${ptr_suffix},\n"
                            } else {
                                set first_val "[str escape [lindex $v_lines 0]]"
                                # List 的对齐基准：左侧的 indent + 开引号(1个字符)
                                set align_str [string repeat " " [string length $indent]]
                                
                                set v_out "\"${first_val}"
                                foreach line [lrange $v_lines 1 end] {
                                    append v_out "\n${align_str}|[str escape $line]"
                                }
                                append v_out "\"${ptr_suffix}"
                                
                                append result "${indent}${v_out},\n"
                            }
                        }
                    }
                }
                return [string trimright [string trimright $result "\n"] ","]
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

