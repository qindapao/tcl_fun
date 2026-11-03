#!/usr/bin/env tclsh9

# @file errors.tcl
# @brief 中心化错误码体系与结构化错误抛出
#
# @details 本模块是 tutils 工具箱的【错误码唯一真相源】。
#          - 所有模块必须经由此模块的门面抛错，禁止在调用点自定义 errorcode。
#          - 错误码两段式：主码（大类，白名单）+ 副码（细分原因，按主码分组登记）。
#          - 双门面：panic 用于系统级不可恢复错误，主码固定；
#                    fail  用于业务级可分类错误，显式主码+副码。
#          - 统一 `return -code error -errorcode` 抛出，默认结构为 [list $main $sub]；
#            若调用方传入 extra 数据，则追加在尾部（如 [list $main $sub $exit_code]）。
#            catch 端通过 -errorcode 拿到标准列表，前两元素固定为主码/副码。

namespace eval ::errors {
    namespace export {[a-z]*}
    namespace ensemble create

    # @brief 【错误码总表】主码 -> 副码列表（内部只读，校验唯一依据）
    # @details 新增错误码只能改此处。若将来副码需携带元数据，
    #          可迁移为“副码作键 + 值放元数据字典”，迁移成本低。
    variable CODES [dict create \
        SYS_SYSTEM_PANIC {
            ARGS_EMPTY
            PIPE_CLOSE_FAILED
            OPEN_FAILED
            REMOTE_ARGS_EMPTY
            LOCAL_FILE_NOT_FOUND
            LOCAL_DIR_NOT_FOUND
        } \
        SYS_USAGE_ERROR {
            BAD_ARG
            MISSING_ARG
        } \
        SYS_IO_ERROR {
            ENOENT
            EACCES
        } \
        SYS_EXEC_ERROR {} \
    ]

    # @brief 【内部核心】主码+副码双重白名单校验并结构化抛错（私有）
    # @details 校验失败用 `error`（不带 -errorcode），属于开发者用错门面参数的
    #          开发期错误；校验通过后用 `return -code error -errorcode` 抛结构化错误，
    #          默认 -level 1，栈帧完整。
    #          支持两种主码形态：
    #          - 有副码：CODES 中登记副码列表，校验副码后 -errorcode 为 [list $main $sub]。
    #          - 无副码：CODES 中登记空列表，跳过副码校验，-errorcode 为 [list $main]。
    #          若传了 extra，动态数据追加到 -errorcode 尾部。
    #
    # @param[in] main    主码
    # @param[in] sub     副码。主码无副码时传空字符串 ""，此时跳过副码校验。
    # @param[in] message 错误消息
    # @param[in] extra   可选。追加到 -errorcode 尾部的动态数据列表，
    #                    用于携带无法枚举进 CODES 的信息（如退出码）。
    #                    默认空列表。
    #
    # @return 不返回（纯 thrower）
    # @throws error 主码/副码不合法（开发期错误）；或合法时抛出结构化错误，
    #               -errorcode 为 [list $main {*}$extra] 或 [list $main $sub {*}$extra]
    proc _raise {main sub message {extra {}}} {
        variable CODES
        if {![dict exists $CODES $main]} {
            set main_codes_str [join [dict keys $CODES] {, }]
            error "errors: unknown main code '$main'; expected one of: $main_codes_str"
        }
        set valid_subs [dict get $CODES $main]

        # 主码无副码：跳过副码校验，-errorcode 直接 [list $main {*}$extra]
        if {[llength $valid_subs] == 0} {
            set ecode [list $main]
            if {[llength $extra]} { lappend ecode {*}$extra }
            return -code error -errorcode $ecode $message
        }

        if {$sub ni $valid_subs} {
            set valid_subs_str [join $valid_subs {, }]
            error "errors: invalid sub code '$sub' for main '$main'; expected one of: $valid_subs_str"
        }
        set ecode [list $main $sub]
        if {[llength $extra]} { lappend ecode {*}$extra }
        return -code error -errorcode $ecode $message
    }

    # @brief 【门面 1】系统级 panic，主码固定 SYS_SYSTEM_PANIC
    # @details 用于不可恢复的系统级异常（命令不存在、管道崩溃等）。
    #          调用示例：panic ARGS_EMPTY "..."
    #          catch 端 -errorcode 为 {SYS_SYSTEM_PANIC <sub>}。
    #
    # @param[in] sub     副码
    # @param[in] message 错误消息
    #
    # @return 不返回（纯 thrower）
    # @throws error 副码不合法；或合法时抛出结构化 panic 错误
    proc panic {sub message} {
        _raise SYS_SYSTEM_PANIC $sub $message
    }

    # @brief 【门面 2】业务级 fail，显式主码
    # @details 用于可分类处理的业务错误。
    #          调用示例：fail SYS_IO_ERROR ENOENT "file not found"
    #                    fail SYS_EXEC_ERROR EXIT_NONZERO "..." [list $exit_code]
    #          catch 端可按主码 switch 分支，再按副码细分；
    #          若传了 extra，动态数据在 -errorcode 的第 3 个元素起。
    #
    # @param[in] main    主码
    # @param[in] sub     副码
    # @param[in] message 错误消息
    # @param[in] extra   可选。追加到 -errorcode 尾部的动态数据列表。
    #
    # @return 不返回（纯 thrower）
    # @throws error 主码/副码不合法；或合法时抛出结构化 fail 错误
    proc fail {main sub message {extra {}}} {
        _raise $main $sub $message $extra
    }

    # @brief 【只读访问器】返回整个错误码总表（dict 副本，值语义）
    # @return dict 主码 -> 副码列表
    proc codes {} {
        variable CODES
        return $CODES
    }

    # @brief 【只读访问器】返回指定主码下的合法副码列表
    # @details 主码不存在时抛出与 _raise 一致格式的错误，列出所有合法主码。
    #
    # @param[in] main 主码
    # @return list 该主码下所有合法副码
    # @throws error 主码不在 CODES 中
    proc sub-codes {main} {
        variable CODES
        if {![dict exists $CODES $main]} {
            set main_codes_str [join [dict keys $CODES] {, }]
            error "errors: unknown main code '$main'; expected one of: $main_codes_str"
        }
        return [dict get $CODES $main]
    }
}

