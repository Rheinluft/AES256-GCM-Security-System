#!/usr/bin/env python3
"""Pack the OpenSSL golden handoff into DUT-ready RX stimulus files.

The handoff stores AAD / ciphertext / TAG in three separate streams.  The RX
AXI-Stream expects them interleaved per packet as one 1472-byte record:

    beat 0     : AAD        (16 B)
    beat 1..90 : ciphertext (1440 B)
    beat 91    : TAG        (16 B)

File byte 0 goes to TDATA[7:0], so the testbench packs bytes in order and no
byte swapping happens here.

Outputs (into 03_RX_AUTH/data/):
    rx_normal_<N>pkt.bin  N x 1472 B  -> s_axis stimulus
    rx_plain_<N>pkt.bin   N x 1440 B  -> expected m_axis payload

Usage:  pack_rx_vectors.py [packet_count]        (default 1280 = full frame)
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
HANDOFF = ROOT.parent / "00_1_benchmark" / "rx_core_golden_handoff_pcam_1280_20260813"
DATA = ROOT / "data"

AAD_BYTES = 16
PAYLOAD_BYTES = 1440
TAG_BYTES = 16
RECORD_BYTES = AAD_BYTES + PAYLOAD_BYTES + TAG_BYTES  # 1472
TOTAL_PACKETS = 1280

count = int(sys.argv[1]) if len(sys.argv) > 1 else TOTAL_PACKETS
if not 1 <= count <= TOTAL_PACKETS:
    raise SystemExit(f"packet_count must be 1..{TOTAL_PACKETS}")

aad = (HANDOFF / "aad_1280.bin").read_bytes()
ct = (HANDOFF / "ciphertext_1280.bin").read_bytes()
tag = (HANDOFF / "tag_1280.bin").read_bytes()
pt = (HANDOFF / "plaintext_1280.bin").read_bytes()

records = bytearray()
plain = bytearray()
for i in range(count):
    records += aad[i * AAD_BYTES:(i + 1) * AAD_BYTES]
    records += ct[i * PAYLOAD_BYTES:(i + 1) * PAYLOAD_BYTES]
    records += tag[i * TAG_BYTES:(i + 1) * TAG_BYTES]
    plain += pt[i * PAYLOAD_BYTES:(i + 1) * PAYLOAD_BYTES]

assert len(records) == count * RECORD_BYTES
assert len(plain) == count * PAYLOAD_BYTES

DATA.mkdir(parents=True, exist_ok=True)
stim = DATA / f"rx_normal_{count}pkt.bin"
gold = DATA / f"rx_plain_{count}pkt.bin"
stim.write_bytes(records)
gold.write_bytes(plain)

print(f"wrote {stim}  ({len(records)} B = {count} x {RECORD_BYTES})")
print(f"wrote {gold}  ({len(plain)} B = {count} x {PAYLOAD_BYTES})")
