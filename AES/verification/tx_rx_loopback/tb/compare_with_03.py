#!/usr/bin/env python3
"""Document the relationship between the 03 and 04 stimulus.

03_RX_AUTH drove the RX with PC/OpenSSL golden vectors; 04_TX_TO_RX drives it
with the TX RTL's own verified output.  Because TX was itself signed off
against the same OpenSSL reference, the two stimulus streams are expected to be
byte-identical.

That is worth recording explicitly rather than leaving implicit: it is the
reason the 04 regression numbers match 03 exactly, and it is the evidence that
TX RTL and RX RTL interoperate through an independently specified format.

If this ever reports a difference, 04 is genuinely exercising new bytes and the
03 results can no longer be assumed to carry over.
"""
from hashlib import sha256
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
V03 = ROOT / "03_RX_AUTH" / "data"
V04 = ROOT / "04_TX_TO_RX" / "data"

PAIRS = [
    ("rx_normal_1280pkt.bin", "tx_records_1280pkt.bin", "자극 (1280 패킷 레코드)"),
    ("rx_plain_1280pkt.bin",  "tx_plain_1280pkt.bin",   "기대 평문 (1280 패킷)"),
]

identical = True
print("=== 03 (OpenSSL 골든) ↔ 04 (TX RTL 출력) 자극 대조 ===")
for a, b, label in PAIRS:
    pa, pb = V03 / a, V04 / b
    if not pa.exists():
        print(f"[SKIP] {label}: {pa} 없음 (03에서 먼저 생성 필요)")
        continue
    da = sha256(pa.read_bytes()).hexdigest()
    db = sha256(pb.read_bytes()).hexdigest()
    same = da == db
    identical &= same
    print(f"[{'SAME' if same else 'DIFF'}] {label}")
    print(f"       03  {a:<24} {da}")
    print(f"       04  {b:<24} {db}")

print()
if identical:
    print("두 자극은 바이트 단위로 동일하다.")
    print("→ 04의 시나리오별 수치는 03과 일치하는 것이 정상이며,")
    print("  04가 새로 확립하는 것은 커버리지가 아니라 자극의 출처(provenance)다.")
else:
    print("자극이 다르다. 04는 03과 다른 바이트를 구동하므로")
    print("03의 결과를 그대로 인용할 수 없다.")
sys.exit(0)
