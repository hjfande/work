#!/usr/bin/env python3
"""
Generate preload.data file with 8Kbit (8192 bits) of data.

Generation flow:
  1. Generate 8192 bits directly
  2. Apply lcs_state to eFuse bit addresses mapped from APB 0x48
  3. Apply wr_rd_acc_dis to eFuse bit addresses mapped from APB 0x7C/0x80
  4. Apply top_acc_sec_region_bit to eFuse bit address mapped from APB 0xA4+41bit
  5. Apply shadow_sram_acc_bit to eFuse bit address mapped from APB 0xA4+42bit
  6. Write physical bit-address format output

LCS_STATE control:
  - low 4 bits at APB 0x48

WR_RD_ACC_DIS control:
  - 0x7C low 8 bits -> write access disable for region_res_[0-7]
  - 0x80 low 8 bits -> read  access disable for region_res_[0-7]

TOP_ACC_SEC_REGION_BIT control:
  - bit at APB 0xA4 + 41bit offset (i.e. APB 0xA8 bit[9])

SHADOW_SRAM_ACC_BIT control:
  - bit at APB 0xA4 + 42bit offset (i.e. APB 0xA8 bit[10])

Format: @<bit_address_hex> <bit_value>
"""

import argparse
import random

# Fixed configuration
TOTAL_BITS = 8192        # 8Kbit physical


def apb_addr_to_efuse_bit_addr(apb_addr):
    """Convert an APB byte address to eFuse primary/shadow bit addresses.

    Returns:
        efuse_primary_addr_ls: list of 32 primary bit addresses
        efuse_shadow_addr_ls:  list of 32 shadow bit addresses
    """
    base = (apb_addr >> 2) & 0x7F   # apb_addr[8:2]
    efuse_primary_addr_ls = [(base + ( i << 8)) for i in range(32)]
    efuse_shadow_addr_ls = [addr + (1 << 7) for addr in efuse_primary_addr_ls]
    return efuse_primary_addr_ls, efuse_shadow_addr_ls


def write_apb_word_to_efuse(physical_bits, apb_addr, word_val, mask=0xFFFFFFFF):
    """Write a 32-bit APB word value to eFuse bit addresses mapped from apb_addr.

    Only bits with mask=1 are written. The word bits are mapped MSB-first to the
    primary+shadow efuse bit addresses returned by apb_addr_to_efuse_bit_addr.
    """
    pri_addrs, shd_addrs = apb_addr_to_efuse_bit_addr(apb_addr)

    for i in range(32):
        if (mask >> (31 - i)) & 1:
            bit_val = (word_val >> (31 - i)) & 1
            physical_bits[pri_addrs[i]] = bit_val
            physical_bits[shd_addrs[i]] = bit_val

    return physical_bits


def write_apb_bit_to_efuse(physical_bits, base_addr, bit_offset, bit_val):
    """Write a single bit at base_addr + bit_offset to eFuse bit addresses."""
    word_addr = base_addr + (bit_offset // 32) * 4
    bit_in_word = bit_offset % 32
    mask = 1 << bit_in_word
    word_val = (bit_val & 1) << bit_in_word
    return write_apb_word_to_efuse(physical_bits, word_addr, word_val, mask)


def generate_preload_data(seed, output_file="preload.data", lcs_state=0, wr_rd_acc_dis=0,
                          top_acc_sec_region_bit=0, shadow_sram_acc_bit=0,
                          all_zero=False):
    """
    Generate 8Kbit preload data.

    Flow:
      1. Generate 8192 bits directly
      2. Apply lcs_state to mapped eFuse bit addresses at APB 0x48
      3. Apply wr_rd_acc_dis to mapped eFuse bit addresses
      4. Apply top_acc_sec_region_bit to APB 0xA4+41bit offset
      5. Apply shadow_sram_acc_bit to APB 0xA4+42bit offset
      6. Write physical bit-address output

    Args:
        seed: Random seed for reproducible data
        output_file: Output filename
        lcs_state: 4-bit value at APB 0x48 low 4 bits
        wr_rd_acc_dis: 16-bit value controlling 0x7C/0x80 low 8 bits
        top_acc_sec_region_bit: 1-bit value for APB 0xA4+41bit offset (0xA8 bit[9])
        shadow_sram_acc_bit: 1-bit value for APB 0xA4+42bit offset (0xA8 bit[10])
        all_zero: If True, force entire 8Kbit to 0

    Returns:
        dict containing physical_bits and parameters
    """
    random.seed(seed)

    # Step 1: Generate 8192 bits directly
    if all_zero:
        physical_bits = [0] * TOTAL_BITS
    else:
        physical_bits = [random.randint(0, 1) for _ in range(TOTAL_BITS)]

    # Step 2: Apply lcs_state
    # low 4 bits at APB 0x48
    if not all_zero:
        write_apb_word_to_efuse(physical_bits, 0x48, lcs_state & 0xF, 0x0000000F)

    # Step 3: Apply wr_rd_acc_dis
    # bit[7:0]  -> 0x7C low 8 bits (write access disable)
    # bit[15:8] -> 0x80 low 8 bits (read access disable)
    if not all_zero:
        write_apb_word_to_efuse(physical_bits, 0x7C, wr_rd_acc_dis & 0xFF, 0x000000FF)
        write_apb_word_to_efuse(physical_bits, 0x80, (wr_rd_acc_dis >> 8) & 0xFF, 0x000000FF)

    # Step 4: Apply top_acc_sec_region_bit
    # APB 0xA4 + 41bit offset -> APB 0xA8 bit[9]
    if not all_zero:
        write_apb_bit_to_efuse(physical_bits, 0xA4, 41, top_acc_sec_region_bit)

    # Step 5: Apply shadow_sram_acc_bit
    # APB 0xA4 + 42bit offset -> APB 0xA8 bit[10]
    if not all_zero:
        write_apb_bit_to_efuse(physical_bits, 0xA4, 42, shadow_sram_acc_bit)

    # Step 6: Write preload.data in physical bit-address format
    with open(output_file, 'w') as f:
        for bit_addr in range(TOTAL_BITS):
            f.write(f"@{bit_addr:08x} {physical_bits[bit_addr]}\n")

    # Print summary
    print(f"{'='*70}")
    print(f"  8Kbit eFuse Preload Data Generation")
    print(f"{'='*70}")
    print(f"  Seed:               {seed}")
    print(f"  LCS_STATE:          0x{lcs_state & 0xF:x}")
    print(f"  WR_RD_ACC_DIS:      0x{wr_rd_acc_dis:04x}")
    print(f"  TOP_ACC_SEC_REGION_BIT: {top_acc_sec_region_bit & 1}")
    print(f"  SHADOW_SRAM_ACC_BIT: {shadow_sram_acc_bit & 1}")
    print(f"  All zero mode:      {all_zero}")
    print(f"{'='*70}")
    print(f"\n  Generated {output_file}: {TOTAL_BITS} bits ({TOTAL_BITS//8} bytes)")
    print(f"{'='*70}")

    return {
        'seed': seed,
        'physical_bits': physical_bits,
        'lcs_state': lcs_state & 0xF,
        'wr_rd_acc_dis': wr_rd_acc_dis,
        'top_acc_sec_region_bit': top_acc_sec_region_bit & 1,
        'shadow_sram_acc_bit': shadow_sram_acc_bit & 1,
        'all_zero': all_zero,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Generate 8Kbit preload.data"
    )
    parser.add_argument(
        "--seed",
        type=int,
        required=True,
        help="Random seed for data generation"
    )
    parser.add_argument(
        "--output",
        type=str,
        default="preload.data",
        help="Output filename (default: preload.data)"
    )
    parser.add_argument(
        "--wr-rd-acc-dis",
        type=lambda x: int(x, 0),
        default=0,
        help="16-bit value for WR_RD_ACC_DIS control (0x7C=low8 write, 0x80=low8 read), default 0"
    )
    parser.add_argument(
        "--lcs-state",
        type=lambda x: int(x, 0),
        default=0,
        help="4-bit value for LCS_STATE at APB 0x48 low 4 bits (default 0)"
    )
    parser.add_argument(
        "--top-acc-sec-region-bit",
        type=lambda x: int(x, 0),
        default=0,
        help="1-bit value for TOP_ACC_SEC_REGION_BIT at APB 0xA4+41bit offset (default 0)"
    )
    parser.add_argument(
        "--shadow-sram-acc-bit",
        type=lambda x: int(x, 0),
        default=0,
        help="1-bit value for SHADOW_SRAM_ACC_BIT at APB 0xA4+42bit offset (default 0)"
    )
    parser.add_argument(
        "--all-zero",
        action="store_true",
        default=False,
        help="Force entire 8Kbit to 0 (overrides all other settings)"
    )

    args = parser.parse_args()

    # Validate wr_rd_acc_dis is 16-bit
    if args.wr_rd_acc_dis < 0 or args.wr_rd_acc_dis > 0xFFFF:
        parser.error("--wr-rd-acc-dis must be a 16-bit value (0~0xFFFF)")

    # Validate lcs_state is 4-bit
    if args.lcs_state < 0 or args.lcs_state > 0xF:
        parser.error("--lcs-state must be a 4-bit value (0~0xF)")

    # Validate top_acc_sec_region_bit is 1-bit
    if args.top_acc_sec_region_bit < 0 or args.top_acc_sec_region_bit > 1:
        parser.error("--top-acc-sec-region-bit must be 0 or 1")

    # Validate shadow_sram_acc_bit is 1-bit
    if args.shadow_sram_acc_bit < 0 or args.shadow_sram_acc_bit > 1:
        parser.error("--shadow-sram-acc-bit must be 0 or 1")

    result = generate_preload_data(
        args.seed,
        args.output,
        args.lcs_state,
        args.wr_rd_acc_dis,
        args.top_acc_sec_region_bit,
        args.shadow_sram_acc_bit,
        args.all_zero
    )

    # Internal variables available for future use:
    # result['physical_bits'] -> 8192 bits (physical)


if __name__ == "__main__":
    main()
