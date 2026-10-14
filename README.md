# Rotom implementations

Reference C and Cortex-M3/M4 assembly implementations of the Rotom tweakable
block cipher variants used in the paper.

## Contents

- `Rotom/Reference-C/`: C implementations and tests.
- `Rotom/Cortex-M3/`, `Rotom/Cortex-M4/`: full-unroll and non-unroll ASM implementations.
- `Rotom/Rotom_TestVector.txt`: round tweakey, encryption, and decryption test vectors.

Each implementation directory contains `Rotom-128/` and `Rotom-256/`, with
headers in `Inc/` and sources in `Src/`.

## Variants

| Variant | Compile-time definition |
| --- | --- |
| Rotom-128* | `-DTBC128_ROUNDS=5` |
| Rotom-128 | `-DTBC128_ROUNDS=6` (default) |
| Rotom-256* | `-DTBC128256_ROUNDS=6` |
| Rotom-256 | `-DTBC128256_ROUNDS=7` (default) |

Use the same round-count definition for the implementation and calling code.

## API

Include the corresponding `Inc/define.h`. Reference-C provides these functions;
the Cortex-M implementations use the same names with an `_asm` suffix.

| Operation | Rotom-128 | Rotom-256 |
| --- | --- | --- |
| Tweakey schedule | `tbc128_tweakey_sche` | `tbc128256_tweakey_sche` |
| Encryption | `tbc128_encrypt_precomputed_tk` | `tbc128256_encrypt_precomputed_tk` |
| Decryption | `tbc128_decrypt_precomputed_tk` | `tbc128256_decrypt_precomputed_tk` |

Compute the round tweakeys first, then pass the resulting buffer to encryption
or decryption.

## Cortex-M ASM

For the target core and key size, select either `*_asm_full_unroll.S` or
`*_asm_non_unroll.S`. Both export the same function names, so include only one
in a build. 

Call the `*_asm` functions directly from C. All input and output buffers must
be 4-byte aligned.

## Test-vector checks

Run these commands from the repository root. The tests check the round tweakeys,
encryption, and decryption against the test vectors.

Rotom-128:

```sh
cc -std=c11 \
  -IRotom/Reference-C/Rotom-128/Inc \
  Rotom/Reference-C/Rotom-128/Src/tbc128.c \
  Rotom/Reference-C/Rotom-128/Test/test_tbc128.c \
  -o test_tbc128
./test_tbc128
```

Rotom-256:

```sh
cc -std=c11 \
  -IRotom/Reference-C/Rotom-256/Inc \
  Rotom/Reference-C/Rotom-256/Src/tbc128256.c \
  Rotom/Reference-C/Rotom-256/Test/test_tbc128256.c \
  -o test_tbc128256
./test_tbc128256
```

For the starred variants, add the corresponding compile-time definition from
the table above. Each test prints `<variant> test vectors OK` on success.
