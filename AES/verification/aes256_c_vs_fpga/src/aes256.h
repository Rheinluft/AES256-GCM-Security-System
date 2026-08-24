#ifndef AES256_H
#define AES256_H

#include <stdint.h>

void aes256_expand_key(const uint8_t key[32], uint8_t round_keys[240]);
void aes256_encrypt_block(const uint8_t plaintext[16], uint8_t ciphertext[16],
                          const uint8_t round_keys[240]);

#endif
