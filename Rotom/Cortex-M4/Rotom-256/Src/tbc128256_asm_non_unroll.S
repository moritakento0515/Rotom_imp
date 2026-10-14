#define __ASSEMBLER__ 1
#include "define.h"

#if TBC128256_USE_ASM

    .syntax unified
    .cpu cortex-m4
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

    .macro SBOX_PAIR_ENC w, hi, tmp, c
    smulbb  \tmp, \w, \c
    smultb  \hi, \w, \c
    pkhbt   \w, \tmp, \hi, lsl #16
    uxtb16  \tmp, \w, ror #8
    eor.w   \w, \w, \tmp

    smulbb  \tmp, \w, \c
    smultb  \hi, \w, \c
    bfi     \tmp, \tmp, #16, #16
    bfi     \hi, \hi, #16, #16

    eor.w   \w, \tmp, \tmp, ror #12
    eor.w   \tmp, \w, \tmp, ror #4
    eor.w   \w, \hi, \hi, ror #12
    eor.w   \hi, \w, \hi, ror #4

    smulbb  \tmp, \tmp, \c
    smulbb  \hi, \hi, \c
    pkhbt   \w, \tmp, \hi, lsl #16
    .endm

    .macro SBOX_PAIR_DEC w, hi, tmp, c
    smulbb  \tmp, \w, \c
    smultb  \hi, \w, \c
    bfi     \tmp, \tmp, #16, #16
    bfi     \hi, \hi, #16, #16

    eor.w   \w, \tmp, \tmp, ror #12
    eor.w   \tmp, \w, \tmp, ror #4
    eor.w   \w, \hi, \hi, ror #12
    eor.w   \hi, \w, \hi, ror #4

    smulbb  \tmp, \tmp, \c
    smulbb  \hi, \hi, \c
    pkhbt   \w, \tmp, \hi, lsl #16
    uxtb16  \tmp, \w, ror #8
    eor.w   \w, \w, \tmp

    smulbb  \tmp, \w, \c
    smultb  \hi, \w, \c
    pkhbt   \w, \tmp, \hi, lsl #16
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
    .macro ENC_WHITEN_IN ptr
    mov     r5, lr
    ldmia.w \ptr, {r8-r11}
    add.w   \ptr, \ptr, #16
    ldmia.w \ptr!, {r6-r7}
    ADD_KEY
    add.w   r0, r0, r6
    add.w   r1, r1, r7
    ldmia.w \ptr, {r6-r7}
    add.w   r2, r2, r6
    add.w   r3, r3, r7
    bl      .L_tbc128256_enc_whiten_matrix_layer
    ldmia.w \ptr, {r6-r7}
    ADD_KEY
    add.w   r0, r0, r6
    add.w   r1, r1, r7
    ldmdb.w \ptr, {r6-r7}
    add.w   r2, r2, r6
    add.w   r3, r3, r7
    bl      .L_tbc128256_enc_whiten_matrix_layer
    mov     lr, r5
    .endm

    .macro ENC_WHITEN_OUT ptr
    mov     r5, lr
    ldmia.w \ptr!, {r8-r11}
    ldmia.w \ptr!, {r6-r7}
    ADD_KEY_ROT32
    add.w   r0, r0, r6
    add.w   r1, r1, r7
    ldmia.w \ptr, {r6-r7}
    add.w   r2, r2, r6
    add.w   r3, r3, r7
    bl      .L_tbc128256_enc_whiten_matrix_layer
    ldmia.w \ptr, {r6-r7}
    ADD_KEY_ROT32
    add.w   r0, r0, r6
    add.w   r1, r1, r7
    ldmdb.w \ptr, {r6-r7}
    add.w   r2, r2, r6
    add.w   r3, r3, r7
    mov     lr, r5
    .endm

    .macro DEC_WHITEN_IN ptr
    mov     r5, lr
    ldmia.w \ptr!, {r8-r11}
    add.w   \ptr, \ptr, #8
    ldmia.w \ptr, {r6-r7}
    SUB_KEY_ROT32
    sub.w   r0, r0, r6
    sub.w   r1, r1, r7
    ldmdb.w \ptr, {r6-r7}
    sub.w   r2, r2, r6
    sub.w   r3, r3, r7
    bl      .L_tbc128256_dec_whiten_matrix_layer_inv
    ldmdb.w \ptr, {r6-r7}
    SUB_KEY_ROT32
    sub.w   r0, r0, r6
    sub.w   r1, r1, r7
    ldmia.w \ptr, {r6-r7}
    sub.w   r2, r2, r6
    sub.w   r3, r3, r7
    bl      .L_tbc128256_dec_whiten_matrix_layer_inv
    mov     lr, r5
    .endm

    .macro DEC_WHITEN_OUT ptr
    mov     r5, lr
    ldmia.w \ptr, {r8-r11}
    add.w   \ptr, \ptr, #24
    ldmia.w \ptr, {r6-r7}
    SUB_KEY
    sub.w   r0, r0, r6
    sub.w   r1, r1, r7
    ldmdb.w \ptr, {r6-r7}
    sub.w   r2, r2, r6
    sub.w   r3, r3, r7
    bl      .L_tbc128256_dec_whiten_matrix_layer_inv
    ldmdb.w \ptr, {r6-r7}
    SUB_KEY
    sub.w   r0, r0, r6
    sub.w   r1, r1, r7
    ldmia.w \ptr, {r6-r7}
    sub.w   r2, r2, r6
    sub.w   r3, r3, r7
    mov     lr, r5
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

    .macro LOAD_TK_KEY_FOR_COUNTER slot
    ldr.w   r7, [sp, #\slot]
#if TBC128256_ROUNDS == 6
    tst     r6, #1
    beq     99f
    add.w   r7, r7, #16
99:
#else
    tst     r6, #1
    bne     99f
    add.w   r7, r7, #16
99:
#endif
    ldmia.w r7, {r8-r11}
    .endm

    .macro LOAD_NEXT_RC_AND_XOR_TK_KEY slot
    LOAD_TK_KEY_FOR_COUNTER \slot
    LOAD_NEXT_RC_AND_XOR_KEY
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
    mov     r7, r0
    ldmia.w r7, {r0-r3}

    movw    r5, #0x809b
    adr.w   lr, .L_tbc128256_round_constants
    movs    r6, #TBC128256_ROUNDS
.L_tbc128256_tk_round_loop:
    LOAD_NEXT_RC_AND_XOR_TK_KEY TBC128256_TK_KEYPTR
    stmia.w r4!, {r0-r3}
    SBOX_LAYER_ENC
    subs    r6, r6, #1
    beq     .L_tbc128256_tk_round_done
    MATRIX_LAYER
    b       .L_tbc128256_tk_round_loop

.L_tbc128256_tk_round_done:
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

    movs    r6, #TBC128256_ROUNDS
.L_tbc128256_enc_round_loop:
    XOR_RK_FORWARD
    SBOX_LAYER_ENC
    subs    r6, r6, #1
    beq     .L_tbc128256_enc_round_done
    MATRIX_LAYER
    b       .L_tbc128256_enc_round_loop
.L_tbc128256_enc_round_done:

    XOR_RK_FORWARD
    MATRIX_LAYER

    ldr     r12, [sp, #0]
    ENC_WHITEN_OUT r12
    stmia.w lr, {r0-r3}
    add     sp, sp, #4
    pop.w   {r4-r11, pc}

.L_tbc128256_enc_whiten_matrix_layer:
    MATRIX_LAYER
    bx      lr

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
    movs    r6, #TBC128256_ROUNDS
.L_tbc128256_dec_round_loop:
    cmp     r6, #TBC128256_ROUNDS
    beq     99f
    MATRIX_LAYER_INV
99:
    SBOX_LAYER_DEC
    XOR_RK_BACKWARD
    subs    r6, r6, #1
    beq     .L_tbc128256_dec_round_done
    b       .L_tbc128256_dec_round_loop

.L_tbc128256_dec_round_done:
    MATRIX_LAYER_INV
    ldr     r12, [sp, #0]
    DEC_WHITEN_OUT r12
    stmia.w lr, {r0-r3}
    add     sp, sp, #4
    pop.w   {r4-r11, pc}

.L_tbc128256_dec_whiten_matrix_layer_inv:
    MATRIX_LAYER_INV
    bx      lr

    .size tbc128256_decrypt_precomputed_tk_asm, .-tbc128256_decrypt_precomputed_tk_asm

#endif /* TBC128256_USE_ASM */
