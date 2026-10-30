#!/usr/bin/env python3
"""Independent Python zipfile fixtures; full ZIP64 central/footer records follow
PKWARE APPNOTE 6.3.10 sections 4.3.14/15 and 4.5.3. Not app-generated ZIP data.
Run from the repo root. Every generated fixture is also read by Python zipfile.
"""
from pathlib import Path
import io
import struct
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "GridFixCore/Tests/GridFixCoreTests/Resources"

class Stream(io.BytesIO):
    def seekable(self): return False
    def seek(self, *args): raise io.UnsupportedOperation("nonseekable fixture")

def archive(members, streamed=True, method=zipfile.ZIP_DEFLATED, force64=True):
    output = Stream() if streamed else io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=method) as writer:
        for name, data in members:
            entry = zipfile.ZipInfo(name, (2023, 11, 14, 12, 0, 0))
            entry.compress_type = method
            with writer.open(entry, "w", force_zip64=force64) as member:
                member.write(data)
    return output.getvalue()

def full_zip64(data):
    end = data.rindex(b"PK\x05\x06")
    count = struct.unpack_from("<H", data, end+10)[0]
    offset = struct.unpack_from("<I", data, end+16)[0]
    cursor = offset
    central = bytearray()
    for _ in range(count):
        header = bytearray(data[cursor:cursor+46])
        assert header[:4] == b"PK\x01\x02"
        compressed, size = struct.unpack_from("<II", header, 20)
        name_size, extra_size, comment_size = struct.unpack_from("<HHH", header, 28)
        local = struct.unpack_from("<I", header, 42)[0]
        name = data[cursor+46:cursor+46+name_size]
        extra = data[cursor+46+name_size:cursor+46+name_size+extra_size]
        comment = data[cursor+46+name_size+extra_size:cursor+46+name_size+extra_size+comment_size]
        extension = struct.pack("<HHQQQI", 1, 28, size, compressed, local, 0)
        struct.pack_into("<H", header, 6, 45)
        struct.pack_into("<II", header, 20, 0xffffffff, 0xffffffff)
        struct.pack_into("<H", header, 30, len(extension)+len(extra))
        struct.pack_into("<H", header, 34, 0xffff)
        struct.pack_into("<I", header, 42, 0xffffffff)
        central += header + name + extension + extra + comment
        cursor += 46 + name_size + extra_size + comment_size
    assert cursor == end
    record_offset = offset + len(central)
    record = struct.pack("<IQHHIIQQQQ", 0x06064b50, 44, 45, 45, 0, 0, count, count, len(central), offset)
    locator = struct.pack("<IIQI", 0x07064b50, 0, record_offset, 1)
    footer = struct.pack("<IHHHHIIH", 0x06054b50, 0, 0, 0xffff, 0xffff, 0xffffffff, 0xffffffff, 0)
    return data[:offset] + central + record + locator + footer

def original(name):
    with zipfile.ZipFile(RESOURCES / name) as source:
        return [(entry.filename, source.read(entry)) for entry in source.infolist()]

def save(name, data, members):
    with zipfile.ZipFile(io.BytesIO(data)) as reader:
        assert reader.testzip() is None
        assert [(entry.filename, reader.read(entry)) for entry in reader.infolist()] == members
    (RESOURCES / name).write_bytes(data)
    print(name, len(data), "bytes; Python CRC/contents verified")

kml = b'<kml xmlns="http://www.opengis.net/kml/2.2"><Placemark><name>ZIP64 rally</name><Point><coordinates>54.3773,24.4539</coordinates></Point></Placemark></kml>'
point = [("doc.kml", kml)]
save("python-local64-stored.zip", archive(point, False, zipfile.ZIP_STORED), point)
save("python-local64-streamed.zip", archive(point), point)
save("zip64-full-kmz.kmz", full_zip64(archive(point)), point)
for source, target in [("android-backup-contract.zip", "zip64-full-backup.zip"),
                       ("android-mission-package.zip", "zip64-full-datapackage.zip")]:
    members = original(source)
    save(target, full_zip64(archive(members)), members)

# Optional descriptor signatures are removed without changing member contents.
def unsigned_descriptor(data):
    with zipfile.ZipFile(io.BytesIO(data)) as reader:
        member = reader.infolist()[0]
    local = member.header_offset
    name_size, extra_size = struct.unpack_from("<HH", data, local+26)
    descriptor = local+30+name_size+extra_size+member.compress_size
    assert data[descriptor:descriptor+4] == b"PK\x07\x08"
    original_end = data.rindex(b"PK\x05\x06")
    offset = struct.unpack_from("<I", data, original_end+16)[0]
    result = bytearray(data[:descriptor]+data[descriptor+4:])
    struct.pack_into("<I", result, original_end-4+16, offset-4)
    return bytes(result)

for force64 in [False, True]:
    data = unsigned_descriptor(archive(point, force64=force64))
    save("python-unsigned-"+("64" if force64 else "32")+".zip", data, point)

# A legitimate CRC equal to the optional descriptor signature exercises the
# ambiguity without relying on this project's CRC or ZIP writer.
base = zlib.crc32(bytes(4))
basis = {}
for bit in range(32):
    vector, mask = zlib.crc32((1 << bit).to_bytes(4, "little")) ^ base, 1 << bit
    while vector:
        pivot = vector.bit_length()-1
        if pivot not in basis:
            basis[pivot] = vector, mask
            break
        vector ^= basis[pivot][0]; mask ^= basis[pivot][1]
vector, mask = 0x08074b50 ^ base, 0
while vector:
    pivot = vector.bit_length()-1
    vector ^= basis[pivot][0]; mask ^= basis[pivot][1]
crc_payload = mask.to_bytes(4, "little")
assert zlib.crc32(crc_payload) == 0x08074b50
crc_members = [("crc.bin", crc_payload)]
save("zip64-crc-signature.zip", unsigned_descriptor(archive(crc_members)), crc_members)
print("CRC signature payload:", crc_payload.hex())

# Exercise the actual Android backup decompression ceiling, including ignored
# members. Compact on disk; exactly 32 MiB after decompression.
boundary = original("android-backup-contract.zip")
remaining = 32*1024*1024-sum(len(data) for _, data in boundary)
boundary += [("ignored-a.bin", bytes(16*1024*1024)), ("ignored-b.bin", bytes(remaining-16*1024*1024))]
save("zip64-budget-boundary.zip", full_zip64(archive(boundary)), boundary)

# Central ZIP64 values are conditional, not a fixed tuple. Exercise one size
# sentinel and one offset sentinel without a ZIP64 footer.
def conditional_central(data, kind):
    end = data.rindex(b"PK\x05\x06")
    offset = struct.unpack_from("<I", data, end+16)[0]
    header = bytearray(data[offset:offset+46])
    name_size, extra_size, comment_size = struct.unpack_from("<HHH", header, 28)
    assert extra_size == 0
    field = 24 if kind == "size" else 42
    value = struct.unpack_from("<I", header, field)[0]
    extension = struct.pack("<HHQ", 1, 8, value)
    struct.pack_into("<I", header, field, 0xffffffff)
    struct.pack_into("<H", header, 30, len(extension))
    tail = data[offset+46:offset+46+name_size]
    central = header+tail+extension+data[offset+46+name_size:end]
    footer = bytearray(data[end:])
    struct.pack_into("<I", footer, 12, len(central))
    return data[:offset]+central+footer

for kind in ["size", "offset"]:
    save("zip64-central-"+kind+".zip", conditional_central(archive(point), kind), point)
