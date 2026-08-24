#include <openssl/evp.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define RECORD_COUNT 10000u

static int aes256_ecb_encrypt(const uint8_t key[32], const uint8_t plaintext[16],
                              uint8_t ciphertext[16])
{
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    int update_len = 0;
    int final_len = 0;
    int ok = 0;

    if (ctx == NULL)
        return 0;
    if (EVP_EncryptInit_ex(ctx, EVP_aes_256_ecb(), NULL, key, NULL) != 1)
        goto out;
    if (EVP_CIPHER_CTX_set_padding(ctx, 0) != 1)
        goto out;
    if (EVP_EncryptUpdate(ctx, ciphertext, &update_len, plaintext, 16) != 1)
        goto out;
    if (EVP_EncryptFinal_ex(ctx, ciphertext + update_len, &final_len) != 1)
        goto out;
    ok = update_len + final_len == 16;

out:
    EVP_CIPHER_CTX_free(ctx);
    return ok;
}

static int open_output(FILE **file, const char *directory, const char *name)
{
    char path[1024];

    if (snprintf(path, sizeof path, "%s/%s", directory, name) >= (int)sizeof path)
        return 0;
    *file = fopen(path, "w");
    if (*file == NULL)
        perror(path);
    return *file != NULL;
}

static int write_hex_line(FILE *file, const uint8_t *bytes, size_t length)
{
    size_t i;

    for (i = 0; i < length; ++i) {
        if (fprintf(file, "%02x", bytes[i]) < 0)
            return 0;
    }
    return fputc('\n', file) != EOF;
}

static void make_record(uint32_t index, uint8_t key[32], uint8_t plaintext[16])
{
    uint32_t j;

    for (j = 0; j < 32; ++j)
        key[j] = (uint8_t)((index * 17u + j * 29u + 0x31u) & 0xffu);
    for (j = 0; j < 16; ++j)
        plaintext[j] = (uint8_t)((index * 13u + j * 7u + 0x5au) & 0xffu);
}

int main(int argc, char **argv)
{
    static const uint8_t fips_key[32] = {
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
        0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f
    };
    static const uint8_t fips_plaintext[16] = {
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff
    };
    static const uint8_t fips_ciphertext[16] = {
        0x8e, 0xa2, 0xb7, 0xca, 0x51, 0x67, 0x45, 0xbf,
        0xea, 0xfc, 0x49, 0x90, 0x4b, 0x49, 0x60, 0x89
    };
    FILE *keys_file = NULL;
    FILE *plaintexts_file = NULL;
    FILE *golden_file = NULL;
    FILE *golden_fixed_file = NULL;
    uint8_t key[32];
    uint8_t fixed_key[32];
    uint8_t plaintext[16];
    uint8_t ciphertext[16];
    uint8_t fixed_ciphertext[16];
    uint32_t i;
    int status = EXIT_FAILURE;

    if (argc != 2) {
        fprintf(stderr, "Usage: %s OUTPUT_DIRECTORY\n", argv[0]);
        return EXIT_FAILURE;
    }

    if (!aes256_ecb_encrypt(fips_key, fips_plaintext, ciphertext) ||
        memcmp(ciphertext, fips_ciphertext, sizeof ciphertext) != 0) {
        fprintf(stderr, "OpenSSL FIPS AES-256 KAT: FAIL\n");
        return EXIT_FAILURE;
    }
    puts("OpenSSL FIPS AES-256 KAT: PASS");

    if (!open_output(&keys_file, argv[1], "keys.hex") ||
        !open_output(&plaintexts_file, argv[1], "plaintexts.hex") ||
        !open_output(&golden_file, argv[1], "golden.hex") ||
        !open_output(&golden_fixed_file, argv[1], "golden_fixed_key.hex"))
        goto out;

    make_record(0, fixed_key, plaintext);
    for (i = 0; i < RECORD_COUNT; ++i) {
        make_record(i, key, plaintext);
        if (!aes256_ecb_encrypt(key, plaintext, ciphertext) ||
            !aes256_ecb_encrypt(fixed_key, plaintext, fixed_ciphertext) ||
            !write_hex_line(keys_file, key, sizeof key) ||
            !write_hex_line(plaintexts_file, plaintext, sizeof plaintext) ||
            !write_hex_line(golden_file, ciphertext, sizeof ciphertext) ||
            !write_hex_line(golden_fixed_file, fixed_ciphertext,
                            sizeof fixed_ciphertext)) {
            fprintf(stderr, "Vector generation failed at record %u\n", i);
            goto out;
        }
    }

    printf("OpenSSL golden vectors: PASS (%u records)\n", RECORD_COUNT);
    status = EXIT_SUCCESS;

out:
    if (keys_file != NULL && fclose(keys_file) != 0)
        status = EXIT_FAILURE;
    if (plaintexts_file != NULL && fclose(plaintexts_file) != 0)
        status = EXIT_FAILURE;
    if (golden_file != NULL && fclose(golden_file) != 0)
        status = EXIT_FAILURE;
    if (golden_fixed_file != NULL && fclose(golden_fixed_file) != 0)
        status = EXIT_FAILURE;
    return status;
}
