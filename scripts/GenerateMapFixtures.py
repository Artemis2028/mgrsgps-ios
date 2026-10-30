#!/usr/bin/env python3
"""Synthetic raster MBTiles fixtures written independently of Swift's archive code."""
import base64
import sqlite3
from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'GridFixCore/Tests/GridFixCoreTests/Resources'
png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
for name, normalized in [('raster-tms.mbtiles', False), ('raster-view.mbtiles', True)]:
    file = root / name
    file.unlink(missing_ok=True)
    with sqlite3.connect(file) as db:
        db.execute('CREATE TABLE metadata(name TEXT, value TEXT)')
        db.executemany('INSERT INTO metadata VALUES(?,?)', [('format','png'),('name','Synthetic training map'),('bounds','-90,66,-45,80'),('attribution','GridFix synthetic fixture')])
        if normalized:
            db.executescript('CREATE TABLE images(tile_id TEXT, tile_data BLOB); CREATE TABLE map(zoom_level INTEGER,tile_column INTEGER,tile_row INTEGER,tile_id TEXT); CREATE VIEW tiles AS SELECT zoom_level,tile_column,tile_row,tile_data FROM map JOIN images USING(tile_id);')
            db.execute('INSERT INTO images VALUES(?,?)', ('fixture',png))
            db.execute('INSERT INTO map VALUES(3,2,6,?)', ('fixture',))
        else:
            db.execute('CREATE TABLE tiles(zoom_level INTEGER,tile_column INTEGER,tile_row INTEGER,tile_data BLOB)')
            db.execute('INSERT INTO tiles VALUES(3,2,6,?)', (png,))
