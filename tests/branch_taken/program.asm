_start:
    addi x1, x0, 0
    beq  x1, x0, taken
    addi x2, x0, 1
taken:
    addi x3, x0, 2
    ebreak
