#ifndef ROTOM256_DEFINE_H_
#define ROTOM256_DEFINE_H_

#ifndef __ASSEMBLER__
#include <stdint.h>
#endif

/* Rotom-256* uses 6 rounds; Rotom-256 uses 7 rounds. */
#ifndef TBC128256_ROUNDS
#define TBC128256_ROUNDS 7
#endif

#ifndef TBC128256_USE_ASM
#define TBC128256_USE_ASM 1
#endif

#if !TBC128256_USE_ASM
#error "The ASM package must be built with TBC128256_USE_ASM=1."
#endif

#if (TBC128256_ROUNDS != 6) && (TBC128256_ROUNDS != 7)
#error "TBC128256_ROUNDS must be 6 for Rotom-256* or 7 for Rotom-256."
#endif

#define TBC128256_BLOCK_BITS 128
#define TBC128256_BLOCK_BYTES 16
#define TBC128256_KEY_BITS 256
#define TBC128256_KEY_BYTES 32
#define TBC128256_TWEAK_BITS 128
#define TBC128256_TWEAK_BYTES 16
#define TBC128256_WORDS 4
#define TBC128256_TK_WORDS (TBC128256_WORDS * (TBC128256_ROUNDS + 1))
#define TBC128256_TK_BYTES (TBC128256_TK_WORDS * 4)

#if TBC128256_ROUNDS == 6
#define TBC128256_NAME "Rotom-256*"
#else
#define TBC128256_NAME "Rotom-256"
#endif

#ifndef __ASSEMBLER__

void tbc128256_tweakey_sche_asm(uint8_t const tweak[TBC128256_TWEAK_BYTES],
								uint8_t const key[TBC128256_KEY_BYTES],
								uint32_t tk[TBC128256_TK_WORDS]);
void tbc128256_encrypt_precomputed_tk_asm(uint8_t ct[TBC128256_BLOCK_BYTES],
										  uint8_t const pt[TBC128256_BLOCK_BYTES],
										  uint8_t const key[TBC128256_KEY_BYTES],
										  uint32_t const tk[TBC128256_TK_WORDS]);
void tbc128256_decrypt_precomputed_tk_asm(uint8_t pt[TBC128256_BLOCK_BYTES],
										  uint8_t const ct[TBC128256_BLOCK_BYTES],
										  uint8_t const key[TBC128256_KEY_BYTES],
										  uint32_t const tk[TBC128256_TK_WORDS]);

#endif /* __ASSEMBLER__ */

#endif /* ROTOM256_DEFINE_H_ */
