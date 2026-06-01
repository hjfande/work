#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_bind_from_excel.py
  解析 Excel 文件生成 bind_idc_wrap.sv
  用法: python gen_bind_from_excel.py <excel_file>
  返回: 1=错误, 0=成功
"""

import sys
import os
import re
import argparse
import zipfile
import xml.etree.ElementTree as ET


# ============================================================================
# Data Classes
# ============================================================================
class PortOutInfo:
    """Represents a single port-out entry within an IntrInfo."""
    def __init__(self, ic_name='', ic_num=0, ic_bit=0):
        self.ic_name = ic_name
        self.ic_num = ic_num
        self.ic_bit = ic_bit

    def __repr__(self):
        return (f"PortOutInfo(ic_name={self.ic_name!r}, ic_num={self.ic_num}, "
                f"ic_bit={self.ic_bit})")


class IntrInfo:
    """
    Wraps raw Excel fields, plus typed attributes for computed fields.
    Fixed columns: IP, INT_NAME, INT_NET_NAME, INT_TYPE, INT_HIER.
    Dynamic IC columns (e.g. IC0, IC1) are stored in self.ic dict.
    """
    _FIXED_GET_MAP = {
        'IP': 'ip',
        'INT_NAME': 'int_name',
        'INT_NET_NAME': 'int_net_name',
        'INT_TYPE': 'int_type',
        'INT_HIER': 'int_hier',
    }

    def __init__(self, raw_data=None):
        self.ip = ''
        self.int_name = ''
        self.int_net_name = ''
        self.int_type = ''
        self.int_hier = ''
        self.ic = {}          # dynamic IC fields, e.g. {'IC0': 'Y', 'IC1': ''}
        self.int_type_in_bit_num = -1
        self.port_in_name = ''
        self.port_out_info_list = []
        self.merge_group_idx = -1
        self.regbank_merge_int_hier = ''

        if raw_data:
            for k, v in raw_data.items():
                attr = self._FIXED_GET_MAP.get(k)
                if attr:
                    setattr(self, attr, v)
                else:
                    self.ic[k] = v

    def get(self, key, default=''):
        attr = self._FIXED_GET_MAP.get(key)
        if attr:
            return getattr(self, attr, default)
        return self.ic.get(key, default)

    def __repr__(self):
        return (f"IntrInfo(ip={self.ip!r}, int_name={self.int_name!r}, "
                f"int_net_name={self.int_net_name!r}, int_type={self.int_type!r}, "
                f"int_hier={self.int_hier!r}, ic={self.ic!r}, "
                f"int_type_in_bit_num={self.int_type_in_bit_num}, "
                f"port_in_name={self.port_in_name!r}, "
                f"port_out_info_list={self.port_out_info_list}, "
                f"merge_group_idx={self.merge_group_idx}, "
                f"regbank_merge_int_hier={self.regbank_merge_int_hier!r})")


class CFG:
    def __init__(self, sys_name=''):
        self.sys_name = sys_name
        self.wrap_name = f"{sys_name}_idc_wrap"
        self.ctrl_name = f"{sys_name}_intr_distribute_ctrl"
        self.regbank_name = f"{sys_name}_idc_reg_bank"
        self.ic_prefix = f"{sys_name}_int_bus_to"

    def __repr__(self):
        return (f"CFG(sys_name={self.sys_name!r}, wrap_name={self.wrap_name!r}, "
                f"ctrl_name={self.ctrl_name!r}, regbank_name={self.regbank_name!r}, "
                f"ic_prefix={self.ic_prefix!r})")



class ParseIntrResult:
    """Container for parse_intr_sheet output."""
    def __init__(self):
        self.intr_info_list = []
        self.destination_merge = None
        self.headers = {}
        self.ic_list = []
        self.posedge_cnt = 0
        self.negedge_cnt = 0
        self.high_cnt = 0
        self.low_cnt = 0
        self.level_cnt_per_ic = {}  # {ic_name: count}

    def __repr__(self):
        return (f"ParseIntrResult(list={len(self.intr_info_list)}, "
                f"posedge={self.posedge_cnt}, negedge={self.negedge_cnt}, "
                f"high={self.high_cnt}, low={self.low_cnt})")


# ============================================================================
# Helpers
# ============================================================================
def strip_namespace(elem):
    """Remove namespace prefixes from all tags in the XML tree."""
    for e in elem.iter():
        if '}' in e.tag:
            e.tag = e.tag.split('}', 1)[1]
    return elem


def col_name_to_index(name):
    """Convert Excel column name to 1-based index: A->1, B->2, ..., Z->26, AA->27."""
    idx = 0
    for ch in name.upper():
        idx = idx * 26 + (ord(ch) - ord('A') + 1)
    return idx


def index_to_col_name(idx):
    """Convert 1-based index to Excel column name."""
    name = ''
    while idx > 0:
        idx, rem = divmod(idx - 1, 26)
        name = chr(ord('A') + rem) + name
    return name


def get_cell_value(cell, shared_strings):
    """Extract string value from a <c> element."""
    v_elem = cell.find('v')
    val = v_elem.text if v_elem is not None else ''
    if cell.get('t') == 's' and val.isdigit():
        idx = int(val)
        val = shared_strings[idx] if idx < len(shared_strings) else ''
    return val


# ============================================================================
# Step 1: Parse CFG sheet
# ============================================================================
def parse_cfg_sheet(excel_path):
    """
    Parse the 'CFG' sheet from an .xlsx file.
    Returns a CFG object with sys_name extracted from the sheet.
    """
    raw_cfg = {}

    with zipfile.ZipFile(excel_path, 'r') as zf:
        wb_xml = zf.read('xl/workbook.xml')
        wb_root = strip_namespace(ET.fromstring(wb_xml))

        target_rid = None
        for sheet in wb_root.iter('sheet'):
            if sheet.get('name') == 'CFG':
                target_rid = sheet.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id')
                break

        if target_rid is None:
            raise ValueError("Sheet 'CFG' not found in workbook")

        rels_xml = zf.read('xl/_rels/workbook.xml.rels')
        rels_root = strip_namespace(ET.fromstring(rels_xml))

        sheet_path = None
        for rel in rels_root.iter('Relationship'):
            if rel.get('Id') == target_rid:
                target = rel.get('Target')
                sheet_path = 'xl/' + target.replace('\\', '/')
                break

        if sheet_path is None:
            raise ValueError(f"Cannot resolve path for sheet rId '{target_rid}'")

        shared_strings = []
        if 'xl/sharedStrings.xml' in zf.namelist():
            ss_xml = zf.read('xl/sharedStrings.xml')
            ss_root = strip_namespace(ET.fromstring(ss_xml))
            for si in ss_root.iter('si'):
                t_elem = si.find('t')
                if t_elem is not None:
                    shared_strings.append(t_elem.text or '')
                else:
                    texts = [t.text or '' for t in si.iter('t')]
                    shared_strings.append(''.join(texts))

        sheet_xml = zf.read(sheet_path)
        sheet_root = strip_namespace(ET.fromstring(sheet_xml))

        for row in sheet_root.iter('row'):
            row_num = int(row.get('r', '0'))
            if row_num < 2:
                continue

            cells = {}
            for cell in row.iter('c'):
                ref = cell.get('r', '')
                col = ''.join(ch for ch in ref if ch.isalpha())
                cells[col] = get_cell_value(cell, shared_strings)

            key = cells.get('A', '')
            if key:
                raw_cfg[key] = cells.get('B', '')

    return CFG(raw_cfg.get('SYS_NAME', ''))


# ============================================================================
# Step 2: Parse second sheet (intr_info)
# ============================================================================
def parse_intr_sheet(excel_path):
    """
    Parse the second sheet (index 1, 0-based) from an .xlsx file.
    Returns a ParseIntrResult object.
    """
    result = ParseIntrResult()

    with zipfile.ZipFile(excel_path, 'r') as zf:
        # --- 1. Locate second sheet ---
        wb_xml = zf.read('xl/workbook.xml')
        wb_root = strip_namespace(ET.fromstring(wb_xml))

        sheets = list(wb_root.iter('sheet'))
        if len(sheets) < 2:
            raise ValueError("Workbook must have at least 2 sheets for intr_info parsing")

        second_sheet = sheets[1]
        target_rid = second_sheet.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id')

        rels_xml = zf.read('xl/_rels/workbook.xml.rels')
        rels_root = strip_namespace(ET.fromstring(rels_xml))

        sheet_path = None
        for rel in rels_root.iter('Relationship'):
            if rel.get('Id') == target_rid:
                target = rel.get('Target')
                sheet_path = 'xl/' + target.replace('\\', '/')
                break

        if sheet_path is None:
            raise ValueError(f"Cannot resolve path for second sheet rId '{target_rid}'")

        # --- 2. Load shared strings ---
        shared_strings = []
        if 'xl/sharedStrings.xml' in zf.namelist():
            ss_xml = zf.read('xl/sharedStrings.xml')
            ss_root = strip_namespace(ET.fromstring(ss_xml))
            for si in ss_root.iter('si'):
                t_elem = si.find('t')
                if t_elem is not None:
                    shared_strings.append(t_elem.text or '')
                else:
                    texts = [t.text or '' for t in si.iter('t')]
                    shared_strings.append(''.join(texts))

        # --- 3. Parse sheet XML ---
        sheet_xml = zf.read(sheet_path)
        sheet_root = strip_namespace(ET.fromstring(sheet_xml))

        # Collect all rows
        all_rows = {}
        all_cols = set()
        for row in sheet_root.iter('row'):
            row_num = int(row.get('r', '0'))
            cells = {}
            for cell in row.iter('c'):
                ref = cell.get('r', '')
                col = ''.join(ch for ch in ref if ch.isalpha())
                all_cols.add(col)
                cells[col] = get_cell_value(cell, shared_strings)
            all_rows[row_num] = cells

        if not all_rows:
            raise ValueError("Second sheet is empty")

        # --- 4. Parse mergeCells (row 1 only) ---
        merge_ranges = []
        merge_cells_elem = sheet_root.find('mergeCells')
        if merge_cells_elem is not None:
            for mc in merge_cells_elem.iter('mergeCell'):
                ref = mc.get('ref', '')
                if ':' not in ref:
                    continue
                start_ref, end_ref = ref.split(':')
                start_col = ''.join(ch for ch in start_ref if ch.isalpha())
                start_row = int(''.join(ch for ch in start_ref if ch.isdigit()) or '0')
                end_col = ''.join(ch for ch in end_ref if ch.isalpha())
                end_row = int(''.join(ch for ch in end_ref if ch.isdigit()) or '0')

                if start_row == 1:
                    merge_ranges.append({
                        'ref': ref,
                        'start_col': start_col,
                        'start_row': start_row,
                        'end_col': end_col,
                        'end_row': end_row,
                        'start_col_idx': col_name_to_index(start_col),
                        'end_col_idx': col_name_to_index(end_col),
                        'is_col_merge': start_col != end_col,
                    })

        # --- 5. Identify Destination merge cell ---
        destination_merge = None
        for mr in merge_ranges:
            sc = mr['start_col']
            if sc in all_rows.get(1, {}) and all_rows[1][sc] == 'Destination':
                destination_merge = mr
                break

        result.destination_merge = destination_merge

        # --- 5.5 Build ic_list from Destination merge sub-headers (row 2) ---
        ic_list = []
        if destination_merge:
            for col_idx in range(destination_merge['start_col_idx'], destination_merge['end_col_idx'] + 1):
                col = index_to_col_name(col_idx)
                sub_header = all_rows.get(2, {}).get(col, '')
                ic_list.append(sub_header)
        result.ic_list = ic_list

        # --- 6. Build headers ---
        sorted_cols = sorted(all_cols, key=col_name_to_index)

        headers = {}
        for col in sorted_cols:
            col_idx = col_name_to_index(col)
            in_col_merge = False
            for mr in merge_ranges:
                if (mr['start_col_idx'] <= col_idx <= mr['end_col_idx']
                        and mr.get('is_col_merge')):
                    in_col_merge = True
                    break

            if in_col_merge and col in all_rows.get(2, {}):
                headers[col] = all_rows[2][col]
            else:
                val = all_rows.get(1, {}).get(col, '')
                if not val and col in all_rows.get(2, {}):
                    val = all_rows[2][col]
                headers[col] = val

        result.headers = headers

        # --- 7. Collect intr_info rows (from row 3 onwards) ---
        posedge_cnt = 0
        negedge_cnt = 0
        high_cnt = 0
        low_cnt = 0

        raw_list = []
        for row_num in sorted(all_rows.keys()):
            if row_num < 3:
                continue

            row_data = all_rows[row_num]
            raw = {}
            for col in sorted_cols:
                key = headers.get(col, col)
                raw[key] = row_data.get(col, '')

            intr = IntrInfo(raw)

            # Build port_in_name
            int_net_name = intr.get('INT_NET_NAME', '')
            if int_net_name:
                port = int_net_name
            else:
                int_hier = intr.get('INT_HIER', '')
                parts = int_hier.split('.')
                if len(parts) > 1:
                    port = parts[-1]
                else:
                    port = int_hier

            intr.port_in_name = re.sub(r'\[(\d+)\]$', r'_\1', port)

            # Assign int_type_in_bit_num based on INT_TYPE
            int_type = intr.get('INT_TYPE', '')
            if int_type == 'POSEDGE':
                intr.int_type_in_bit_num = posedge_cnt
                posedge_cnt += 1
            elif int_type == 'NEGEDGE':
                intr.int_type_in_bit_num = negedge_cnt
                negedge_cnt += 1
            elif int_type == 'HIGH':
                intr.int_type_in_bit_num = high_cnt
                high_cnt += 1
            elif int_type == 'LOW':
                intr.int_type_in_bit_num = low_cnt
                low_cnt += 1
            else:
                intr.int_type_in_bit_num = -1

            raw_list.append(intr)

        result.posedge_cnt = posedge_cnt
        result.negedge_cnt = negedge_cnt
        result.high_cnt = high_cnt
        result.low_cnt = low_cnt

        # Phase 2: Assign port_out_info_list with grouped counters
        edge_counters = {name: 0 for name in ic_list}
        level_counters = {name: 0 for name in ic_list}

        def assign_port_out(info_list, int_type_list, counters):
            for info in info_list:
                if info.get('INT_TYPE', '') in int_type_list:
                    port_out = []
                    for ic_num, ic_name in enumerate(ic_list):
                        if info.get(ic_name, '') == 'Y':
                            port_out.append(PortOutInfo(
                                ic_name=ic_name,
                                ic_num=ic_num,
                                ic_bit=counters[ic_name]
                            ))
                            counters[ic_name] += 1
                    info.port_out_info_list = port_out

        assign_port_out(raw_list, ['NEGEDGE'], edge_counters)
        assign_port_out(raw_list, ['POSEDGE'], edge_counters)
        assign_port_out(raw_list, ['LOW'], level_counters)
        assign_port_out(raw_list, ['HIGH'], level_counters)

        result.level_cnt_per_ic = dict(level_counters)
        result.intr_info_list = raw_list

        # Phase 3: Assign merge_group_idx for HIGH/LOW types
        merge_counter = 0
        for info in result.intr_info_list:
            if info.get('INT_TYPE', '') in ('HIGH', 'LOW'):
                info.merge_group_idx = merge_counter // 32
                merge_counter += 1

    return result


# ============================================================================
# Step 3: Generate bind_idc_wrap.sv
# ============================================================================
def generate_bind_sva(intr, cfg, output_file='bind_idc_wrap.sv'):
    """
    Generate bind_idc_wrap.sv for POSEDGE/NEGEDGE intr entries.
    One edge_detect_fpv instance per port_out_info.
    """
    with open(output_file, 'w') as f:
        f.write("// ============================================================================\n")
        f.write("// Auto-generated bind file by gen_bind_from_excel.py\n")
        f.write("// Do NOT edit manually\n")
        f.write("// ============================================================================\n\n")

        sys_name = cfg.sys_name

        for info in intr.intr_info_list:
            int_type = info.get('INT_TYPE', '')
            if int_type not in ('POSEDGE', 'NEGEDGE'):
                continue

            port_in = info.port_in_name
            edge_in_conn = f"~{port_in}" if int_type == 'NEGEDGE' else port_in
            sync_num = '2'

            merge_group_num = (intr.high_cnt + intr.low_cnt + 31) // 32
            for po in info.port_out_info_list:
                ic_name = po.ic_name
                ic_bit = po.ic_bit
                level_cnt = intr.level_cnt_per_ic.get(ic_name, 0)
                bit_idx = merge_group_num + level_cnt + ic_bit
                async_edge = f"{cfg.ic_prefix}_{ic_name}[{bit_idx}]".lower()

                inst_name = (f"u_edge_detect_fpv_"
                             f"{int_type.lower()}{info.int_type_in_bit_num}_ic{po.ic_num}_{port_in}")

                f.write(f"bind {cfg.wrap_name} edge_detect_fpv #(\n")
                f.write(f"    .SYNC_NUM({sync_num})\n")
                f.write(f") {inst_name} (\n")
                f.write(f"    .clk               (apb_clk),\n")
                f.write(f"    .rst_n             (apb_rstn),\n")
                f.write(f"    .edge_in           ({edge_in_conn}),\n")
                f.write(f"    .async_edge        ({async_edge}),\n")
                f.write(f"    .edge_stb          (1'b1),\n")
                f.write(f"    .dft_dc_scan_clk   (dft_dc_scan_clk),\n")
                f.write(f"    .dft_dc_scan_mode  (dft_dc_scan_mode),\n")
                f.write(f"    .dft_dc_scan_rst_n (dft_dc_scan_rst_n)\n")
                f.write(f");\n\n")

        # --- Bind HIGH/LOW level checks ---
        for info in intr.intr_info_list:
            int_type = info.get('INT_TYPE', '')
            if int_type not in ('HIGH', 'LOW'):
                continue

            port_in = info.port_in_name
            module_name = ('high_checker' if int_type == 'HIGH' else 'low_checker')
            level_port = ('high_level_bit'
                          if int_type == 'HIGH'
                          else 'low_level_bit')

            merge_group_num = (intr.high_cnt + intr.low_cnt + 31) // 32
            for po in info.port_out_info_list:
                ic_name = po.ic_name
                ic_bit = po.ic_bit
                bit_idx = merge_group_num + ic_bit
                level_sig = f"{cfg.ic_prefix}_{ic_name}[{bit_idx}]".lower()

                inst_name = (f"u_{module_name}_"
                             f"{int_type.lower()}{info.int_type_in_bit_num}_ic{po.ic_num}_{port_in}")

                f.write(f"bind {cfg.wrap_name} {module_name} {inst_name} (\n")
                f.write(f"    .clk        (apb_clk),\n")
                f.write(f"    .rst_n      (apb_rstn),\n")
                f.write(f"    .{level_port} ({port_in}),\n")
                f.write(f"    .level_bit  ({level_sig})\n")
                f.write(f");\n\n")

        # --- Bind merge checks ---
        merge_groups = {}
        for info in intr.intr_info_list:
            if info.get('INT_TYPE', '') not in ('HIGH', 'LOW'):
                continue
            gid = info.merge_group_idx
            if gid < 0:
                continue
            regbank = info.regbank_merge_int_hier.replace('``ic_num``', str(gid))
            merge_groups.setdefault(gid, []).append({
                'port_in': info.port_in_name,
                'regbank': regbank
            })

        for gid, entries in sorted(merge_groups.items()):
            width = len(entries)
            port_list = [e['port_in'] for e in entries]
            regbank_list = [e['regbank'] for e in entries]

            if width == 1:
                merge_bus = port_list[0]
                merge_bus_regbank = regbank_list[0]
            else:
                merge_bus = "{" + ", ".join(reversed(port_list)) + "}"
                merge_bus_regbank = "{" + ", ".join(reversed(regbank_list)) + "}"

            for ic_name in intr.ic_list:
                merge_ic_bit = f"{cfg.ic_prefix}_{ic_name}[{gid}]".lower()
                inst_name = f"u_merge_sva_group{gid}_{ic_name}"

                f.write(f"bind {cfg.wrap_name} merge_sva #(\n")
                f.write(f"    .BUS_WIDTH({width})\n")
                f.write(f") {inst_name} (\n")
                f.write(f"    .clk               (apb_clk),\n")
                f.write(f"    .rst_n             (apb_rstn),\n")
                f.write(f"    .merge_bus_regbank ({merge_bus_regbank}),\n")
                f.write(f"    .merge_ic_bit      ({merge_ic_bit}),\n")
                f.write(f"    .merge_bus         ({merge_bus}),\n")
                f.write(f"    .merge_bus_enable  ({width}'b0),\n")
                f.write(f"    .merge_bus_mask    ({width}'b0),\n")
                f.write(f"    .merge_bus_set     ({width}'b0)\n")
                f.write(f");\n\n")

        f.write("// ============================================================================\n")
        f.write("// End of auto-generated bind file\n")
        f.write("// ============================================================================\n")

    print(f"\n[INFO] Bind file saved to: {output_file}")


# ============================================================================
# Main
# ============================================================================
def main():
    parser = argparse.ArgumentParser(
        description="Generate bind_idc_wrap.sv from Excel file"
    )
    parser.add_argument(
        "excel_file",
        help="Path to the input Excel file"
    )
    args = parser.parse_args()

    excel_path = args.excel_file

    if not os.path.isfile(excel_path):
        print(f"[ERROR] File not found: {excel_path}", file=sys.stderr)
        return 0

    try:
        # --- Step 1: CFG ---
        cfg = parse_cfg_sheet(excel_path)
        print(f"[INFO] CFG parsed: {cfg}")
        sys_name = cfg.sys_name

        # --- Step 2: intr_info ---
        intr = parse_intr_sheet(excel_path)

        dm = intr.destination_merge
        if dm:
            print(f"\n[INFO] Destination merge range: {dm['start_col']}:{dm['end_col']} "
                  f"(cols {dm['start_col_idx']}-{dm['end_col_idx']})")
            print(f"[INFO] ic_list: {intr.ic_list}")
        else:
            print("\n[WARN] No Destination merge cell found in row 1")

        print(f"[INFO] Headers: {intr.headers}")
        print(f"[INFO] intr_info_list has {len(intr.intr_info_list)} entries")
        print(f"[INFO] Counters -> POSEDGE:{intr.posedge_cnt} "
              f"NEGEDGE:{intr.negedge_cnt} HIGH:{intr.high_cnt} LOW:{intr.low_cnt}")

        for i, info in enumerate(intr.intr_info_list[:5]):
            print(f"  Row {i+3}: {info}")
        if len(intr.intr_info_list) > 5:
            print(f"  ... ({len(intr.intr_info_list) - 5} more rows)")

        # --- Step 4: Assign regbank_merge_int_hier for HIGH/LOW types ---
        for info in intr.intr_info_list:
            if info.get('INT_TYPE', '') in ('HIGH', 'LOW'):
                info.regbank_merge_int_hier = (
                    f"`REG_BANK.{sys_name.lower()}_ic``ic_num``_merge_int"
                    f"{info.merge_group_idx}_{info.port_in_name}_rdat"
                )

        # --- Step 6: Generate bind_idc_wrap.sv ---
        generate_bind_sva(intr, cfg)

        return 0

    except Exception as e:
        print(f"[ERROR] {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
