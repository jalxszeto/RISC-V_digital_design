_start:
    addi x1, x0, 10
    addi x2, x0, 20
    sw   x1, 4(x0)
    sw   x2, 8(x0)
    addi x3, x0, 99
    sw   x3, 8(x0)
    ebreak
