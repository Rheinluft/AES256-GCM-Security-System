#!/usr/bin/env python3
"""Independently validate the RX golden vector handoff.

Three checks must pass before the vectors are trusted as UVM stimulus:
  1. SHA-256 of every file matches tx_rtl_manifest.txt.
  2. Re-encrypting plaintext with an independent AES-GCM implementation
     (python cryptography) reproduces ciphertext and TAG
     byte for byte, using the nonce/AAD rules the RTL actually implements.
  3. The RX UVM 8/16/1280-packet files are exact interleaved prefixes.

Check 2 is the important one: it proves the protocol interpretation in
gcm_protocol_pkg.sv (magic, flags, big-endian AAD layout, nonce derivation)
agrees with what the vectors were built from.
"""
from hashlib import sha256
from pathlib import Path
from struct import pack
import sys

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOT = Path(__file__).resolve().parents[2]
HANDOFF = ROOT / "tx_uvm" / "vectors"
RX_DATA = ROOT / "rx_uvm" / "data"

# Mirrors gcm_protocol_pkg.sv
MAGIC = 0x5043414D          # "PCAM"
VERSION = 1                 # flags[15:12]
PACKET_COUNT = 1280         # LAST_PACKET_INDEX = 1279
PAYLOAD_BYTES = 1440        # 90 x 128-bit beats
SESSION_ID = 0x00000001
FRAME_ID = 0x00000000

failures = []


def check(label, ok, detail=""):
    print(f"[{'PASS' if ok else 'FAIL'}] {label}" + (f"  {detail}" if detail else ""))
    if not ok:
        failures.append(label)


# --- 1. manifest SHA-256 ----------------------------------------------------
print("=== 1. manifest SHA-256 ===")
for line in (HANDOFF / "tx_rtl_manifest.txt").read_text().splitlines()[1:]:
    name, size, digest = line.split("\t")
    blob = (HANDOFF / name).read_bytes()
    check(f"{name:<20}", len(blob) == int(size) and sha256(blob).hexdigest() == digest,
          f"{len(blob)} B")

# --- 2. independent AES-GCM re-encryption -----------------------------------
print("\n=== 2. re-encrypt with python cryptography (independent of OpenSSL CLI) ===")
key = (HANDOFF / "key.bin").read_bytes()
aad_all = (HANDOFF / "tx_rtl_aad_1280.bin").read_bytes()
iv_all = (HANDOFF / "iv_1280.bin").read_bytes()
pt_all = (HANDOFF / "plaintext_1280.bin").read_bytes()
ct_all = (HANDOFF / "tx_rtl_ciphertext_1280.bin").read_bytes()
tag_all = (HANDOFF / "tx_rtl_tag_1280.bin").read_bytes()

check("key.bin == 00..1f", key == bytes(range(32)), key.hex())

aesgcm = AESGCM(key)
bad_aad = bad_iv = bad_pt = bad_ct = bad_tag = 0

for i in range(PACKET_COUNT):
    # flags per gcm_protocol_pkg::make_flags = {ver,9'b0,eof,sof,encrypted}
    flags = (VERSION << 12) | 0x1
    if i == 0:
        flags |= 1 << 1
    if i == PACKET_COUNT - 1:
        flags |= 1 << 2
    exp_aad = pack(">IIIHH", MAGIC, SESSION_ID, FRAME_ID, i, flags)
    # nonce per gcm_protocol_pkg::make_nonce
    exp_iv = pack(">IIHH", SESSION_ID, FRAME_ID, 0, i)
    # plaintext[j] = (i + j) & 0xff
    exp_pt = bytes((i + j) & 0xFF for j in range(PAYLOAD_BYTES))

    if aad_all[i * 16:(i + 1) * 16] != exp_aad:
        bad_aad += 1
    if iv_all[i * 12:(i + 1) * 12] != exp_iv:
        bad_iv += 1
    if pt_all[i * PAYLOAD_BYTES:(i + 1) * PAYLOAD_BYTES] != exp_pt:
        bad_pt += 1

    ct_tag = aesgcm.encrypt(exp_iv, exp_pt, exp_aad)
    if ct_tag[:PAYLOAD_BYTES] != ct_all[i * PAYLOAD_BYTES:(i + 1) * PAYLOAD_BYTES]:
        bad_ct += 1
    if ct_tag[PAYLOAD_BYTES:] != tag_all[i * 16:(i + 1) * 16]:
        bad_tag += 1

check("AAD  matches gcm_protocol_pkg::make_aad rule",   bad_aad == 0, f"{bad_aad} mismatched")
check("IV   matches gcm_protocol_pkg::make_nonce rule", bad_iv == 0,  f"{bad_iv} mismatched")
check("plaintext matches (i+j)&0xff rule",              bad_pt == 0,  f"{bad_pt} mismatched")
check("ciphertext reproduced independently",            bad_ct == 0,  f"{bad_ct} mismatched")
check("TAG        reproduced independently",            bad_tag == 0, f"{bad_tag} mismatched")

# --- 3. packaged RX stimulus ------------------------------------------------
print("\n=== 3. RX UVM packaged prefix consistency ===")
record_all = (HANDOFF / "tx_rtl_records_1280.bin").read_bytes()
for count in (8, 16, 1280):
    records = (RX_DATA / f"rx_normal_{count}pkt.bin").read_bytes()
    plain = (RX_DATA / f"rx_plain_{count}pkt.bin").read_bytes()
    check(f"rx_normal_{count}pkt.bin",
          records == record_all[:count * (16 + PAYLOAD_BYTES + 16)])
    check(f"rx_plain_{count}pkt.bin",
          plain == pt_all[:count * PAYLOAD_BYTES])

print(f"\n{'ALL VECTOR CHECKS PASSED' if not failures else 'FAILURES: ' + str(failures)}")
sys.exit(1 if failures else 0)
