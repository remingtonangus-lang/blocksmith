#!/usr/bin/env python3
# The SHA-256 of an APK's first signing certificate (APK Signature Scheme v3, else v2), for tools/headset_gate.sh: an APK
# signed with another key than the installed app's can only go on by uninstalling, which wipes the saves.
#   python3 tools/apk_signer.py APK   -> prints the hex digest, or "unknown" (no v2/v3 block)
import hashlib, struct, sys

def u32(b, o): return struct.unpack_from("<I", b, o)[0]
def u64(b, o): return struct.unpack_from("<Q", b, o)[0]

def lp(b, o):
    n = u32(b, o)
    return b[o + 4:o + 4 + n], o + 4 + n

def cert(path):
    d = open(path, "rb").read()
    e = d.rfind(b"PK\x05\x06")
    if e < 0: return None
    cd = u32(d, e + 16)
    if d[cd - 16:cd] != b"APK Sig Block 42": return None
    size = u64(d, cd - 24)
    start = cd - size - 8
    o, end = start + 8, cd - 24
    blocks = {}
    while o < end:
        n = u64(d, o); bid = u32(d, o + 8)
        blocks[bid] = d[o + 12:o + 8 + n]
        o += 8 + n
    for bid in (0xF05368C0, 0x7109871A):            # v3, v2
        if bid not in blocks: continue
        signers, _ = lp(blocks[bid], 0)
        signer, _ = lp(signers, 0)
        signed, _ = lp(signer, 0)
        _, o2 = lp(signed, 0)                        # digests
        certs, _ = lp(signed, o2)
        c, _ = lp(certs, 0)
        return hashlib.sha256(c).hexdigest()
    return None

print(cert(sys.argv[1]) or "unknown")
