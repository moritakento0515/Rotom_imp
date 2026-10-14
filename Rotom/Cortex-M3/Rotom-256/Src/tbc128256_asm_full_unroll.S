#define __ASSEMBLER__ 1
#include "define.h"

#if TBC128256_USE_ASM

    .syntax unified
    .cpu cortex-m3
    .thumb
    .text

#define TBC128256_TK_STACK_BYTES 4
#define TBC128256_TK_KEYPTR 0

@ Register contract
@   r0-r3   current 128-bit state words
@   r4      round tweakey pointer
@   r5      S-box multiplication constant (0x809b or 0x6593), or whitening scratch
@   r6      round counter, or whitening scratch
@   r7      S-box temporary
@   r8-r11  key words or loaded round tweakey words
@   r12     scratch register
@   lr      output pointer in encrypt/decrypt, or round-constant pointer in
@           the schedule.
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

@ ---- Whitening key ----

    .macro ADD_KEY
    add.w   r0, r0, r8
    add.w   r1, r1, r9
    add.w   r2, r2, r10
    add.w   r3, r3, r11
    .endm

    .macro ADD_KEY_ROT32
    add.w   r0, r0, r9
    add.w   r1, r1, r10
    add.w   r2, r2, r11
    add.w   r3, r3, r8
    .endm

    .macro SUB_KEY
    sub.w   r0, r0, r8
    sub.w   r1, r1, r9
    sub.w   r2, r2, r10
    sub.w   r3, r3, r11
    .endm

    .macro SUB_KEY_ROT32
    sub.w   r0, r0, r9
    sub.w   r1, r1, r10
    sub.w   r2, r2, r11
    sub.w   r3, r3, r8
    .endm

@ Keep the K0 half resident across each adjacent whitening pair and add the
@ K1 half directly to the state. This avoids reloading K0 for W1/W3.
@ r5 holds the output pointer while whitening matrix calls use lr.
    .macro ENC_WHITEN_IN ptr
    ldmia.w \ptr, {r8-r11}
    add.w   \ptr, \ptr, #16
    ldmia.w \ptr!, {r6-r7}
    ADD_KEY
    add.w   r0, r0, r6
    add.w   r1, r1, r7
    ldmia.w \ptr, {r6-r7}
    add.w   r2, r2, r6
    add.w   r3, r3, r7
    MATRIX_LAYER
    ldmia.w \ptr, {r6-r7}
    ADD_KEY
    add.w   r0, r0, r6
    add.w   r1, r1, r7
    ldmdb.w \ptr, {r6-r7}
    add.w   r2, r2, r6
    add.w   r3, r3, r7
    MATRIX_LAYER
    .endm

    .macro ENC_WHITEN_OUT ptr
    ldmia.w \ptr!, {r8-r11}
    ldmia.w \ptr!, {r6-r7}
    ADD_KEY_ROT32
    add.w   r0, r0, r6
    add.w   r1, r1, r7
    ldmia.w \ptr, {r6-r7}
    add.w   r2, r2, r6
    add.w   r3, r3, r7
    MATRIX_LAYER
    ldmia.w \ptr, {r6-r7}
    ADD_KEY_ROT32
    add.w   r0, r0, r6
    add.w   r1, r1, r7
    ldmdb.w \ptr, {r6-r7}
    add.w   r2, r2, r6
    add.w   r3, r3, r7
    .endm

    .macro DEC_WHITEN_IN ptr
    ldmia.w \ptr!, {r8-r11}
    add.w   \ptr, \ptr, #8
    ldmia.w \ptr, {r6-r7}
    SUB_KEY_ROT32
    sub.w   r0, r0, r6
    sub.w   r1, r1, r7
    ldmdb.w \ptr, {r6-r7}
    sub.w   r2, r2, r6
    sub.w   r3, r3, r7
    MATRIX_LAYER_INV
    ldmdb.w \ptr, {r6-r7}
    SUB_KEY_ROT32
    sub.w   r0, r0, r6
    sub.w   r1, r1, r7
    ldmia.w \ptr, {r6-r7}
    sub.w   r2, r2, r6
    sub.w   r3, r3, r7
    MATRIX_LAYER_INV
    .endm

    .macro DEC_WHITEN_OUT ptr
    ldmia.w \ptr, {r8-r11}
    add.w   \ptr, \ptr, #24
    ldmia.w \ptr, {r6-r7}
    SUB_KEY
    sub.w   r0, r0, r6
    sub.w   r1, r1, r7
    ldmdb.w \ptr, {r6-r7}
    sub.w   r2, r2, r6
    sub.w   r3, r3, r7
    MATRIX_LAYER_INV
    ldmdb.w \ptr, {r6-r7}
    SUB_KEY
    sub.w   r0, r0, r6
    sub.w   r1, r1, r7
    ldmia.w \ptr, {r6-r7}
    sub.w   r2, r2, r6
    sub.w   r3, r3, r7
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

    .macro LOAD_CURRENT_RC_AND_XOR_KEY
    ldr.w   r12, [lr]
    XOR_KEY_AND_RC
    .endm

    .macro LOAD_TK_KEY0 slot
    ldr.w   r7, [sp, #\slot]
    ldmia.w r7, {r8-r11}
    .endm

    .macro LOAD_TK_KEY1 slot
    ldr.w   r7, [sp, #\slot]
    add.w   r7, r7, #16
    ldmia.w r7, {r8-r11}
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

    .macro TK_SCHEDULE_ROUND_FULL_UNROLL_K0
    LOAD_TK_KEY0 TBC128256_TK_KEYPTR
    LOAD_NEXT_RC_AND_XOR_KEY
    stmia.w r4!, {r0-r3}
    SBOX_LAYER_ENC
    MATRIX_LAYER
    .endm

    .macro TK_SCHEDULE_ROUND_FULL_UNROLL_K1
    LOAD_TK_KEY1 TBC128256_TK_KEYPTR
    LOAD_NEXT_RC_AND_XOR_KEY
    stmia.w r4!, {r0-r3}
    SBOX_LAYER_ENC
    MATRIX_LAYER
    .endm

@ ---- Tweakey schedule ----

    .global tbc128256_tweakey_sche_asm
    .type tbc128256_tweakey_sche_asm, %function
    .thumb_func
tbc128256_tweakey_sche_asm:
@ Arguments:
@   r0 = tweak input, r1 = key input, r2 = output TK buffer
    push.w  {r4-r11, lr}
    sub     sp, sp, #TBC128256_TK_STACK_BYTES
    mov     r4, r2
    str     r1, [sp, #TBC128256_TK_KEYPTR]
    ldmia.w r0, {r0-r3}

    movw    r5, #0x809b
    adr.w   lr, .L_tbc128256_round_constants
    TK_SCHEDULE_ROUND_FULL_UNROLL_K0
    TK_SCHEDULE_ROUND_FULL_UNROLL_K1
    TK_SCHEDULE_ROUND_FULL_UNROLL_K0
    TK_SCHEDULE_ROUND_FULL_UNROLL_K1
    TK_SCHEDULE_ROUND_FULL_UNROLL_K0
#if TBC128256_ROUNDS == 6
    LOAD_TK_KEY1 TBC128256_TK_KEYPTR
#else
    TK_SCHEDULE_ROUND_FULL_UNROLL_K1
    LOAD_TK_KEY0 TBC128256_TK_KEYPTR
#endif
    LOAD_NEXT_RC_AND_XOR_KEY
    stmia.w r4!, {r0-r3}
    SBOX_LAYER_ENC
#if TBC128256_ROUNDS == 6
    LOAD_TK_KEY0 TBC128256_TK_KEYPTR
#else
    LOAD_TK_KEY1 TBC128256_TK_KEYPTR
#endif
    LOAD_CURRENT_RC_AND_XOR_KEY
    stmia.w r4, {r0-r3}

    add     sp, sp, #TBC128256_TK_STACK_BYTES
    pop.w   {r4-r11, pc}

    .align 2
.L_tbc128256_round_constants:
    .word   0x243f6a88
    .word   0x85a308d3
    .word   0x13198a2e
    .word   0x03707344
    .word   0xa4093822
    .word   0x299f31d0
    .word   0x082efa98
#if TBC128256_ROUNDS == 7
    .word   0xec4e6c89
#endif

    .size tbc128256_tweakey_sche_asm, .-tbc128256_tweakey_sche_asm

@ ---- Encryption ----

    .global tbc128256_encrypt_precomputed_tk_asm
    .type tbc128256_encrypt_precomputed_tk_asm, %function
    .thumb_func
tbc128256_encrypt_precomputed_tk_asm:
@ Arguments:
@   r0 = ciphertext output, r1 = plaintext input, r2 = key input, r3 = TK buffer
    push.w  {r4-r11, lr}
    sub     sp, sp, #4
    str     r2, [sp]
    mov     lr, r0
    mov     r4, r3
    ldmia.w r1, {r0-r3}

    ldr     r12, [sp, #0]
    ENC_WHITEN_IN r12

    movw    r5, #0x809b

    ENC_ROUND_FULL
    ENC_ROUND_FULL
    ENC_ROUND_FULL
    ENC_ROUND_FULL
    ENC_ROUND_FULL
#if TBC128256_ROUNDS == 7
    ENC_ROUND_FULL
#endif
    XOR_RK_FORWARD
    SBOX_LAYER_ENC

    XOR_RK_FORWARD
    MATRIX_LAYER

    ldr     r12, [sp, #0]
    ENC_WHITEN_OUT r12
    stmia.w lr, {r0-r3}
    add     sp, sp, #4
    pop.w   {r4-r11, pc}

    .size tbc128256_encrypt_precomputed_tk_asm, .-tbc128256_encrypt_precomputed_tk_asm

@ ---- Decryption ----

    .global tbc128256_decrypt_precomputed_tk_asm
    .type tbc128256_decrypt_precomputed_tk_asm, %function
    .thumb_func
tbc128256_decrypt_precomputed_tk_asm:
@ Arguments:
@   r0 = plaintext output, r1 = ciphertext input, r2 = key input, r3 = TK buffer
    push.w  {r4-r11, lr}
    sub     sp, sp, #4
    str     r2, [sp]
    mov     lr, r0
    mov     r4, r3
    add.w   r4, r4, #(TBC128256_TK_WORDS * 4)
    ldmia.w r1, {r0-r3}

    ldr     r12, [sp, #0]
    DEC_WHITEN_IN r12

    XOR_RK_BACKWARD

    movw    r5, #0x6593
    SBOX_LAYER_DEC
    XOR_RK_BACKWARD
    DEC_ROUND_FULL
    DEC_ROUND_FULL
    DEC_ROUND_FULL
    DEC_ROUND_FULL
    DEC_ROUND_FULL
#if TBC128256_ROUNDS == 7
    DEC_ROUND_FULL
#endif

    MATRIX_LAYER_INV
    ldr     r12, [sp, #0]
    DEC_WHITEN_OUT r12
    stmia.w lr, {r0-r3}
    add     sp, sp, #4
    pop.w   {r4-r11, pc}

    .size tbc128256_decrypt_precomputed_tk_asm, .-tbc128256_decrypt_precomputed_tk_asm

#endif /* TBC128256_USE_ASM */
