bind_gen_readme
搜索 输入路径下的_idc_wrap.v 文件，提取中断映射关系
生成 idc_wrap_ast 实例 (每ic编号一个实例)

从spec.txt中读取*_idc_wrap.v的接口说明，*保存为wrap_name参数
提取*_idc_wrap.v内部实例化的int_distributor_ctrl的parameter
收集*_idc_wrap.v的输入信号和其内部的*_int_bus的映射关系，输入信号以_int结尾
收集*_idc_wrap.v的输出信号和其内部的*_to_ic[ic_number]的映射关系
bitmap参数决定哪些输入映射到哪些输出

实例化ic_number个idc_wrap_ast
*_idc_wrap.v的输入直接bind到全部的idc_wrap_ast上，由于这部分代码重复，将其定义为宏，应用到每个idc_wrap_ast上
*_idc_wrap.v的输输出根据ic_number bind到对应的idc_wrap_ast上

regbank_merge_int_bus信号由${wrap_name}_idc_wrap_ic${ic_num}_int${merge_group_num}_${sig_name}_rdat拼接而成
- sig_name是*_idc_wrap.v的输入信号_int之前的部分，然后转大写
- merge_group_num是high_level_int_bus和Low_level_int_bus按照32bit分组得到
- 若通过bitmap过滤sig_name