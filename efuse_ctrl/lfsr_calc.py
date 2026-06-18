#!/usr/bin/env python3
"""
LFSR data translator for the efuse controller.

This mirrors the SystemVerilog function lfsr_out_data(seed, in_data):
    out_data[i] = in_data[i] ^ XOR_of_selected_seed_bits[i]

Because the transform is a plain XOR, the same function both encodes logical
-> raw and decodes raw -> logical data.

Seed selection by logical eFuse word address:
    0x04, 0x08, 0x0C, 0x10 -> MODEL_RTL_CODE0..3
    0x18, 0x1C, 0x20, 0x24 -> DEVICE_RTL_CODE0..3
"""

# Seed localparams (from RTL screenshots).
# NOTE: DEVICE_RTL_CODE0 in the screenshot appears as 32'hddbebd01d (9 hex
# digits). It is masked to 32 bits below, but please verify the intended value.
MODEL_RTL_CODE0  = 0x2e2b5d09
MODEL_RTL_CODE1  = 0xaa755e97
MODEL_RTL_CODE2  = 0x68762cea
MODEL_RTL_CODE3  = 0xfe5afa1b
DEVICE_RTL_CODE0 = 0xddbeb01d  # verify: screenshot shows 32'hddbebd01d
DEVICE_RTL_CODE1 = 0x9b42e513
DEVICE_RTL_CODE2 = 0xeb6e9ac2
DEVICE_RTL_CODE3 = 0x121066a1


# Map logical word address -> seed
ADDR_TO_SEED = {
    0x04: MODEL_RTL_CODE0,
    0x08: MODEL_RTL_CODE1,
    0x0C: MODEL_RTL_CODE2,
    0x10: MODEL_RTL_CODE3,
    0x18: DEVICE_RTL_CODE0,
    0x1C: DEVICE_RTL_CODE1,
    0x20: DEVICE_RTL_CODE2,
    0x24: DEVICE_RTL_CODE3,
}


# Per-bit seed XOR masks copied from RTL lfsr_out_data.
# Each entry lists the seed bit indices XORed with in_data[i].
SEED_MASKS = [
    [31],                              # bit 0
    [30],                              # bit 1
    [29],                              # bit 2
    [28],                              # bit 3
    [27],                              # bit 4
    [26],                              # bit 5
    [25],                              # bit 6
    [24],                              # bit 7
    [23],                              # bit 8
    [22, 31],                          # bit 9
    [21, 30],                          # bit 10
    [20, 29],                          # bit 11
    [19, 28],                          # bit 12
    [18, 27],                          # bit 13
    [17, 26],                          # bit 14
    [16, 25],                          # bit 15
    [15, 24],                          # bit 16
    [14, 23],                          # bit 17
    [13, 22, 31],                      # bit 18
    [12, 21, 30],                      # bit 19
    [11, 20, 29],                      # bit 20
    [10, 19, 28],                      # bit 21
    [9, 18, 27],                       # bit 22
    [8, 17, 26],                       # bit 23
    [7, 16, 25],                       # bit 24
    [6, 15, 24],                       # bit 25
    [5, 14, 23],                       # bit 26
    [4, 13, 22, 31],                   # bit 27
    [3, 12, 21, 30],                   # bit 28
    [2, 11, 20, 29],                   # bit 29
    [1, 10, 19, 28],                   # bit 30
    [0, 9, 18, 27],                    # bit 31
]


def lfsr_out_data(seed: int, in_data: int) -> int:
    """Compute 32-bit LFSR translated data from seed and input data."""
    seed &= 0xFFFFFFFF
    in_data &= 0xFFFFFFFF
    out_data = 0
    for i in range(32):
        bit = (in_data >> i) & 1
        for s in SEED_MASKS[i]:
            bit ^= (seed >> s) & 1
        out_data |= bit << i
    return out_data


def lfsr_by_addr(addr: int, in_data: int) -> int:
    """Select seed by logical word address and compute LFSR output."""
    if addr not in ADDR_TO_SEED:
        raise ValueError(
            f"Unsupported LFSR address 0x{addr:08x}. "
            f"Supported addresses: {[hex(a) for a in ADDR_TO_SEED]}"
        )
    return lfsr_out_data(ADDR_TO_SEED[addr], in_data)


def main():
    import sys
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <addr> <in_data>")
        print("  addr:    logical eFuse word address (e.g. 0x04)")
        print("  in_data: 32-bit input data (e.g. 0x12345678)")
        print("\nThe same transform works for both encode and decode.")
        sys.exit(1)

    addr = int(sys.argv[1], 0)
    in_data = int(sys.argv[2], 0)

    seed = ADDR_TO_SEED[addr]
    out_data = lfsr_out_data(seed, in_data)

    print(f"addr      = 0x{addr:08x}")
    print(f"seed      = 0x{seed:08x}")
    print(f"in_data   = 0x{in_data:08x}")
    print(f"out_data  = 0x{out_data:08x}")


if __name__ == "__main__":
    main()
