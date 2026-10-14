#include "define.h"

#define TBC128256_MASK16 0xffffu

static uint32_t const RC[TBC128256_ROUNDS + 1] = {
	0x243f6a88u,
	0x85a308d3u,
	0x13198a2eu,
	0x03707344u,
	0xa4093822u,
	0x299f31d0u,
	0x082efa98u,
#if TBC128256_ROUNDS == 7
	0xec4e6c89u,
#endif
};

static inline uint32_t rotl32(uint32_t x, uint32_t r)
{
	r &= 31u;
	return r == 0u ? x : ((x << r) | (x >> (32u - r)));
}

static inline uint32_t load32_le(uint8_t const *p)
{
	return ((uint32_t)p[0]) |
		   ((uint32_t)p[1] << 8) |
		   ((uint32_t)p[2] << 16) |
		   ((uint32_t)p[3] << 24);
}

static inline void store32_le(uint8_t *p, uint32_t x)
{
	p[0] = (uint8_t)x;
	p[1] = (uint8_t)(x >> 8);
	p[2] = (uint8_t)(x >> 16);
	p[3] = (uint8_t)(x >> 24);
}

static inline uint32_t sbox_rot_mix(uint32_t x)
{
	uint32_t y = (x & TBC128256_MASK16) | (x << 16);
	return y ^ ((y >> 12) | (y << 20)) ^ ((y >> 4) | (y << 28));
}

static inline uint32_t s16(uint32_t x)
{
	x = (x * 0x809bu) & TBC128256_MASK16;
	x ^= x >> 8;
	x = (x * 0x809bu) & TBC128256_MASK16;
	x = sbox_rot_mix(x);
	x *= 0x809bu;
	return x;
}

static inline uint32_t s16_inv(uint32_t x)
{
	x = (x * 0x6593u) & TBC128256_MASK16;
	x = sbox_rot_mix(x);
	x = (x * 0x6593u) & TBC128256_MASK16;
	x ^= x >> 8;
	x = (x * 0x6593u) & TBC128256_MASK16;
	return x;
}

static inline uint32_t sbox_pair(uint32_t w)
{
	uint32_t lo = s16(w);
	uint32_t hi = s16(w >> 16);
	return (lo & TBC128256_MASK16) | (hi << 16);
}

static inline uint32_t sbox_pair_inv(uint32_t w)
{
	uint32_t lo = s16_inv(w);
	uint32_t hi = s16_inv(w >> 16);
	return (lo & TBC128256_MASK16) | (hi << 16);
}

static inline void sbox_layer(uint32_t x[4])
{
	x[0] = sbox_pair(x[0]);
	x[1] = sbox_pair(x[1]);
	x[2] = sbox_pair(x[2]);
	x[3] = sbox_pair(x[3]);
}

static inline void matrix_layer(uint32_t x[4])
{
	uint32_t r0 = x[0];
	uint32_t r1 = x[1];
	uint32_t r2 = x[2];
	uint32_t r3 = x[3];

	r0 ^= rotl32(r3, 24);
	r1 ^= rotl32(r2, 24);
	r2 ^= rotl32(r1, 24);
	r3 ^= rotl32(r0, 24);

	r0 ^= r2;
	r1 ^= r3;
	r2 ^= r1;
	r3 ^= r0;

	r0 ^= rotl32(r2, 13);
	r1 ^= rotl32(r3, 13);
	r2 ^= rotl32(r0, 13);
	r3 ^= rotl32(r1, 13);

	x[0] = r0;
	x[1] = r1;
	x[2] = r2;
	x[3] = r3;
}

static inline void matrix_layer_inv(uint32_t x[4])
{
	uint32_t r0 = x[0];
	uint32_t r1 = x[1];
	uint32_t r2 = x[2];
	uint32_t r3 = x[3];

	r3 ^= rotl32(r1, 13);
	r2 ^= rotl32(r0, 13);
	r1 ^= rotl32(r3, 13);
	r0 ^= rotl32(r2, 13);

	r3 ^= r0;
	r2 ^= r1;
	r1 ^= r3;
	r0 ^= r2;

	r3 ^= rotl32(r0, 24);
	r2 ^= rotl32(r1, 24);
	r1 ^= rotl32(r2, 24);
	r0 ^= rotl32(r3, 24);

	x[0] = r0;
	x[1] = r1;
	x[2] = r2;
	x[3] = r3;
}

#define TBC128256_C_SBOX_INV_WORDS(x0, x1, x2, x3) \
	do { \
		(x0) = sbox_pair_inv(x0); \
		(x1) = sbox_pair_inv(x1); \
		(x2) = sbox_pair_inv(x2); \
		(x3) = sbox_pair_inv(x3); \
	} while (0)

static inline void load_state(uint32_t x[4], uint8_t const in[16])
{
	x[0] = load32_le(in + 0);
	x[1] = load32_le(in + 4);
	x[2] = load32_le(in + 8);
	x[3] = load32_le(in + 12);
}

static inline void store_state(uint8_t out[16], uint32_t const x[4])
{
	store32_le(out + 0, x[0]);
	store32_le(out + 4, x[1]);
	store32_le(out + 8, x[2]);
	store32_le(out + 12, x[3]);
}

void tbc128256_tweakey_sche(uint8_t const tweak[TBC128256_TWEAK_BYTES],
							uint8_t const key[TBC128256_KEY_BYTES],
							uint32_t tk[TBC128256_TK_WORDS])
{
	uint32_t ts[4];
	uint32_t k0[4];
	uint32_t k1[4];

	load_state(ts, tweak);
	load_state(k0, key);
	load_state(k1, key + 16);

	for (uint32_t r = 0; r < (uint32_t)TBC128256_ROUNDS; r++) {
		uint32_t *out = &tk[r * 4u];
		uint32_t const *kr = (r & 1u) == 0u ? k0 : k1;

		out[0] = ts[0] ^ kr[0] ^ RC[r];
		out[1] = ts[1] ^ kr[1];
		out[2] = ts[2] ^ kr[2];
		out[3] = ts[3] ^ kr[3];

		ts[0] = out[0];
		ts[1] = out[1];
		ts[2] = out[2];
		ts[3] = out[3];
		sbox_layer(ts);
		if (r != (uint32_t)(TBC128256_ROUNDS - 1)) {
			matrix_layer(ts);
		}
	}

	uint32_t const *kr = (TBC128256_ROUNDS & 1u) == 0u ? k0 : k1;
	tk[TBC128256_ROUNDS * 4u + 0u] = ts[0] ^ kr[0] ^ RC[TBC128256_ROUNDS];
	tk[TBC128256_ROUNDS * 4u + 1u] = ts[1] ^ kr[1];
	tk[TBC128256_ROUNDS * 4u + 2u] = ts[2] ^ kr[2];
	tk[TBC128256_ROUNDS * 4u + 3u] = ts[3] ^ kr[3];
}

void tbc128256_encrypt_precomputed_tk(uint8_t ct[TBC128256_BLOCK_BYTES],
									  uint8_t const pt[TBC128256_BLOCK_BYTES],
									  uint8_t const key[TBC128256_KEY_BYTES],
									  uint32_t const tk[TBC128256_TK_WORDS])
{
	uint32_t sp[4];
	uint32_t k0[4];
	uint32_t k1[4];

	load_state(sp, pt);
	load_state(k0, key);
	load_state(k1, key + 16);

	sp[0] += k0[0] + k1[0];
	sp[1] += k0[1] + k1[1];
	sp[2] += k0[2] + k1[2];
	sp[3] += k0[3] + k1[3];
	matrix_layer(sp);
	sp[0] += k0[0] + k1[2];
	sp[1] += k0[1] + k1[3];
	sp[2] += k0[2] + k1[0];
	sp[3] += k0[3] + k1[1];
	matrix_layer(sp);

	for (uint32_t r = 0; r < (uint32_t)TBC128256_ROUNDS; r++) {
		uint32_t const *round_tk = &tk[r * 4u];

		sp[0] ^= round_tk[0];
		sp[1] ^= round_tk[1];
		sp[2] ^= round_tk[2];
		sp[3] ^= round_tk[3];
		sbox_layer(sp);
		if (r != (uint32_t)(TBC128256_ROUNDS - 1)) {
			matrix_layer(sp);
		}
	}

	sp[0] ^= tk[TBC128256_ROUNDS * 4u + 0u];
	sp[1] ^= tk[TBC128256_ROUNDS * 4u + 1u];
	sp[2] ^= tk[TBC128256_ROUNDS * 4u + 2u];
	sp[3] ^= tk[TBC128256_ROUNDS * 4u + 3u];
	matrix_layer(sp);
	sp[0] += k0[1] + k1[0];
	sp[1] += k0[2] + k1[1];
	sp[2] += k0[3] + k1[2];
	sp[3] += k0[0] + k1[3];
	matrix_layer(sp);
	sp[0] += k0[1] + k1[2];
	sp[1] += k0[2] + k1[3];
	sp[2] += k0[3] + k1[0];
	sp[3] += k0[0] + k1[1];

	store_state(ct, sp);
}

void tbc128256_decrypt_precomputed_tk(uint8_t pt[TBC128256_BLOCK_BYTES],
									  uint8_t const ct[TBC128256_BLOCK_BYTES],
									  uint8_t const key[TBC128256_KEY_BYTES],
									  uint32_t const tk[TBC128256_TK_WORDS])
{
	uint32_t sp[4];
	uint32_t k0[4];
	uint32_t k1[4];

	load_state(sp, ct);
	load_state(k0, key);
	load_state(k1, key + 16);

	sp[0] -= k0[1] + k1[2];
	sp[1] -= k0[2] + k1[3];
	sp[2] -= k0[3] + k1[0];
	sp[3] -= k0[0] + k1[1];
	matrix_layer_inv(sp);
	sp[0] -= k0[1] + k1[0];
	sp[1] -= k0[2] + k1[1];
	sp[2] -= k0[3] + k1[2];
	sp[3] -= k0[0] + k1[3];
	matrix_layer_inv(sp);
	sp[0] ^= tk[TBC128256_ROUNDS * 4u + 0u];
	sp[1] ^= tk[TBC128256_ROUNDS * 4u + 1u];
	sp[2] ^= tk[TBC128256_ROUNDS * 4u + 2u];
	sp[3] ^= tk[TBC128256_ROUNDS * 4u + 3u];

	for (int32_t r = TBC128256_ROUNDS - 1; r >= 0; r--) {
		uint32_t const *round_tk = &tk[(uint32_t)r * 4u];

		if (r != TBC128256_ROUNDS - 1) {
			matrix_layer_inv(sp);
		}
		TBC128256_C_SBOX_INV_WORDS(sp[0], sp[1], sp[2], sp[3]);
		sp[0] ^= round_tk[0];
		sp[1] ^= round_tk[1];
		sp[2] ^= round_tk[2];
		sp[3] ^= round_tk[3];
	}

	matrix_layer_inv(sp);
	sp[0] -= k0[0] + k1[2];
	sp[1] -= k0[1] + k1[3];
	sp[2] -= k0[2] + k1[0];
	sp[3] -= k0[3] + k1[1];
	matrix_layer_inv(sp);
	sp[0] -= k0[0] + k1[0];
	sp[1] -= k0[1] + k1[1];
	sp[2] -= k0[2] + k1[2];
	sp[3] -= k0[3] + k1[3];

	store_state(pt, sp);
}
