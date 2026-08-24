AES-256-GCM verified TX RTL output for RX verification
Packet count       : 1280
AAD per packet     : 16 bytes
Ciphertext/packet  : 1440 bytes
TAG per packet     : 16 bytes
Record layout      : AAD[16] || Ciphertext[1440] || TAG[16]
Record size        : 1472 bytes
Byte ordering      : first stream byte first in file
Session ID         : 0x00000001
Initial frame ID   : 0x00000000
Packet index       : 0..1279
Nonce              : session_id || frame_id || 16'h0000 || packet_index
Expected plaintext : plaintext_1280.bin
AES key            : key.bin
Reference IV       : iv_1280.bin
