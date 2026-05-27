#!/usr/bin/perl
#============================================================================
# bind_gen.perl
#   搜索 _idc_wrap.v 文件，提取中断映射关系
#   生成 bind int_distributor_sva 实例 (每ic编号一个实例)
#   用法: perl bind_gen.perl <input_path>
#============================================================================
use strict;
use warnings;
use File::Find;
use File::Basename;

#--------------------------------------------------------------------------
# 命令行参数
#--------------------------------------------------------------------------
my $input_path = $ARGV[0];
if (!defined $input_path) {
    print STDERR "Usage: $0 <input_path>\n";
    print STDERR "  <input_path> : directory or file to search for *_idc_wrap.v\n";
    exit 1;
}

if (!-e $input_path) {
    die "Error: path '$input_path' does not exist.\n";
}

#--------------------------------------------------------------------------
# 全局数据结构
#--------------------------------------------------------------------------
my %all_mapping;  # { DESIGN_NAME => { type => { number => signal_name } } }
my %design_dir;    # { DESIGN_NAME => file_directory }
our $GLOBAL_ERROR = 0;  # 连续性检查错误标志

#--------------------------------------------------------------------------
# 正则表达式定义
#--------------------------------------------------------------------------
my %regex_map = (
    posedge    => qr/^\s*assign\s+posedge_int_bus\s*\[\s*(\d+)\s*\]\s*=\s*([^;]+?)\s*;\s*$/,
    negedge    => qr/^\s*assign\s+negedge_int_bus\s*\[\s*(\d+)\s*\]\s*=\s*([^;]+?)\s*;\s*$/,
    high_level => qr/^\s*assign\s+high_level_int_bus\s*\[\s*(\d+)\s*\]\s*=\s*([^;]+?)\s*;\s*$/,
    low_level  => qr/^\s*assign\s+low_level_int_bus\s*\[\s*(\d+)\s*\]\s*=\s*([^;]+?)\s*;\s*$/,
);

my %ic_regex_map = (
    edge_ic  => qr/^\s*\.edge_int_to_ic(\d+)\s*\(\s*([^)]+?)\s*\)\s*,?\s*$/,
    level_ic => qr/^\s*\.level_int_to_ic(\d+)\s*\(\s*([^)]+?)\s*\)\s*,?\s*$/,
    merge_ic => qr/^\s*\.merge_int_to_ic(\d+)\s*\(\s*([^)]+?)\s*\)\s*,?\s*$/,
);

my $param_regex = qr/^\s*\.([A-Z][A-Z_0-9]*)\s*\(\s*(\d+(?:'[hbodHBOD][0-9a-fA-F_xzXZ_]+)?)\s*\)\s*,?\s*$/;

#--------------------------------------------------------------------------
# 辅助函数：计算十六进制字符串中 1 的数量
#--------------------------------------------------------------------------
sub count_ones_in_hex {
    my ($hex_str) = @_;
    return 0 unless defined $hex_str;
    
    $hex_str =~ s/^\d+'[hHbBdDoO]//;
    $hex_str =~ s/^[hHbBdDoO]'//;
    $hex_str =~ s/_//g;
    
    my %hex_to_ones = (
        '0'=>0,'1'=>1,'2'=>1,'3'=>2,'4'=>1,'5'=>2,'6'=>2,'7'=>3,
        '8'=>1,'9'=>2,'a'=>2,'b'=>3,'c'=>2,'d'=>3,'e'=>3,'f'=>4,
        'A'=>2,'B'=>3,'C'=>2,'D'=>3,'E'=>3,'F'=>4,
    );
    
    my $count = 0;
    foreach my $c (split //, $hex_str) {
        $count += $hex_to_ones{$c} // 0;
    }
    return $count;
}

#--------------------------------------------------------------------------
# 辅助函数：从 entries {number=>signal} 生成总线拼接字符串
#   按 bit 从高位到低位拼接: {signal[N-1], ..., signal[0]}
#--------------------------------------------------------------------------
sub build_bus_concat {
    my ($entries) = @_;
    return "1'b0" if scalar keys %$entries == 0;
    
    my @signals;
    foreach my $num (sort { $b <=> $a } keys %$entries) {
        push @signals, $entries->{$num};
    }
    
    if (scalar @signals == 1) {
        return $signals[0];
    } else {
        return "{" . join(", ", @signals) . "}";
    }
}

#--------------------------------------------------------------------------
# 辅助函数：处理 signal 为 regbank_merge_int_bus 的命名格式
#   末尾 _int -> _rdat，全大写
#--------------------------------------------------------------------------
sub process_sig_for_regbank {
    my ($sig) = @_;
    return $sig if $sig =~ /^1'b[01]$/;  # 默认填充值不处理
    $sig =~ s/_int$//;        # 去掉末尾 _int
    $sig = uc($sig);           # 主体大写
    $sig .= "_rdat";           # 追加小写 _rdat
    return $sig;
}

#--------------------------------------------------------------------------
# 辅助函数：解析十六进制 bitmap 为 bit 数组
#   返回 [$bit0, $bit1, ...]，1 表示该位有效
#--------------------------------------------------------------------------
sub parse_bitmap_to_bits {
    my ($hex_str, $max_bits) = @_;
    return [] if !defined $hex_str || $hex_str eq "";
    
    $hex_str =~ s/^\d+'[hH]//;
    $hex_str =~ s/_//g;
    
    my @bits;
    my $bit_idx = 0;
    
    # 从右到左处理（从最低位开始）
    foreach my $hex_char (reverse split //, $hex_str) {
        my $val = hex($hex_char);
        for (my $i = 0; $i < 4 && $bit_idx < $max_bits; $i++) {
            $bits[$bit_idx] = ($val >> $i) & 1;
            $bit_idx++;
        }
    }
    
    return \@bits;
}

#--------------------------------------------------------------------------
# 辅助函数：根据 bitmap 过滤 signal
#   只保留 bitmap 对应位为 1 的 signal
#--------------------------------------------------------------------------
sub filter_signals_by_bitmap {
    my ($entries, $bitmap_bits) = @_;
    my @filtered;
    
    for (my $i = 0; $i < scalar(@$bitmap_bits); $i++) {
        if ($bitmap_bits->[$i] && exists $entries->{$i}) {
            push @filtered, {bit => $i, sig => $entries->{$i}};
        }
    }
    
    return \@filtered;
}

#--------------------------------------------------------------------------
# 辅助函数：生成 regbank_merge_int_bus 宏定义
#   使用所有 assign 的位，不按 bitmap 过滤
#   宏参数 ic_num 通过 ``ic``ic_num`` 连接到信号名中
#   从 ${wrap_name}_intr_distribute_ctrl.v 读取每个 sig 的实际 merge group
#--------------------------------------------------------------------------
sub build_regbank_macro {
    my ($design_name, $wrap_name, $hl_entries, $ll_entries, $file_dir) = @_;
    
    # 读取外部控制文件，建立 sig -> merge_group 映射
    my %sig_to_group;
    my $ctrl_file = "$file_dir/${wrap_name}_intr_distribute_ctrl.sv";
    if (!-f $ctrl_file) {
        die "ERROR: Control file '$ctrl_file' not found for regbank macro generation.\n";
    }
    open(my $cfh, '<', $ctrl_file) or die "ERROR: cannot open '$ctrl_file': $!\n";
    while (my $line = <$cfh>) {
        chomp($line);
        # 匹配 ${wrap_name}_ic0_merge_int(\d+)_${sig}_rdat
        while ($line =~ /${wrap_name}_ic0_merge_int(\d+)_([A-Za-z0-9_]+)_rdat/g) {
            $sig_to_group{$2} = $1;
        }
    }
    close($cfh);
    
    # 直接使用所有 assign 的位（高位到低位排序）
    my @hl_list;
    foreach my $num (sort { $b <=> $a } keys %$hl_entries) {
        push @hl_list, {bit => $num, sig => $hl_entries->{$num}};
    }
    my @ll_list;
    foreach my $num (sort { $b <=> $a } keys %$ll_entries) {
        push @ll_list, {bit => $num, sig => $ll_entries->{$num}};
    }
    
    my @entries = (@hl_list, @ll_list);
    
    # 为每个entry添加group信息，任何sig匹配不到则报错退出
    foreach my $entry (@entries) {
        if (!exists $sig_to_group{$entry->{sig}}) {
            die "ERROR: Cannot find merge group for signal '$entry->{sig}' in '$ctrl_file'.\n";
        }
        $entry->{group} = $sig_to_group{$entry->{sig}};
    }
    
    # 按group降序排列，同一group的排在一起；group相同则保持bit高位在前
    @entries = sort { $b->{group} <=> $a->{group} || $b->{bit} <=> $a->{bit} } @entries;
    
    # 生成signal_templates
    my @signal_templates;
    foreach my $entry (@entries) {
        my $g = $entry->{group};
        push @signal_templates, "`REG_BANK.${wrap_name}_ic``ic_num``_merge_int${g}_$entry->{sig}_rdat";
    }
    
    my $macro_name = uc($wrap_name) . "_MERGE_REG";
    
    my $macro_def;
    if (scalar @signal_templates == 0) {
        $macro_def = "`define $macro_name(ic_num) 1'b0\n";
    } elsif (scalar @signal_templates == 1) {
        $macro_def = "`define $macro_name(ic_num) $signal_templates[0]\n";
    } else {
        $macro_def = "`define $macro_name(ic_num) { \\\n";
        for (my $i = 0; $i < scalar(@signal_templates); $i++) {
            my $comma = ($i < scalar(@signal_templates) - 1) ? "," : "";
            $macro_def .= "        $signal_templates[$i]$comma \\\n";
        }
        $macro_def .= "    }\n";
    }
    
    # 生成 merge_int_bus 宏
    my @merge_bus_templates;
    foreach my $entry (@entries) {
        push @merge_bus_templates, "$design_name.$entry->{sig}";
    }
    
    my $merge_bus_macro_name = uc($design_name) . "_MERGE_BUS";
    
    my $merge_bus_macro_def;
    if (scalar @merge_bus_templates == 0) {
        $merge_bus_macro_def = "`define $merge_bus_macro_name 1'b0\n";
    } elsif (scalar @merge_bus_templates == 1) {
        $merge_bus_macro_def = "`define $merge_bus_macro_name $merge_bus_templates[0]\n";
    } else {
        $merge_bus_macro_def = "`define $merge_bus_macro_name { \\\n";
        for (my $i = 0; $i < scalar(@merge_bus_templates); $i++) {
            my $comma = ($i < scalar(@merge_bus_templates) - 1) ? "," : "";
            $merge_bus_macro_def .= "        $merge_bus_templates[$i]$comma \\\n";
        }
        $merge_bus_macro_def .= "    }\n";
    }
    
    return ($macro_def, $macro_name, $merge_bus_macro_def, $merge_bus_macro_name);
}

#--------------------------------------------------------------------------
# 处理单个文件
#--------------------------------------------------------------------------
sub parse_file {
    my ($file_path) = @_;
    my $basename = basename($file_path);
    
    # design_name = 文件名去掉 .v 后缀
    my $design_name = $basename;
    $design_name =~ s/\.v$//;
    
    if ($basename !~ /_idc_wrap\.v$/) {
        print STDERR "Warning: file '$basename' does not match *_idc_wrap.v, skipping.\n";
        return;
    }
    
    print "[INFO] Parsing: $file_path  (DESIGN_NAME=$design_name)\n";
    
    open(my $fh, '<', $file_path) or die "Error: cannot open '$file_path': $!\n";
    
    my %file_mapping = (
        posedge    => {},
        negedge    => {},
        high_level => {},
        low_level  => {},
        edge_ic    => {},
        level_ic   => {},
        merge_ic   => {},
        params     => {},
    );
    
    my $line_num = 0;
    while (my $line = <$fh>) {
        $line_num++;
        chomp($line);
        
        next if $line =~ /^\s*$/;
        next if $line =~ /^\s*\/\//;
        
        my $matched = 0;
        
        # 匹配 assign 语句
        foreach my $type (keys %regex_map) {
            my $regex = $regex_map{$type};
            if ($line =~ $regex) {
                my $bus_number = $1;
                my $signal_name = $2;
                $signal_name =~ s/\s+/ /g;
                $signal_name =~ s/^\s+|\s+$//g;
                
                if (exists $file_mapping{$type}{$bus_number}) {
                    print STDERR "Warning: $design_name line $line_num: $type\_int_bus[$bus_number] redefined\n";
                }
                $file_mapping{$type}{$bus_number} = $signal_name;
                $matched = 1;
                last;
            }
        }
        
        # 匹配 .*_int_to_ic<number> (signal)
        if (!$matched) {
            foreach my $type (keys %ic_regex_map) {
                my $regex = $ic_regex_map{$type};
                if ($line =~ $regex) {
                    my $ic_number = $1;
                    my $signal_name = $2;
                    $signal_name =~ s/\s+/ /g;
                    $signal_name =~ s/^\s+|\s+$//g;
                    
                    if (exists $file_mapping{$type}{$ic_number}) {
                        print STDERR "Warning: $design_name line $line_num: $type\_to_ic$ic_number redefined\n";
                    }
                    $file_mapping{$type}{$ic_number} = $signal_name;
                    $matched = 1;
                    last;
                }
            }
        }
        
        # 匹配 parameter 赋值
        if (!$matched && $line =~ $param_regex) {
            my $param_name = $1;
            my $param_value = $2;
            if (exists $file_mapping{params}{$param_name}) {
                print STDERR "Warning: $design_name line $line_num: param $param_name redefined\n";
            }
            $file_mapping{params}{$param_name} = $param_value;
        }
    }
    
    close($fh);
    
    # 检查 assign 语句的连续性
    my $file_error = 0;
    foreach my $type (qw(posedge negedge high_level low_level)) {
        my $entries = $file_mapping{$type};
        my $count = scalar keys %$entries;
        next if $count == 0;
        
        my @nums = sort { $a <=> $b } keys %$entries;
        my $max_num = $nums[-1];
        
        # 检查是否从0开始连续到max_num
        my @missing;
        for (my $i = 0; $i <= $max_num; $i++) {
            if (!exists $entries->{$i}) {
                push @missing, $i;
            }
        }
        
        if (scalar @missing > 0) {
            print STDERR "ERROR: $design_name: $type\_int_bus assign is not continuous. "
                       . "Missing bit(s): " . join(", ", @missing) . "\n";
            $file_error = 1;
        }
    }
    
    if ($file_error) {
        print STDERR "ERROR: $design_name parsing failed due to discontinuous assign.\n";
        return 1;  # 返回错误码，不保存此文件的映射
    }
    
    $all_mapping{$design_name} = \%file_mapping;
    $design_dir{$design_name} = dirname($file_path);
    
    my $total = 0;
    foreach my $type (qw(posedge negedge high_level low_level edge_ic level_ic merge_ic params)) {
        my $count = scalar keys %{$file_mapping{$type}};
        $total += $count;
        print "       -> $type: $count entries\n";
    }
    print "       -> Total: $total entries\n";
    return 0;
}

#--------------------------------------------------------------------------
# 遍历目录
#--------------------------------------------------------------------------
sub wanted {
    if (-f $_ && /_idc_wrap\.v$/) {
        my $rc = parse_file($File::Find::name);
        $GLOBAL_ERROR = 1 if $rc != 0;
    }
}

print "[INFO] Searching under: $input_path\n\n";

if (-d $input_path) {
    find(\&wanted, $input_path);
} elsif (-f $input_path && $input_path =~ /_idc_wrap\.v$/) {
    my $rc = parse_file($input_path);
    $GLOBAL_ERROR = 1 if $rc != 0;
} else {
    die "Error: '$input_path' is not a valid directory or *_idc_wrap.v file.\n";
}

#--------------------------------------------------------------------------
# 打印汇总到终端
#--------------------------------------------------------------------------
print "\n" . "="x70 . "\n";
print "SUMMARY: Interrupt Mapping Relationships\n";
print "="x70 . "\n\n";

foreach my $design_name (sort keys %all_mapping) {
    my $mapping = $all_mapping{$design_name};
    
    print "------------------------------------------------------------------------\n";
    print "DESIGN_NAME: $design_name\n";
    print "------------------------------------------------------------------------\n";
    
    # print assign-to-bus conversion
    foreach my $type (qw(posedge negedge high_level low_level)) {
        my $entries = $mapping->{$type};
        next if scalar keys %$entries == 0;
        my $concat = build_bus_concat($entries);
        print "  .${type}_int_bus ($concat),\n";
    }
    
    # print ic connections
    foreach my $type (qw(edge_ic level_ic merge_ic)) {
        my $entries = $mapping->{$type};
        next if scalar keys %$entries == 0;
        foreach my $num (sort { $a <=> $b } keys %$entries) {
            my $sig = $entries->{$num};
            my $port_name = $type;
            $port_name =~ s/_ic$//;
            print "  .${port_name}_int_to_ic$num ($sig),\n";
        }
    }
    print "\n";
}

print "="x70 . "\n";
print "Total files: " . scalar(keys %all_mapping) . "\n";
print "="x70 . "\n";

#--------------------------------------------------------------------------
# 生成 bind 实例化文件
#   design名称为搜索到的文件名（不含.v后缀）
#   每个 ic 编号对应一个 bind 实例
#   参数从 bitmap 中 1 的数量计算
#--------------------------------------------------------------------------
my $bind_sv_file = "bind_idc_wrap.sv";
open(my $bind_fh, '>', $bind_sv_file) or die "Error: cannot write '$bind_sv_file': $!\n";

print $bind_fh "// Auto-generated bind file by bind_gen.perl\n";
print $bind_fh "// Do NOT edit manually\n\n";

foreach my $design_name (sort keys %all_mapping) {
    my $mapping = $all_mapping{$design_name};
    my $params = $mapping->{params};
    
    # 收集所有 ic 编号
    my %ic_numbers;
    foreach my $type (qw(edge_ic level_ic merge_ic)) {
        foreach my $num (keys %{$mapping->{$type}}) {
            $ic_numbers{$num} = 1;
        }
    }
    
    next if scalar keys %ic_numbers == 0;
    
    print $bind_fh "// ============================================================================\n";
    print $bind_fh "// Bind int_distributor_sva for DESIGN: $design_name\n";
    print $bind_fh "// ============================================================================\n\n";
    
    # 预计算总线拼接（输入直接绑定到全部实例，不过滤）
    my %bus_concat;
    foreach my $type (qw(posedge negedge high_level low_level)) {
        my $entries = $mapping->{$type};
        next if scalar keys %$entries == 0;
        $bus_concat{$type} = build_bus_concat($entries);
    }
    
    # 生成输入连接宏（所有实例共享）
    my $macro_name = uc($design_name) . "_IDC_INPUTS";
    print $bind_fh "// Input connections macro (shared across all IC instances)\n";
    print $bind_fh "`define $macro_name \\\n";
    
    my @macro_lines;
    foreach my $type (qw(posedge negedge high_level low_level)) {
        next if !exists $bus_concat{$type};
        push @macro_lines, "    .${type}_int_bus    ($bus_concat{$type})";
    }
    
    for (my $i = 0; $i < scalar(@macro_lines); $i++) {
        if ($i < scalar(@macro_lines) - 1) {
            print $bind_fh $macro_lines[$i] . ", \\\n";
        } else {
            print $bind_fh $macro_lines[$i] . "\n";
        }
    }
    print $bind_fh "\n";
    
    # 生成 regbank_merge_int_bus 宏定义（所有实例共享）
    my $wrap_name = $design_name;
    $wrap_name =~ s/_idc_wrap$//;
    my $file_dir = $design_dir{$design_name} // ".";
    my ($regbank_macro_def, $regbank_macro_name, $merge_bus_macro_def, $merge_bus_macro_name) = build_regbank_macro($design_name, $wrap_name,
        $mapping->{high_level}, $mapping->{low_level}, $file_dir);
    print $bind_fh "// regbank_merge_int_bus macro (shared across all IC instances)\n";
    print $bind_fh $regbank_macro_def;
    print $bind_fh "\n";
    print $bind_fh "// merge_int_bus macro (shared across all IC instances)\n";
    print $bind_fh $merge_bus_macro_def;
    print $bind_fh "\n";
    
    # 为每个 ic 编号生成 bind
    foreach my $ic_num (sort { $a <=> $b } keys %ic_numbers) {
        my $inst_name = "u_int_distributor_sva_ic${ic_num}";
        
        # 从 bitmap 计算参数值
        my %bitmap_params = (
            posedge    => "POS_EDGE_INT_BITMAP_IC${ic_num}",
            negedge    => "NEG_EDGE_INT_BITMAP_IC${ic_num}",
            high_level => "HIGH_LEVEL_INT_BITMAP_IC${ic_num}",
            low_level  => "LOW_LEVEL_INT_BITMAP_IC${ic_num}",
        );
        
        my %ic_param_vals;
        my %ic_param_src;
        my %ic_bitmap_vals;
        foreach my $type (qw(posedge negedge high_level low_level)) {
            my $param_name = uc($type) . "_INT_NUM";
            my $bitmap_name = $bitmap_params{$type};
            my $bitmap_val = $params->{$bitmap_name};
            
            # 参数值优先使用设计文件中的原始参数
            if (defined $params->{$param_name}) {
                $ic_param_vals{$type} = $params->{$param_name};
                $ic_param_src{$type} = "param:$param_name";
            } elsif (defined $bitmap_val) {
                $ic_param_vals{$type} = count_ones_in_hex($bitmap_val);
                $ic_param_src{$type} = "$bitmap_name=$bitmap_val";
            } else {
                $ic_param_vals{$type} = scalar keys %{$mapping->{$type}};
                $ic_param_src{$type} = "fallback:assign_count";
            }
            
            $ic_bitmap_vals{$type} = $bitmap_val // "";
        }
        
        # 提取 ic 信号
        my $edge_ic_sig  = $mapping->{edge_ic}{$ic_num}  // "";
        my $level_ic_sig = $mapping->{level_ic}{$ic_num} // "";
        my $merge_ic_sig = $mapping->{merge_ic}{$ic_num} // "";
        
        print $bind_fh "// --- IC$ic_num ---\n";
        foreach my $type (qw(posedge negedge high_level low_level)) {
            my $type_upper = uc($type);
            print $bind_fh "//   ${type_upper}_INT_TO_IC_NUM = $ic_param_vals{$type}  ($ic_param_src{$type})\n";
        }
        print $bind_fh "\n";
        
        my $edge_ic_width  = (($ic_bitmap_vals{posedge} ne "")    ? count_ones_in_hex($ic_bitmap_vals{posedge})    : scalar(keys %{$mapping->{posedge}}))
                           + (($ic_bitmap_vals{negedge} ne "")    ? count_ones_in_hex($ic_bitmap_vals{negedge})    : scalar(keys %{$mapping->{negedge}}));
        my $level_ic_width = (($ic_bitmap_vals{high_level} ne "") ? count_ones_in_hex($ic_bitmap_vals{high_level}) : scalar(keys %{$mapping->{high_level}}))
                           + (($ic_bitmap_vals{low_level} ne "")  ? count_ones_in_hex($ic_bitmap_vals{low_level})  : scalar(keys %{$mapping->{low_level}}));
        
        print $bind_fh "bind $design_name int_distributor_sva #(\n";
        print $bind_fh "    .POS_EDGE_INT_NUM   (" . scalar(keys %{$mapping->{posedge}}) . "),\n";
        print $bind_fh "    .NEG_EDGE_INT_NUM   (" . scalar(keys %{$mapping->{negedge}}) . "),\n";
        print $bind_fh "    .HIGH_LEVEL_INT_NUM (" . scalar(keys %{$mapping->{high_level}}) . "),\n";
        print $bind_fh "    .LOW_LEVEL_INT_NUM  (" . scalar(keys %{$mapping->{low_level}}) . "),\n";
        print $bind_fh "    .EDGE_INT_TO_IC_WIDTH  ($edge_ic_width),\n";
        print $bind_fh "    .LEVEL_INT_TO_IC_WIDTH ($level_ic_width),\n";
        if ($ic_bitmap_vals{posedge} ne "") {
            print $bind_fh "    .POS_EDGE_INT_BITMAP   ($ic_bitmap_vals{posedge}),\n";
        }
        if ($ic_bitmap_vals{negedge} ne "") {
            print $bind_fh "    .NEG_EDGE_INT_BITMAP   ($ic_bitmap_vals{negedge}),\n";
        }
        if ($ic_bitmap_vals{high_level} ne "") {
            print $bind_fh "    .HIGH_LEVEL_INT_BITMAP ($ic_bitmap_vals{high_level}),\n";
        }
        if ($ic_bitmap_vals{low_level} ne "") {
            print $bind_fh "    .LOW_LEVEL_INT_BITMAP  ($ic_bitmap_vals{low_level}),\n";
        }
        print $bind_fh "    .USE_REGBANK_PIN    (1)\n";
        print $bind_fh ") $inst_name (\n";
        print $bind_fh "    `$macro_name,\n";
        print $bind_fh "    .apb_clk            (apb_clk),\n";
        print $bind_fh "    .apb_rstn           (apb_rstn),\n";
        
        # enable / mask 接 '0
        print $bind_fh "    .high_level_enable  ('0),\n";
        print $bind_fh "    .high_level_mask    ('0),\n";
        print $bind_fh "    .low_level_enable   ('0),\n";
        print $bind_fh "    .low_level_mask     ('0),\n";
        
        # regbank_merge_int_bus
        print $bind_fh "    .regbank_merge_int_bus (`$regbank_macro_name($ic_num)),\n";
        
        # ic 信号连接
        if ($edge_ic_sig ne "") {
            print $bind_fh "    .edge_int_to_ic     ($edge_ic_sig),\n";
        } else {
            print $bind_fh "    .edge_int_to_ic     (),\n";
        }
        
        if ($level_ic_sig ne "") {
            print $bind_fh "    .level_int_to_ic    ($level_ic_sig),\n";
        } else {
            print $bind_fh "    .level_int_to_ic    (),\n";
        }
        
        if ($merge_ic_sig ne "") {
            print $bind_fh "    .merge_int_to_ic    ($merge_ic_sig),\n";
        } else {
            print $bind_fh "    .merge_int_to_ic    (),\n";
        }
        
        print $bind_fh "    .merge_int_bus      (`$merge_bus_macro_name),\n";
        print $bind_fh "    .dft_dc_scan_clk    (dft_dc_scan_clk),\n";
        print $bind_fh "    .dft_dc_scan_mode   (dft_dc_scan_mode),\n";
        print $bind_fh "    .dft_dc_scan_rst_n  (dft_dc_scan_rst_n)\n";
        print $bind_fh ");\n\n";
    }
}

close($bind_fh);
print "\n[INFO] Bind file saved to: $bind_sv_file\n";

if ($GLOBAL_ERROR) {
    print STDERR "\nERROR: Some files have discontinuous assign, exiting with code 1.\n";
    exit 1;
}

exit 0;
