#!/usr/bin/env python3
"""Slice the TX RTL handoff into N-packet RX stimulus files.

Unlike 03, no interleaving is needed: the TX team already ships
tx_rtl_records_1280.bin in the exact 1472-byte record layout the RX AXI-Stream
consumes (AAD beat, 90 ciphertext beats, TAG beat).  This script only takes a
prefix of it, plus the matching prefix of the expected plaintext.

File byte 0 goes to TDATA[7:0]; no byte swapping happens here.

Outputs (into tx_rx_loopback/data/):
    tx_records_<N>pkt.bin  N x 1472 B  -> s_axis stimulus (TX RTL output)
    tx_plain_<N>pkt.bin    N x 1440 B  -> expected m_axis payload

Usage:  pack_tx_vectors.py [packet_count]        (default 1280 = full frame)
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
TX = ROOT.parent / "tx_uvm" / "vectors"
DATA = ROOT / "data"

PAYLOAD_BYTES = 1440
RECORD_BYTES = 1472
TOTAL_PACKETS = 1280

count = int(sys.argv[1]) if len(sys.argv) > 1 else TOTAL_PACKETS
if not 1 <= count <= TOTAL_PACKETS:
    raise SystemExit(f"packet_count must be 1..{TOTAL_PACKETS}")

records = (TX / "tx_rtl_records_1280.bin").read_bytes()
plain = (TX / "plaintext_1280.bin").read_bytes()

if len(records) != TOTAL_PACKETS * RECORD_BYTES:
    raise SystemExit(f"unexpected record file size {len(records)}")
if len(plain) != TOTAL_PACKETS * PAYLOAD_BYTES:
    raise SystemExit(f"unexpected plaintext file size {len(plain)}")

stim_bytes = records[:count * RECORD_BYTES]
gold_bytes = plain[:count * PAYLOAD_BYTES]

DATA.mkdir(parents=True, exist_ok=True)
stim = DATA / f"tx_records_{count}pkt.bin"
gold = DATA / f"tx_plain_{count}pkt.bin"
stim.write_bytes(stim_bytes)
gold.write_bytes(gold_bytes)

print(f"wrote {stim}  ({len(stim_bytes)} B = {count} x {RECORD_BYTES})")
print(f"wrote {gold}  ({len(gold_bytes)} B = {count} x {PAYLOAD_BYTES})")
