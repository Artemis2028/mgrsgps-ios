#!/usr/bin/env python3
"""Deterministic synthetic terrain corpus. Outputs test fixtures only; never fetches tiles.
Usage: python3 tools/generate-terrain-fixtures.py OUTPUT_DIRECTORY [MIRROR_DIRECTORY ...]
"""
import argparse, struct, zlib, hashlib, json
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('directories',type=Path,nargs='+')
args=parser.parse_args()
def chunk(t,d):return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d))
sig=b'\x89PNG\r\n\x1a\n'
ihdr=lambda bpp=4,interlace=0:struct.pack('>IIBBBBB',256,256,8,6 if bpp==4 else 2,0,0,interlace)
def rows(bpp):
 raw=bytearray();prev=bytes(256*bpp)
 for y in range(256):
  row=bytearray()
  for x in range(256):
   v=int((-25+x/4+y/8+32768)*256); pix=[v>>16,(v>>8)&255,v&255]
   if (x,y)==(2,0):pix=[255,255,255]
   row.extend(pix)
   if bpp==4:row.append(0 if (x,y)==(0,0) else 127 if (x,y)==(1,0) else 255)
  f=y%5;raw.append(f)
  for i,v in enumerate(row):
   aa=row[i-bpp] if i>=bpp else 0;bb=prev[i];cc=prev[i-bpp] if i>=bpp else 0
   pp=aa+bb-cc;ds=[abs(pp-aa),abs(pp-bb),abs(pp-cc)];pa=[aa,bb,cc][ds.index(min(ds))]
   pr=[0,aa,bb,(aa+bb)//2,pa][f];raw.append((v-pr)&255)
  prev=row
 return bytes(raw)
raw=rows(4);compressed=zlib.compress(raw)
def png(h=ihdr(),c=compressed,extra=b''):return sig+chunk(b'IHDR',h)+extra+chunk(b'IDAT',c)+chunk(b'IEND',b'')
good=png();files={'terrain-rgba.png':good,'terrain-rgb.png':png(ihdr(3),zlib.compress(rows(3)))}
files.update({
 'terrain-bad-crc.png':good[:-1]+bytes([good[-1]^1]),
 'terrain-bad-size.png':png(struct.pack('>IIBBBBB',257,256,8,6,0,0,0)),
 'terrain-bad-interlace.png':png(ihdr(interlace=1)),
 'terrain-bad-critical.png':png(extra=chunk(b'ABCD',b'123')),
 'terrain-bad-transparency.png':png(extra=chunk(b'tRNS',b'\x00'*6)),
 'terrain-bad-filter.png':png(c=zlib.compress(b'\x05'+raw[1:])),
 'terrain-bad-expanded.png':png(c=zlib.compress(raw+b'\x00')),
 'terrain-bad-short.png':png(c=zlib.compress(raw[:-1])),
 'terrain-bad-zlib-trailer.png':png(c=compressed+b'123'),
 'terrain-bad-png-trailer.png':good+b'123',
 'terrain-bad-truncated.png':good[:-10],
 'terrain-bad-idat-gap.png':sig+chunk(b'IHDR',ihdr())+chunk(b'IDAT',compressed[:20])+chunk(b'tEXt',b'a\x00b')+chunk(b'IDAT',compressed[20:])+chunk(b'IEND',b'')})
manifest=dict(version=1,encoding='terrarium',source='fake-terrain-source',revision=10,publishedAtMillis=1793260000000,z=13,x=5333,y=3521,bytes=len(good),sha256=hashlib.sha256(good).hexdigest(),attribution='Synthetic fixture; no survey data')
pal=chunk(b'PLTE',b'\x00\x00\x00')
files['terrain-bad-palette.png']=good[:33]+pal+pal+good[33:]
files['terrain-bad-chunk-length.png']=good[:8]+b'\xff'*4+good[12:]
files['terrain-manifest.json']=json.dumps(manifest,sort_keys=True).encode()
files['terrain-invalid.json']=json.dumps([n for n in files if '-bad-' in n]).encode()
for folder in args.directories:
 folder.mkdir(parents=True,exist_ok=True)
 for name,data in files.items():(folder/name).write_bytes(data)
print('Golden RGBA PNG SHA256',manifest['sha256'])
