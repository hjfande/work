#!/usr/bin/tclsh
# countones.tcl - 计算16进制数从bit0到指定bit的1的数量
# 用法: tclsh countones.tcl <hex_num> <bit_num>
# 示例: tclsh countones.tcl C 3  => 输出 2

proc countones {hex_str bit_num} {
    # 移除 0x/0X 前缀
    set hex_str [string trimleft $hex_str "0x"]
    set hex_str [string trimleft $hex_str "0X"]

    # 16进制字符串转整数
    set num [expr "0x$hex_str"]

    # 掩码: 保留 bit0 到 bit_num
    set mask [expr "(1 << ($bit_num + 1)) - 1"]
    set masked [expr "$num & $mask"]

    # 计算1的数量
    set count 0
    set n $masked
    while {$n > 0} {
        set count [expr "$count + ($n & 1)"]
        set n [expr "$n >> 1"]
    }

    return $count
}

# 命令行模式
if {$argc == 2} {
    set hex_num [lindex $argv 0]
    set bit_num [lindex $argv 1]
    puts [countones $hex_num $bit_num]
} else {
    puts stderr "Usage: tclsh countones.tcl <hex_num> <bit_num>"
    puts stderr "Example: tclsh countones.tcl C 3"
    exit 1
}
