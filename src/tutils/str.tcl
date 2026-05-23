#!/usr/bin/env tclsh9

# 声明本文件属于 tutils 工具箱的 1.0 版本（供 pkg_mkIndex 识别）
package provide tutils 1.0

namespace eval ::str {
    # 导出所有小写开头的过程，并建立 Ensemble 集体门面
    namespace export {[a-z]*}
    # 创建 Ensemble 集体门面，将 ::str::escape 简化为极具现代感的 [str escape]
    namespace ensemble create

    # /**
    #  * @brief 符合 RFC 8259 工业标准的字串安全净化与转义器 (str escape)
    #  * @details 优先通过 string map 处理高频常用字符，随后利用 Tcl 9 原生正则引擎，
    #  *          一枪点杀所有 ASCII < 32 的无名幽灵控制字符，将其化为 \u00XX 格式。
    #  *
    #  * @param[in] data  原始未经处理的标量字串。
    #  * @return string   100% 安全、无歧义、可直接贴入标准 JSON 解析器的合规字串。
    #  */
    proc escape {data} {
        # 第一防线：高频字符与反斜杠优先映射（【核心铁律】"\\" 必须排在第一行）
        set safe_data [string map {
            "\\" "\\\\"
            "\"" "\\\""
            "\a" "\\a"
            "\b" "\\b"
            "\f" "\\f"
            "\n" "\\n"
            "\r" "\\r"
            "\t" "\\t"
            "\v" "\\v"
        } $data]

        # 【核心第二防线】：动态全网雷达扫描，精准狙击那些连字母名字都没有的 ASCII < 32 幽灵控制字符
        # 初始化雷达的起点探测计数器变量 count 为 0，代表从字串的最左侧（第 0 个字符）开始搜索
        set count 0

        # 启动 while 条件循环。利用 regexp 指令在 $safe_data 字串中搜索符合正则表达式 {[\x00-\x1F]} 的字符。
        #  -nocase: 忽略大小写（防御性参数）
        #  -indices: 让 Tcl 核心不要返回字符本身，而是返回匹配到的【起始索引和结束索引】列表（例如：{12 12}）
        #  -start $count: 强制雷达从当前计数器 $count 的位置向右看，绝对不往回看，防止陷入死循环
        #  {[\x00-\x1F]}: 正则表达式，精准锁定 ASCII 码表在 0 到 31 之间的所有纯不可见幽灵控制字符
        #  match_idx: 将捕获到的索引列表（形如 {12 12}）塞入这个临时占位变量中
        while {[regexp -nocase -indices -start $count {[\x00-\x1F]} $safe_data match_idx]} {
            # 利用 lassign 指令，把 match_idx 列表中的起始索引解包赋值给 start_idx，结束索引赋值给 end_idx
            # 因为我们每次只匹配单个字符，所以 start_idx 和 end_idx 其实指向同一个物理位置
            lassign $match_idx start_idx end_idx

            # 利用 string index 指令，精准提取出 $safe_data 在 start_idx 物理位置上的那个不可见控制字符
            set char [string index $safe_data $start_idx]

            # 呼叫二进制扫描指令 binary scan，以有符号单字节（c）的二进制格式，读取这个字符的底层内存
            # 将其转化为真实的十进制 ASCII 数值，并将这个数值赋值给新变量 code
            binary scan $char c code

            # 利用 format 指令，将获取到的 code 数值（先与 0xFF 进行位与运算防止符号位扩展）
            # 格式化为 2 位数的十六进制小写字串（例如：ASCII 1 变成 "01"，ASCII 31 变成 "1f"）
            set hex_code [format "%02x" [expr {$code & 0xFF}]]

            # 按照标准 JSON RFC 8259 规范，将十六进制编码重组为国际通用的 \u00XX 字串
            # 注意：这里的反斜杠需要手写两个（"\\u"），代表这是一个合法的纯文字后缀
            set u_esc "\\u00${hex_code}"

            # 呼叫 string replace 指令，把 $safe_data 里面从 start_idx 到 end_idx 处的那个幽灵字符抹除，
            # 并在原地无损替换成全新的、长度为 6 的可见文字字串 $u_esc，然后将新构造的大字串重新赋值给 safe_data
            # 因为tcl9的写时复制的特性所以这里的效率并不会低
            set safe_data [string replace $safe_data $start_idx $end_idx $u_esc]

            # 核心时序控制：因为原来的 1 个字符被你强行撑大了成 6 个字符的 \u00XX
            # 为了让雷达下一次扫描时，不要去重叠扫描新生成的 \u，我们将计数器更新为 start_idx + 6，直接跃过安全区
            set count [expr {$start_idx + 6}]
        }

        return $safe_data
    }
}

