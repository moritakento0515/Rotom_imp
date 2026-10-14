#ifndef ROTOM128_DEFINE_H_
#define ROTOM128_DEFINE_H_

#ifndef __ASSEMBLER__
#include <stdint.h>
#endif

/* Rotom-128* uses 5 rounds; Rotom-128 uses 6 rounds. */
#ifndef TBC128_ROUNDS
#define TBC128_ROUNDS 6
#endif

#ifndef TBC128_USE_ASM
#define TBC128_USE_ASM 1
#endif

#if !TBC128_USE_ASM
#error "The ASM package must be built with TBC128_USE_ASM=1."
#endif

#if (TBC128_ROUNDS != 5) && (TBC128_ROUNDS != 6)
#error "TBC128_ROUNDS must be 5 for Rotom-128* or 6 for Rotom-128."
#endif

#define TBC128_BLOCK_BITS 128
#define TBC128_BLOCK_BYTES 16
#define TBC128_KEY_BITS 128
#define TBC128_KEY_BYTES 16
#define TBC128_TWEAK_BITS 128
#define TBC128_TWEAK_BYTES 16
#define TBC128_WORDS 4
#define TBC128_TK_WORDS (TBC128_WORDS * (TBC128_ROUNDS + 1))
#define TBC128_TK_BYTES (TBC128_TK_WORDS * 4)

#if TBC128_ROUNDS == 5
#define TBC128_NAME "Rotom-128*"
#else
#define TBC128_NAME "Rotom-128"
#endif

#ifndef __ASSEMBLER__

void tbc128_tweakey_sche_asm(uint8_t const tweak[TBC128_TWEAK_BYTES],
							 uint8_t const key[TBC128_KEY_BYTES],
							 uint32_t tk[TBC128_TK_WORDS]);
void tbc128_encrypt_precomputed_tk_asm(uint8_t ct[TBC128_BLOCK_BYTES],
									   uint8_t const pt[TBC128_BLOCK_BYTES],
									   uint8_t const key[TBC128_KEY_BYTES],
									   uint32_t const tk[TBC128_TK_WORDS]);
void tbc128_decrypt_precomputed_tk_asm(uint8_t pt[TBC128_BLOCK_BYTES],
									   uint8_t const ct[TBC128_BLOCK_BYTES],
									   uint8_t const key[TBC128_KEY_BYTES],
									   uint32_t const tk[TBC128_TK_WORDS]);

#endif /* __ASSEMBLER__ */

#endif /* ROTOM128_DEFINE_H_ */
