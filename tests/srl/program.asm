_start:
    addi x1, x0, -1
    addi x2, x0, 4
    srl  x3, x1, x2
    addi x4, x0, 31
    srl  x5, x1, x4
    addi x6, x0, 0
    srl  x7, x1, x6
    ebreak
