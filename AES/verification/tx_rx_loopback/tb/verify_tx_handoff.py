#!/usr/bin/env python3
"""Validate the TX RTL handoff before it is used as RX stimulus.

Five checks, all must pass:
  1. every file matches tx_rtl_manifest.txt (size + SHA-256)
  2. tx_rtl_records_1280.bin really is aad|ciphertext|tag interleaved per packet
  3. AAD / nonce / plaintext follow the rules gcm_protocol_pkg.sv implements
  4. the 8/16/1280-packet loopback inputs are exact prefixes of the TX handoff
  5. TX ciphertext+TAG authenticates and decrypts to plaintext_1280.bin under
     an independent AES-GCM implementation (python cryptography)

Check 5 is the strong one: it proves the TX output is cryptographically valid
on its own terms, not merely equal to a file we already had.
"""
from hashlib import sha256
from pathlib import Path
from struct import pack
import sys

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOT = Path(__file__).resolve().parents[2]
TX = ROOT / "tx_uvm" / "vectors"
LOOPBACK = ROOT / "tx_rx_loopback" / "data"

# Mirrors gcm_protocol_pkg.sv
MAGIC = 0x5043414D          # "PCAM"
VERSION = 1
PACKET_COUNT = 1280
PAYLOAD_BYTES = 1440
AAD_BYTES = 16
TAG_BYTES = 16
RECORD_BYTES = AAD_BYTES + PAYLOAD_BYTES + TAG_BYTES  # 1472
SESSION_ID = 0x00000001
FRAME_ID = 0x00000000

failures = []


def check(label, ok, detail=""):
    print(f"[{'PASS' if ok else 'FAIL'}] {label}" + (f"  {detail}" if detail else ""))
    if not ok:
        failures.append(label)


# --- 1. manifest ------------------------------------------------------------
print("=== 1. tx_rtl_manifest.txt ===")
for line in (TX / "tx_rtl_manifest.txt").read_text().splitlines()[1:]:
    name, size, digest = line.split("\t")
    blob = (TX / name).read_bytes()
    check(f"{name:<28}",
          len(blob) == int(size) and sha256(blob).hexdigest() == digest,
          f"{len(blob)} B")

# --- load -------------------------------------------------------------------
key = (TX / "key.bin").read_bytes()
aad_all = (TX / "tx_rtl_aad_1280.bin").read_bytes()
ct_all = (TX / "tx_rtl_ciphertext_1280.bin").read_bytes()
tag_all = (TX / "tx_rtl_tag_1280.bin").read_bytes()
rec_all = (TX / "tx_rtl_records_1280.bin").read_bytes()
iv_all = (TX / "iv_1280.bin").read_bytes()
pt_all = (TX / "plaintext_1280.bin").read_bytes()

# --- 2. record interleaving -------------------------------------------------
print("\n=== 2. tx_rtl_records_1280.bin 통합 레코드 정합성 ===")
check("record file size", len(rec_all) == PACKET_COUNT * RECORD_BYTES,
      f"{len(rec_all)} B")

bad_rec = 0
for i in range(PACKET_COUNT):
    base = i * RECORD_BYTES
    if rec_all[base:base + AAD_BYTES] != aad_all[i*AAD_BYTES:(i+1)*AAD_BYTES]:
        bad_rec += 1
    elif rec_all[base+AAD_BYTES:base+AAD_BYTES+PAYLOAD_BYTES] != \
            ct_all[i*PAYLOAD_BYTES:(i+1)*PAYLOAD_BYTES]:
        bad_rec += 1
    elif rec_all[base+AAD_BYTES+PAYLOAD_BYTES:base+RECORD_BYTES] != \
            tag_all[i*TAG_BYTES:(i+1)*TAG_BYTES]:
        bad_rec += 1
check("records == aad | ciphertext | tag", bad_rec == 0, f"{bad_rec} mismatched")

# --- 3. protocol rules ------------------------------------------------------
print("\n=== 3. gcm_protocol_pkg.sv 규칙 일치 ===")
check("key.bin == 00..1f", key == bytes(range(32)), key.hex())

bad_aad = bad_iv = bad_pt = 0
for i in range(PACKET_COUNT):
    flags = (VERSION << 12) | 0x1
    if i == 0:
        flags |= 1 << 1                     # SOF
    if i == PACKET_COUNT - 1:
        flags |= 1 << 2                     # EOF
    if aad_all[i*AAD_BYTES:(i+1)*AAD_BYTES] != \
            pack(">IIIHH", MAGIC, SESSION_ID, FRAME_ID, i, flags):
        bad_aad += 1
    if iv_all[i*12:(i+1)*12] != pack(">IIHH", SESSION_ID, FRAME_ID, 0, i):
        bad_iv += 1
    if pt_all[i*PAYLOAD_BYTES:(i+1)*PAYLOAD_BYTES] != \
            bytes((i + j) & 0xFF for j in range(PAYLOAD_BYTES)):
        bad_pt += 1

check("AAD  == make_aad(magic, session, frame, index, flags)", bad_aad == 0,
      f"{bad_aad} mismatched")
check("IV   == make_nonce(session, frame, index)", bad_iv == 0,
      f"{bad_iv} mismatched")
check("plaintext == (i+j)&0xff", bad_pt == 0, f"{bad_pt} mismatched")

# --- 4. packaged loopback prefixes -----------------------------------------
print("\n=== 4. TX handoff ↔ loopback 입력 prefix 정합성 ===")
for count in (8, 16, 1280):
    record_expected = rec_all[:count * RECORD_BYTES]
    plain_expected = pt_all[:count * PAYLOAD_BYTES]
    record_path = LOOPBACK / f"tx_records_{count}pkt.bin"
    plain_path = LOOPBACK / f"tx_plain_{count}pkt.bin"
    check(f"tx_records_{count}pkt.bin", record_path.read_bytes() == record_expected)
    check(f"tx_plain_{count}pkt.bin", plain_path.read_bytes() == plain_expected)

# --- 5. independent decryption + authentication -----------------------------
print("\n=== 5. 독립 구현 복호 인증 (python cryptography) ===")
aesgcm = AESGCM(key)
auth_fail = 0
plain_mismatch = 0
for i in range(PACKET_COUNT):
    nonce = iv_all[i*12:(i+1)*12]
    aad = aad_all[i*AAD_BYTES:(i+1)*AAD_BYTES]
    ct = ct_all[i*PAYLOAD_BYTES:(i+1)*PAYLOAD_BYTES]
    tag = tag_all[i*TAG_BYTES:(i+1)*TAG_BYTES]
    try:
        got = aesgcm.decrypt(nonce, ct + tag, aad)
    except InvalidTag:
        auth_fail += 1
        continue
    if got != pt_all[i*PAYLOAD_BYTES:(i+1)*PAYLOAD_BYTES]:
        plain_mismatch += 1

check("TAG 인증 성공", auth_fail == 0, f"{auth_fail} / {PACKET_COUNT} 실패")
check("복호 평문 == plaintext_1280.bin", plain_mismatch == 0,
      f"{plain_mismatch} mismatched")

print(f"\n{'ALL TX HANDOFF CHECKS PASSED' if not failures else 'FAILURES: ' + str(failures)}")
sys.exit(1 if failures else 0)
