_start:
    addi x1, x0, 1
    beq  x1, x0, target
    addi x2, x0, 1
target:
    addi x3, x0, 2
    ebreak
