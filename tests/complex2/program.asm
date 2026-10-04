_start:
    addi x1, x0, 4
    addi x2, x0, 32
    addi x3, x0, 4
    addi x4, x0, 0
    addi x7, x0, 2
    addi x9, x0, 1

revloop:
    sll  x5, x3, x7
    add  x6, x1, x5
    lw   x8, 0(x6)
    sll  x10, x4, x7
    add  x11, x2, x10
    sw   x8, 0(x11)
    addi x4, x4, 1
    addi x3, x3, -1
    addi x12, x3, 1
    beq  x12, x0, done
    beq  x0, x0, revloop

done:
    lw   x13, 32(x0)
    lw   x14, 48(x0)
    addi x15, x0, 55
    beq  x13, x15, chk2
    addi x31, x0, 0
    ebreak
chk2:
    addi x16, x0, 11
    beq  x14, x16, pass
    addi x31, x0, 0
    ebreak
pass:
    addi x31, x0, 1
    ebreak
