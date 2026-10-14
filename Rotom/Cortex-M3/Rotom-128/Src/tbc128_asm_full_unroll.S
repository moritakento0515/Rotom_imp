#define __ASSEMBLER__ 1
#include "define.h"

#if TBC128_USE_ASM

    .syntax unified
    .cpu cortex-m3
    .thumb
    .text

@ Register contract
@   r0-r3   current 128-bit state words
@   r4      round tweakey pointer
@   r5      S-box multiplication constant (0x809b or 0x6593)
@   r6      round counter
@   r7      S-box temporary
@   r8-r11  key words or loaded round tweakey words
@   r12     scratch register
@   lr      output pointer, or round-constant pointer in the schedule
@ LDM/STM require word-aligned state, key, and round-tweakey buffers.

@ ---- S-box ----

    .macro SBOX16_ENC x, tmp, c
    mul     \x, \x, \c
    uxth    \x, \x
    eor.w   \x, \x, \x, lsr #8

    mul     \x, \x, \c
    bfi     \x, \x, #16, #16
    eor.w   \tmp, \x, \x, ror #12
    eor.w   \x, \tmp, \x, ror #4

    mul     \x, \x, \c
    .endm

    .macro SBOX16_DEC x, tmp, c
    mul     \x, \x, \c
    bfi     \x, \x, #16, #16
    eor.w   \tmp, \x, \x, ror #12
    eor.w   \x, \tmp, \x, ror #4

    mul     \x, \x, \c
    uxth    \x, \x
    eor.w   \x, \x, \x, lsr #8

    mul     \x, \x, \c
    .endm

    .macro SBOX_PAIR_ENC w, hi, tmp, c
    lsr.w   \hi, \w, #16
    SBOX16_ENC \w, \tmp, \c
    SBOX16_ENC \hi, \tmp, \c
    bfi     \w, \hi, #16, #16
    .endm

    .macro SBOX_PAIR_DEC w, hi, tmp, c
    lsr.w   \hi, \w, #16
    SBOX16_DEC \w, \tmp, \c
    SBOX16_DEC \hi, \tmp, \c
    bfi     \w, \hi, #16, #16
    .endm

    .macro SBOX_LAYER_ENC
    SBOX_PAIR_ENC r0, r12, r7, r5
    SBOX_PAIR_ENC r1, r12, r7, r5
    SBOX_PAIR_ENC r2, r12, r7, r5
    SBOX_PAIR_ENC r3, r12, r7, r5
    .endm

    .macro SBOX_LAYER_DEC
    SBOX_PAIR_DEC r0, r12, r7, r5
    SBOX_PAIR_DEC r1, r12, r7, r5
    SBOX_PAIR_DEC r2, r12, r7, r5
    SBOX_PAIR_DEC r3, r12, r7, r5
    .endm

@ ---- Matrix ----

    .macro MATRIX_LAYER
    eor.w   r0, r0, r3, ror #8
    eor.w   r1, r1, r2, ror #8
    eor.w   r2, r2, r1, ror #8
    eor.w   r3, r3, r0, ror #8

    eor.w   r0, r0, r2
    eor.w   r1, r1, r3
    eor.w   r2, r2, r1
    eor.w   r3, r3, r0

    eor.w   r0, r0, r2, ror #19
    eor.w   r1, r1, r3, ror #19
    eor.w   r2, r2, r0, ror #19
    eor.w   r3, r3, r1, ror #19
    .endm

    .macro MATRIX_LAYER_INV
    eor.w   r3, r3, r1, ror #19
    eor.w   r2, r2, r0, ror #19
    eor.w   r1, r1, r3, ror #19
    eor.w   r0, r0, r2, ror #19

    eor.w   r3, r3, r0
    eor.w   r2, r2, r1
    eor.w   r1, r1, r3
    eor.w   r0, r0, r2

    eor.w   r3, r3, r0, ror #8
    eor.w   r2, r2, r1, ror #8
    eor.w   r1, r1, r2, ror #8
    eor.w   r0, r0, r3, ror #8
    .endm

@ ---- Tweakey schedule macros ----

    .macro XOR_KEY_AND_RC
    eor.w   r0, r0, r8
    eor.w   r0, r0, r12
    eor.w   r1, r1, r9
    eor.w   r2, r2, r10
    eor.w   r3, r3, r11
    .endm

    .macro LOAD_NEXT_RC_AND_XOR_KEY
    ldr.w   r12, [lr], #4
    XOR_KEY_AND_RC
    .endm

@ ---- Round tweakey macros ----

    .macro XOR_RK_FORWARD
    ldmia.w r4!, {r8-r11}
    eor.w   r0, r0, r8
    eor.w   r1, r1, r9
    eor.w   r2, r2, r10
    eor.w   r3, r3, r11
    .endm

    .macro XOR_RK_BACKWARD
    ldmdb.w r4!, {r8-r11}
    eor.w   r0, r0, r8
    eor.w   r1, r1, r9
    eor.w   r2, r2, r10
    eor.w   r3, r3, r11
    .endm

@ ---- Round macros ----

    .macro ENC_ROUND_FULL
    XOR_RK_FORWARD
    SBOX_LAYER_ENC
    MATRIX_LAYER
    .endm

    .macro DEC_ROUND_FULL
    MATRIX_LAYER_INV
    SBOX_LAYER_DEC
    XOR_RK_BACKWARD
    .endm

    .macro TK_SCHEDULE_ROUND_FULL
    LOAD_NEXT_RC_AND_XOR_KEY
    stmia.w r4!, {r0-r3}
    SBOX_LAYER_ENC
    MATRIX_LAYER
    .endm

@ ---- Tweakey schedule ----

    .global tbc128_tweakey_sche_asm
    .type tbc128_tweakey_sche_asm, %function
    .thumb_func
tbc128_tweakey_sche_asm:
@ Arguments:
@   r0 = tweak input, r1 = key input, r2 = output TK buffer
    push.w  {r4-r11, lr}
    sub     sp, sp, #4
    mov     r4, r2
    ldmia.w r1, {r8-r11}
    ldmia.w r0, {r0-r3}

    movw    r5, #0x809b
    adr.w   lr, .L_tbc128_round_constants
    TK_SCHEDULE_ROUND_FULL
    TK_SCHEDULE_ROUND_FULL
    TK_SCHEDULE_ROUND_FULL
    TK_SCHEDULE_ROUND_FULL
#if TBC128_ROUNDS == 6
    TK_SCHEDULE_ROUND_FULL
#endif
    LOAD_NEXT_RC_AND_XOR_KEY
    stmia.w r4!, {r0-r3}
    SBOX_LAYER_ENC
    ldr.w   r12, [lr]
    XOR_KEY_AND_RC
    stmia.w r4, {r0-r3}

    add     sp, sp, #4
    pop.w   {r4-r11, pc}

    .align 2
.L_tbc128_round_constants:
    .word   0x243f6a88
    .word   0x85a308d3
    .word   0x13198a2e
    .word   0x03707344
    .word   0xa4093822
    .word   0x299f31d0
#if TBC128_ROUNDS == 6
    .word   0x082efa98
#endif

    .size tbc128_tweakey_sche_asm, .-tbc128_tweakey_sche_asm

@ ---- Encryption ----

    .global tbc128_encrypt_precomputed_tk_asm
    .type tbc128_encrypt_precomputed_tk_asm, %function
    .thumb_func
tbc128_encrypt_precomputed_tk_asm:
@ Arguments:
@   r0 = ciphertext output, r1 = plaintext input, r2 = key input, r3 = TK buffer
    push.w  {r4-r11, lr}
    sub     sp, sp, #4
    str     r2, [sp]
    mov     lr, r0
    mov     r4, r3
    ldmia.w r1, {r0-r3}

    ldr     r12, [sp, #0]
    ldmia.w r12, {r8-r11}
    add.w   r0, r0, r8
    add.w   r1, r1, r9
    add.w   r2, r2, r10
    add.w   r3, r3, r11
    MATRIX_LAYER

    movw    r5, #0x809b

    ENC_ROUND_FULL
    ENC_ROUND_FULL
    ENC_ROUND_FULL
    ENC_ROUND_FULL
#if TBC128_ROUNDS == 6
    ENC_ROUND_FULL
#endif
    XOR_RK_FORWARD
    SBOX_LAYER_ENC

    XOR_RK_FORWARD
    MATRIX_LAYER

    ldr     r12, [sp, #0]
    ldmia.w r12, {r8-r11}
    add.w   r0, r0, r10
    add.w   r1, r1, r11
    add.w   r2, r2, r8
    add.w   r3, r3, r9
    stmia.w lr, {r0-r3}
    add     sp, sp, #4
    pop.w   {r4-r11, pc}

    .size tbc128_encrypt_precomputed_tk_asm, .-tbc128_encrypt_precomputed_tk_asm

@ ---- Decryption ----

    .global tbc128_decrypt_precomputed_tk_asm
    .type tbc128_decrypt_precomputed_tk_asm, %function
    .thumb_func
tbc128_decrypt_precomputed_tk_asm:
@ Arguments:
@   r0 = plaintext output, r1 = ciphertext input, r2 = key input, r3 = TK buffer
    push.w  {r4-r11, lr}
    sub     sp, sp, #4
    str     r2, [sp]
    mov     lr, r0
    mov     r4, r3
    add.w   r4, r4, #(TBC128_TK_WORDS * 4)
    ldmia.w r1, {r0-r3}

    ldr     r12, [sp, #0]
    ldmia.w r12, {r8-r11}
    sub.w   r0, r0, r10
    sub.w   r1, r1, r11
    sub.w   r2, r2, r8
    sub.w   r3, r3, r9
    MATRIX_LAYER_INV

    XOR_RK_BACKWARD

    movw    r5, #0x6593
    SBOX_LAYER_DEC
    XOR_RK_BACKWARD
    DEC_ROUND_FULL
    DEC_ROUND_FULL
    DEC_ROUND_FULL
    DEC_ROUND_FULL
#if TBC128_ROUNDS == 6
    DEC_ROUND_FULL
#endif

    MATRIX_LAYER_INV
    ldr     r12, [sp, #0]
    ldmia.w r12, {r8-r11}
    sub.w   r0, r0, r8
    sub.w   r1, r1, r9
    sub.w   r2, r2, r10
    sub.w   r3, r3, r11
    stmia.w lr, {r0-r3}
    add     sp, sp, #4
    pop.w   {r4-r11, pc}

    .size tbc128_decrypt_precomputed_tk_asm, .-tbc128_decrypt_precomputed_tk_asm

#endif /* TBC128_USE_ASM */
