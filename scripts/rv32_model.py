#!/usr/bin/env python3
"""Small RV32I reference model used to generate processor test goldens."""

from __future__ import annotations

import argparse
from pathlib import Path

MASK32 = 0xFFFF_FFFF
ISRAM_BASE = 0x0000
DSRAM_BASE = 0x1000
MEMORY_BYTES = 4096
EBREAK = 0x0010_0073


def sign_extend(value: int, bits: int) -> int:
    sign = 1 << (bits - 1)
    return (value & (sign - 1)) - (value & sign)


def signed32(value: int) -> int:
    return sign_extend(value & MASK32, 32)


def read_words(path: Path | None) -> list[int]:
    if path is None or not path.exists():
        return []
    words = []
    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        token = line.split("#", 1)[0].strip()
        if token:
            try:
                words.append(int(token, 16) & MASK32)
            except ValueError as error:
                raise ValueError(f"{path}:{line_number}: invalid hex word") from error
    return words


def write_words(path: Path, words: list[int | None]) -> None:
    lines = (
        "xxxxxxxx\n" if word is None else f"{word & MASK32:08x}\n"
        for word in words
    )
    path.write_text("".join(lines))


class RV32Model:
    def __init__(self, program: list[int], initial_data: list[int]):
        if len(program) > MEMORY_BYTES // 4:
            raise ValueError("program exceeds the 1024-word ISRAM")
        if len(initial_data) > MEMORY_BYTES // 4:
            raise ValueError("initial data exceeds the 1024-word DSRAM")
        self.program = program
        self.data = bytearray(MEMORY_BYTES)
        self.defined = bytearray(MEMORY_BYTES)
        for index, word in enumerate(initial_data):
            self.data[index * 4:index * 4 + 4] = word.to_bytes(4, "little")
            self.defined[index * 4:index * 4 + 4] = b"\x01\x01\x01\x01"
        self.regs = [0] * 32
        self.pc = ISRAM_BASE
        self.highest_data_byte = len(initial_data) * 4

    def reg(self, index: int) -> int:
        return 0 if index == 0 else self.regs[index]

    def set_reg(self, index: int, value: int) -> None:
        if index:
            self.regs[index] = value & MASK32

    def data_offset(self, address: int, size: int) -> int:
        # The CPU has a direct, local DSRAM port, so program addresses are
        # offsets 0x000-0xfff. DSRAM_BASE is used only by the external debug
        # crossbar; accepting it here is also useful for future mapped tests.
        offset = address if address < MEMORY_BYTES else address - DSRAM_BASE
        if offset < 0 or offset + size > MEMORY_BYTES:
            raise RuntimeError(f"DSRAM access outside 0x1000-0x1fff: 0x{address:08x}")
        return offset

    def load(self, address: int, size: int, signed: bool) -> int:
        offset = self.data_offset(address, size)
        value = int.from_bytes(self.data[offset:offset + size], "little")
        return sign_extend(value, size * 8) & MASK32 if signed else value

    def store(self, address: int, size: int, value: int) -> None:
        offset = self.data_offset(address, size)
        self.data[offset:offset + size] = (value & ((1 << (size * 8)) - 1)).to_bytes(size, "little")
        self.defined[offset:offset + size] = bytes([1]) * size
        self.highest_data_byte = max(self.highest_data_byte, offset + size)

    def step(self) -> bool:
        if self.pc & 3:
            raise RuntimeError(f"misaligned instruction PC 0x{self.pc:08x}")
        index = (self.pc - ISRAM_BASE) // 4
        if index < 0 or index >= len(self.program):
            raise RuntimeError(f"instruction fetch outside program at 0x{self.pc:08x}")

        insn = self.program[index]
        if insn == EBREAK:
            return False

        opcode = insn & 0x7F
        rd = (insn >> 7) & 0x1F
        funct3 = (insn >> 12) & 7
        rs1 = (insn >> 15) & 0x1F
        rs2 = (insn >> 20) & 0x1F
        funct7 = (insn >> 25) & 0x7F
        next_pc = (self.pc + 4) & MASK32

        imm_i = sign_extend(insn >> 20, 12)
        imm_s = sign_extend(((insn >> 25) << 5) | ((insn >> 7) & 0x1F), 12)
        imm_b = sign_extend(
            ((insn >> 31) << 12)
            | (((insn >> 7) & 1) << 11)
            | (((insn >> 25) & 0x3F) << 5)
            | (((insn >> 8) & 0xF) << 1), 13)
        imm_u = insn & 0xFFFFF000
        imm_j = sign_extend(
            ((insn >> 31) << 20)
            | (((insn >> 12) & 0xFF) << 12)
            | (((insn >> 20) & 1) << 11)
            | (((insn >> 21) & 0x3FF) << 1), 21)

        a, b = self.reg(rs1), self.reg(rs2)

        if opcode == 0x37:  # LUI
            self.set_reg(rd, imm_u)
        elif opcode == 0x17:  # AUIPC
            self.set_reg(rd, self.pc + imm_u)
        elif opcode == 0x6F:  # JAL
            self.set_reg(rd, next_pc)
            next_pc = (self.pc + imm_j) & MASK32
        elif opcode == 0x67 and funct3 == 0:  # JALR
            self.set_reg(rd, next_pc)
            next_pc = (a + imm_i) & ~1 & MASK32
        elif opcode == 0x63:  # branches
            conditions = {
                0: a == b,
                1: a != b,
                4: signed32(a) < signed32(b),
                5: signed32(a) >= signed32(b),
                6: a < b,
                7: a >= b,
            }
            if funct3 not in conditions:
                raise RuntimeError(f"unsupported branch funct3 {funct3}")
            if conditions[funct3]:
                next_pc = (self.pc + imm_b) & MASK32
        elif opcode == 0x03:  # loads
            formats = {0: (1, True), 1: (2, True), 2: (4, True), 4: (1, False), 5: (2, False)}
            if funct3 not in formats:
                raise RuntimeError(f"unsupported load funct3 {funct3}")
            size, signed = formats[funct3]
            self.set_reg(rd, self.load((a + imm_i) & MASK32, size, signed))
        elif opcode == 0x23:  # stores
            sizes = {0: 1, 1: 2, 2: 4}
            if funct3 not in sizes:
                raise RuntimeError(f"unsupported store funct3 {funct3}")
            self.store((a + imm_s) & MASK32, sizes[funct3], b)
        elif opcode == 0x13:  # immediate ALU
            shamt = rs2
            if funct3 == 0:
                result = a + imm_i
            elif funct3 == 2:
                result = int(signed32(a) < imm_i)
            elif funct3 == 3:
                result = int(a < (imm_i & MASK32))
            elif funct3 == 4:
                result = a ^ imm_i
            elif funct3 == 6:
                result = a | imm_i
            elif funct3 == 7:
                result = a & imm_i
            elif funct3 == 1 and funct7 == 0:
                result = a << shamt
            elif funct3 == 5 and funct7 == 0:
                result = a >> shamt
            elif funct3 == 5 and funct7 == 0x20:
                result = signed32(a) >> shamt
            else:
                raise RuntimeError(f"unsupported OP-IMM instruction 0x{insn:08x}")
            self.set_reg(rd, result)
        elif opcode == 0x33:  # register ALU
            key = (funct7, funct3)
            operations = {
                (0x00, 0): lambda: a + b,
                (0x20, 0): lambda: a - b,
                (0x00, 1): lambda: a << (b & 31),
                (0x00, 2): lambda: int(signed32(a) < signed32(b)),
                (0x00, 3): lambda: int(a < b),
                (0x00, 4): lambda: a ^ b,
                (0x00, 5): lambda: a >> (b & 31),
                (0x20, 5): lambda: signed32(a) >> (b & 31),
                (0x00, 6): lambda: a | b,
                (0x00, 7): lambda: a & b,
            }
            if key not in operations:
                raise RuntimeError(f"unsupported OP instruction 0x{insn:08x}")
            self.set_reg(rd, operations[key]())
        else:
            raise RuntimeError(f"unsupported instruction 0x{insn:08x} at PC 0x{self.pc:08x}")

        self.pc = next_pc
        self.regs[0] = 0
        return True

    def run(self, max_instructions: int) -> int:
        for count in range(1, max_instructions + 1):
            if not self.step():
                return count
        raise RuntimeError(f"program did not execute EBREAK within {max_instructions} instructions")

    def data_words(self) -> list[int | None]:
        count = (self.highest_data_byte + 3) // 4
        words: list[int | None] = []
        for i in range(count):
            offset = i * 4
            if all(self.defined[offset:offset + 4]):
                words.append(int.from_bytes(self.data[offset:offset + 4], "little"))
            else:
                words.append(None)
        return words


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--program", type=Path, required=True)
    parser.add_argument("--data", type=Path)
    parser.add_argument("--regs-out", type=Path, required=True)
    parser.add_argument("--data-out", type=Path, required=True)
    parser.add_argument("--max-instructions", type=int, default=10000)
    args = parser.parse_args()

    model = RV32Model(read_words(args.program), read_words(args.data))
    count = model.run(args.max_instructions)
    write_words(args.regs_out, model.regs)
    write_words(args.data_out, model.data_words())
    print(f"Reference model halted after {count} instructions")


if __name__ == "__main__":
    main()
