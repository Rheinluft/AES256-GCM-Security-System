#define _POSIX_C_SOURCE 200809L

#include "aes256.h"

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sched.h>
#include <time.h>
#include <unistd.h>
#endif

#define RECORD_COUNT 10000u
#define TRIAL_COUNT 11u

typedef uint8_t aes_key[32];
typedef uint8_t aes_block[16];

static int hex_value(int character)
{
    if (character >= '0' && character <= '9')
        return character - '0';
    if (character >= 'a' && character <= 'f')
        return character - 'a' + 10;
    if (character >= 'A' && character <= 'F')
        return character - 'A' + 10;
    return -1;
}

static int load_hex_file(const char *directory, const char *name, uint8_t *output,
                         size_t record_size)
{
    char path[1024];
    char line[256];
    FILE *file;
    size_t record;

    if (snprintf(path, sizeof path, "%s/%s", directory, name) >= (int)sizeof path)
        return 0;
    file = fopen(path, "r");
    if (file == NULL) {
        perror(path);
        return 0;
    }

    for (record = 0; record < RECORD_COUNT; ++record) {
        size_t i;
        size_t length;

        if (fgets(line, sizeof line, file) == NULL) {
            fprintf(stderr, "%s ended at record %zu\n", path, record);
            fclose(file);
            return 0;
        }
        line[strcspn(line, "\r\n")] = '\0';
        length = strlen(line);
        if (length != record_size * 2) {
            fprintf(stderr, "%s malformed record %zu\n", path, record);
            fclose(file);
            return 0;
        }
        for (i = 0; i < record_size; ++i) {
            int high = hex_value((unsigned char)line[i * 2]);
            int low = hex_value((unsigned char)line[i * 2 + 1]);
            if (high < 0 || low < 0) {
                fprintf(stderr, "%s non-hex record %zu\n", path, record);
                fclose(file);
                return 0;
            }
            output[record * record_size + i] = (uint8_t)((high << 4) | low);
        }
    }
    if (fgets(line, sizeof line, file) != NULL) {
        fprintf(stderr, "%s contains more than %u records\n", path, RECORD_COUNT);
        fclose(file);
        return 0;
    }
    return fclose(file) == 0;
}

static double now_seconds(void)
{
#ifdef _WIN32
    static LARGE_INTEGER frequency;
    LARGE_INTEGER counter;

    if (frequency.QuadPart == 0 && !QueryPerformanceFrequency(&frequency)) {
        fputs("QueryPerformanceFrequency failed\n", stderr);
        exit(EXIT_FAILURE);
    }
    if (!QueryPerformanceCounter(&counter)) {
        fputs("QueryPerformanceCounter failed\n", stderr);
        exit(EXIT_FAILURE);
    }
    return (double)counter.QuadPart / (double)frequency.QuadPart;
#else
    struct timespec timestamp;

    if (clock_gettime(CLOCK_MONOTONIC_RAW, &timestamp) != 0) {
        perror("clock_gettime");
        exit(EXIT_FAILURE);
    }
    return (double)timestamp.tv_sec + (double)timestamp.tv_nsec / 1e9;
#endif
}

static int pin_to_cpu(unsigned cpu)
{
#ifdef _WIN32
    DWORD_PTR mask;

    if (cpu >= sizeof(DWORD_PTR) * 8u)
        return 0;
    mask = (DWORD_PTR)1u << cpu;
    return SetThreadAffinityMask(GetCurrentThread(), mask) != 0;
#else
    cpu_set_t set;

    CPU_ZERO(&set);
    CPU_SET(cpu, &set);
    return sched_setaffinity(0, sizeof set, &set) == 0;
#endif
}

static void encrypt_key_included(aes_key *keys, aes_block *plaintexts,
                                 aes_block *outputs)
{
    uint8_t round_keys[240];
    size_t i;

    for (i = 0; i < RECORD_COUNT; ++i) {
        aes256_expand_key(keys[i], round_keys);
        aes256_encrypt_block(plaintexts[i], outputs[i], round_keys);
    }
}

static void encrypt_key_excluded(const uint8_t round_keys[240],
                                 aes_block *plaintexts, aes_block *outputs)
{
    size_t i;

    for (i = 0; i < RECORD_COUNT; ++i)
        aes256_encrypt_block(plaintexts[i], outputs[i], round_keys);
}

static size_t count_matches(aes_block *actual, aes_block *expected)
{
    size_t matches = 0;
    size_t i;

    for (i = 0; i < RECORD_COUNT; ++i) {
        if (memcmp(actual[i], expected[i], sizeof actual[i]) == 0)
            ++matches;
    }
    return matches;
}

static uint64_t checksum_blocks(aes_block *blocks)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    size_t i;
    size_t j;

    for (i = 0; i < RECORD_COUNT; ++i) {
        for (j = 0; j < sizeof blocks[i]; ++j) {
            hash ^= blocks[i][j];
            hash *= UINT64_C(1099511628211);
        }
    }
    return hash;
}

static int compare_double(const void *left, const void *right)
{
    double a = *(const double *)left;
    double b = *(const double *)right;

    return (a > b) - (a < b);
}

static double median(double samples[TRIAL_COUNT])
{
    double sorted[TRIAL_COUNT];

    memcpy(sorted, samples, sizeof sorted);
    qsort(sorted, TRIAL_COUNT, sizeof sorted[0], compare_double);
    return sorted[TRIAL_COUNT / 2u];
}

static void print_result(const char *label, double seconds, size_t matches,
                         uint64_t checksum)
{
    double blocks_per_second = (double)RECORD_COUNT / seconds;
    double ns_per_block = seconds * 1e9 / (double)RECORD_COUNT;
    double gbps = (double)RECORD_COUNT * 128.0 / seconds / 1e9;

    printf("%s blocks=%u seconds=%.9f ns_per_block=%.3f "
           "blocks_per_second=%.3f gbps=%.6f matches=%zu trials=%u "
           "checksum=%016llx\n",
           label, RECORD_COUNT, seconds, ns_per_block, blocks_per_second, gbps,
           matches, TRIAL_COUNT, (unsigned long long)checksum);
}

int main(int argc, char **argv)
{
    aes_key *keys = NULL;
    aes_block *plaintexts = NULL;
    aes_block *golden = NULL;
    aes_block *golden_fixed = NULL;
    aes_block *outputs = NULL;
    uint8_t fixed_round_keys[240];
    double included_samples[TRIAL_COUNT];
    double excluded_samples[TRIAL_COUNT];
    size_t included_matches;
    size_t excluded_matches;
    uint64_t included_checksum;
    uint64_t excluded_checksum;
    unsigned cpu = 0;
    unsigned trial;
    int status = EXIT_FAILURE;

    if (argc < 2 || argc > 3) {
        fprintf(stderr, "Usage: %s VECTOR_DIRECTORY [CPU]\n", argv[0]);
        return EXIT_FAILURE;
    }
    if (argc == 3) {
        char *end = NULL;
        unsigned long parsed;

        errno = 0;
        parsed = strtoul(argv[2], &end, 10);
        if (errno != 0 || end == argv[2] || *end != '\0' || parsed > 63u) {
            fprintf(stderr, "Invalid CPU number: %s\n", argv[2]);
            return EXIT_FAILURE;
        }
        cpu = (unsigned)parsed;
    }
    if (!pin_to_cpu(cpu)) {
        fprintf(stderr, "Failed to pin benchmark to CPU %u\n", cpu);
        return EXIT_FAILURE;
    }

    keys = malloc(sizeof *keys * RECORD_COUNT);
    plaintexts = malloc(sizeof *plaintexts * RECORD_COUNT);
    golden = malloc(sizeof *golden * RECORD_COUNT);
    golden_fixed = malloc(sizeof *golden_fixed * RECORD_COUNT);
    outputs = malloc(sizeof *outputs * RECORD_COUNT);
    if (keys == NULL || plaintexts == NULL || golden == NULL ||
        golden_fixed == NULL || outputs == NULL) {
        fputs("Memory allocation failed\n", stderr);
        goto out;
    }
    if (!load_hex_file(argv[1], "keys.hex", &keys[0][0], sizeof keys[0]) ||
        !load_hex_file(argv[1], "plaintexts.hex", &plaintexts[0][0],
                       sizeof plaintexts[0]) ||
        !load_hex_file(argv[1], "golden.hex", &golden[0][0], sizeof golden[0]) ||
        !load_hex_file(argv[1], "golden_fixed_key.hex", &golden_fixed[0][0],
                       sizeof golden_fixed[0]))
        goto out;

    encrypt_key_included(keys, plaintexts, outputs);
    included_matches = count_matches(outputs, golden);
    aes256_expand_key(keys[0], fixed_round_keys);
    encrypt_key_excluded(fixed_round_keys, plaintexts, outputs);
    excluded_matches = count_matches(outputs, golden_fixed);
    if (included_matches != RECORD_COUNT || excluded_matches != RECORD_COUNT) {
        fprintf(stderr, "Pre-benchmark correctness failed: included=%zu excluded=%zu\n",
                included_matches, excluded_matches);
        goto out;
    }

    for (trial = 0; trial < TRIAL_COUNT; ++trial) {
        double start = now_seconds();
        encrypt_key_included(keys, plaintexts, outputs);
        included_samples[trial] = now_seconds() - start;
        if (count_matches(outputs, golden) != RECORD_COUNT) {
            fprintf(stderr, "Included correctness failed at trial %u\n", trial + 1u);
            goto out;
        }

        aes256_expand_key(keys[0], fixed_round_keys);
        start = now_seconds();
        encrypt_key_excluded(fixed_round_keys, plaintexts, outputs);
        excluded_samples[trial] = now_seconds() - start;
        if (count_matches(outputs, golden_fixed) != RECORD_COUNT) {
            fprintf(stderr, "Excluded correctness failed at trial %u\n", trial + 1u);
            goto out;
        }
    }

    encrypt_key_included(keys, plaintexts, outputs);
    included_checksum = checksum_blocks(outputs);
    encrypt_key_excluded(fixed_round_keys, plaintexts, outputs);
    excluded_checksum = checksum_blocks(outputs);

    printf("C_CPU_AFFINITY cpu=%u\n", cpu);
    print_result("C_KEY_INCLUDED", median(included_samples), included_matches,
                 included_checksum);
    print_result("C_KEY_EXCLUDED", median(excluded_samples), excluded_matches,
                 excluded_checksum);
    status = EXIT_SUCCESS;

out:
    free(keys);
    free(plaintexts);
    free(golden);
    free(golden_fixed);
    free(outputs);
    return status;
}
