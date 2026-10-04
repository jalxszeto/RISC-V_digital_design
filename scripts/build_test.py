#!/usr/bin/env python3
"""Assemble one tests/<name>/program.asm and generate its golden (Expected outputs)."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import struct
import subprocess

from rv32_model import RV32Model, read_words, write_words


REPO_ROOT = Path(__file__).resolve().parents[1]


def find_assembler(explicit: str | None) -> str:
    candidates = [
        explicit,
        os.environ.get("RISCV_AS"),
        REPO_ROOT / "scripts" / "riscv-none-elf-as",
        "riscv-none-elf-as",
        "riscv32-unknown-elf-as",
        "riscv64-unknown-elf-as",
    ]
    for candidate in candidates:
        if not candidate:
            continue
        candidate = str(candidate)
        resolved = shutil.which(candidate)
        if resolved:
            return resolved
        path = Path(candidate)
        try:
            if path.is_file() and os.access(path, os.X_OK):
                return str(path)
        except OSError:
            continue
    raise RuntimeError(
        "RISC-V GNU assembler not found; "
        "or set RISCV_AS=/path/to/riscv-*-as"
    )


def elf_text(path: Path) -> bytes:
    image = path.read_bytes()
    if image[:4] != b"\x7fELF" or image[4] != 1 or image[5] != 1:
        raise RuntimeError(f"{path} is not a little-endian ELF32 object")
    section_offset = struct.unpack_from("<I", image, 32)[0]
    section_size = struct.unpack_from("<H", image, 46)[0]
    section_count = struct.unpack_from("<H", image, 48)[0]
    names_index = struct.unpack_from("<H", image, 50)[0]
    names_header = section_offset + names_index * section_size
    names_offset, names_size = struct.unpack_from("<II", image, names_header + 16)
    names = image[names_offset:names_offset + names_size]

    for index in range(section_count):
        header = section_offset + index * section_size
        name_index = struct.unpack_from("<I", image, header)[0]
        end = names.find(b"\0", name_index)
        name = names[name_index:end].decode()
        if name == ".text":
            offset, size = struct.unpack_from("<II", image, header + 16)
            return image[offset:offset + size]
    raise RuntimeError(f"{path} has no .text section")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("test_dir", type=Path)
    parser.add_argument("--assembler")
    parser.add_argument("--max-instructions", type=int, default=10000)
    args = parser.parse_args()

    test_dir = args.test_dir.resolve()
    source = test_dir / "program.asm"
    if not source.is_file():
        raise RuntimeError(f"missing required {source}")

    assembler = find_assembler(args.assembler)
    obj = test_dir / "program.o"
    subprocess.run(
        [assembler, "-march=rv32i", "-mabi=ilp32", "-mno-relax", str(source), "-o", str(obj)],
        check=True,
    )
    text = elf_text(obj)
    if len(text) % 4:
        raise RuntimeError(".text size is not a multiple of four bytes")
    program = [int.from_bytes(text[i:i + 4], "little") for i in range(0, len(text), 4)]
    program_path = test_dir / "program.hex"
    write_words(program_path, program)

    data_path = test_dir / "data.hex"
    initial_data = read_words(data_path if data_path.exists() else None)
    model = RV32Model(program, initial_data)
    count = model.run(args.max_instructions)
    write_words(test_dir / "expected_regs.hex", model.regs)
    write_words(test_dir / "expected_data.hex", model.data_words())
    print(f"Built {test_dir.name}: {len(program)} words, halted after {count} instructions")


if __name__ == "__main__":
    main()
