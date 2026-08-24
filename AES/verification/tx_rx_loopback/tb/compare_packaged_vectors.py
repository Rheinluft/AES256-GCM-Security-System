#!/usr/bin/env python3
"""Check the relationship between the TX handoff and packaged loopback stimulus.

The loopback data must be an exact prefix/copy of the verified TX RTL handoff.
This guards against accidental byte-order changes while packaging 8, 16, or
1280 packet RX stimuli.
"""
from hashlib import sha256
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
TX = ROOT / "tx_uvm" / "vectors"
LOOPBACK = ROOT / "tx_rx_loopback" / "data"

PAIRS = [
    ("tx_rtl_records_1280.bin", "tx_records_1280pkt.bin", "자극 (1280 패킷 레코드)"),
    ("plaintext_1280.bin",      "tx_plain_1280pkt.bin",   "기대 평문 (1280 패킷)"),
]

identical = True
print("=== TX RTL handoff ↔ loopback packaged data 대조 ===")
for a, b, label in PAIRS:
    pa, pb = TX / a, LOOPBACK / b
    da = sha256(pa.read_bytes()).hexdigest()
    db = sha256(pb.read_bytes()).hexdigest()
    same = da == db
    identical &= same
    print(f"[{'SAME' if same else 'DIFF'}] {label}")
    print(f"       TX       {a:<28} {da}")
    print(f"       loopback {b:<28} {db}")

print()
if identical:
    print("두 자극은 바이트 단위로 동일하다.")
    print("→ loopback regression은 보존된 TX RTL 출력을 그대로 구동한다.")
else:
    print("자극이 다르다. loopback data를 다시 생성해야 한다.")
sys.exit(0 if identical else 1)
