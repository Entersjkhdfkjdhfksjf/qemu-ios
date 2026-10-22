#!/usr/bin/env python3
"""Download an iPod2,1 IPSW, decrypt its boot images with the profile's keys and sanity-check them.
Prints a report only (no firmware is stored or published)."""
import json, os, re, struct, subprocess, sys, tempfile, urllib.request, zipfile, shutil

prof = json.load(open(sys.argv[1]))
build = prof["build"]
work = sys.argv[2] if len(sys.argv) > 2 else "/tmp/ipsw-" + build
os.makedirs(work, exist_ok=True)

def find_url():
    data = json.load(urllib.request.urlopen("https://api.ipsw.me/v4/device/iPod2,1?type=ipsw", timeout=60))
    for fw in data["firmwares"]:
        if fw["buildid"].lower() == build.lower():
            return fw["url"]
    print("builds known to ipsw.me for iPod2,1:", sorted((f["version"], f["buildid"]) for f in data["firmwares"]))
    raise SystemExit("no IPSW for build " + build)

ipsw = os.path.join(work, "fw.ipsw")
if not os.path.exists(ipsw):
    url = find_url()
    print("IPSW url:", url)
    subprocess.check_call(["curl", "-fL", "--retry", "5", "-o", ipsw, url])

z = zipfile.ZipFile(ipsw)
names = z.namelist()
print("IPSW members (top level + all_flash):")
for n in names:
    if n.count("/") == 0 or "all_flash" in n:
        print("  ", n, z.getinfo(n).file_size)

def pick(sub):
    for n in names:
        if sub.lower() in os.path.basename(n).lower():
            return n

want = {"llb": "llb.n72ap", "iboot": "iboot.n72ap", "applelogo": "applelogo", "dtree": "devicetree.n72ap",
        "kernelcache": "kernelcache"}

def parse_img3(d):
    assert d[:4] == b"3gmI", d[:8]
    off, tags = 20, []
    while off + 12 <= len(d):
        magic = d[off:off+4][::-1].decode("latin1")
        total, dlen = struct.unpack("<II", d[off+4:off+12])
        tags.append((magic, d[off+12:off+12+dlen]))
        if total == 0: break
        off += total
    return tags

def dec(payload, iv, key):
    n = len(payload) & ~0xF
    with tempfile.NamedTemporaryFile() as f:
        f.write(payload[:n]); f.flush()
        return subprocess.check_output(["openssl", "enc", "-d", "-aes-128-cbc", "-nopad", "-K", key, "-iv", iv, "-in", f.name])

def strings(b, minlen=6):
    for m in re.finditer(rb"[\x20-\x7e]{%d,}" % minlen, b):
        yield m.start(), m.group().decode()

PAT = re.compile(r"rd=|boot-args|bluetooth|uart|serial=|debug|nand-enable|-v$|root|iBoot-|amfi|cs_enforcement|kernelcache|DeviceTree", re.I)

for key, sub in want.items():
    n = pick(sub)
    if not n:
        print(f"[{key}] not found in IPSW"); continue
    d = z.read(n)
    base = os.path.basename(n)
    try:
        tags = parse_img3(d)
    except AssertionError as e:
        print(f"[{key}] {base}: not an IMG3 ({e})"); continue
    tagnames = [t[0] for t in tags]
    data = next((t[1] for t in tags if t[0] == "DATA"), None)
    k = prof["images"].get(key)
    if data is None or not k:
        print(f"[{key}] {base}: tags={tagnames} (no DATA/key)"); continue
    out = dec(data, k["iv"], k["key"])
    head = out[:16].hex()
    ok = {"iboot": b"iBoot" in out[:0x400] or b"iBoot" in out, "llb": b"iBoot" in out or b"LLB" in out,
          "kernelcache": out[:8] == b"complzss", "applelogo": out[:8] in (b"complzss", b"iBootIm\x00"[:8]),
          "dtree": b"compatible" in out[:0x2000] or b"device-tree" in out[:0x4000]}[key]
    print(f"[{key}] {base}: size={len(data)} first16={head} -> {'KEY OK' if ok else 'KEY LOOKS WRONG'}")
    if key == "iboot":
        open(os.path.join(work, "iboot.bin"), "wb").write(out)
        print("   iBoot string offsets (address = 0x0ff00000 + offset if loaded at IBOOT_MEM_BASE):")
        c = 0
        for o, s in strings(out):
            if PAT.search(s):
                print(f"     off 0x{o:06x} (addr 0x{0x0ff00000+o:08x}): {s[:110]}")
                c += 1
                if c > 60: break
    if key == "kernelcache" and out[:8] == b"complzss":
        adler, usize, csize = struct.unpack(">III", out[8:20])
        print(f"   complzss header: adler=0x{adler:08x} uncompressed={usize} compressed={csize}")
