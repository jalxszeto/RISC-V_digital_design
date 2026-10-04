_start:
    addi x1, x0, 4
    addi x2, x0, 5
    addi x7, x0, 1
    addi x8, x0, 4
    addi x9, x0, 31
    lw   x3, 0(x1)
    add  x1, x1, x8
    addi x2, x2, -1

maxloop:
    lw   x4, 0(x1)
    sub  x5, x3, x4
    srl  x6, x5, x9
    beq  x6, x0, keep
    add  x3, x0, x4
keep:
    add  x1, x1, x8
    sub  x2, x2, x7
    beq  x2, x0, done
    beq  x0, x0, maxloop

done:
    sw   x3, 28(x0)
    lw   x11, 28(x0)
    beq  x11, x3, pass
    addi x31, x0, 0
    ebreak
pass:
    addi x31, x0, 1
    ebreak
