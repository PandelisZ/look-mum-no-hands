# RealWorld Pointer Cursor Assets

These cursor assets are downloaded from RW Designer and bundled as transparent
PNG frames for the LMNH virtual cursor picker. The original `.ani` and `.cur`
files are preserved under `Originals/`.

All bundled assets listed here are published on RW Designer under Attribution
Required (CC BY).

| App option | Source | Original file | Bundled PNG files | Hotspot | Notes |
| --- | --- | --- | --- | --- | --- |
| Custom Cursor | https://www.rw-designer.com/cursor-detail/10495 | `Originals/custom-curser.ani` | `custom-curser-00.png` ... `custom-curser-11.png` | `9,2` | 12 frames, 0.8s loop |
| Flame 2black | https://www.rw-designer.com/cursor-detail/5471 | `Originals/flame-2black.ani` | `flame-2black-00.png` ... `flame-2black-06.png` | `0,0` | 7 frames, 1.1666666666667s loop |
| TARDIS | https://www.rw-designer.com/cursor-detail/5495 | `Originals/tardis.ani` | `tardis-00.png` ... `tardis-39.png` | `15,15` | 40 frames, 3.3333333333333s loop |
| Crosshair Green | https://www.rw-designer.com/cursor-set/crosshair-green | `Originals/crosshair-green.cur` | `crosshair-green.png` | `16,16` | Main cursor from the set |
| Gun Advanced | https://www.rw-designer.com/cursor-set/advanced | `Originals/gun-advanced.cur` | `gun-advanced.png` | `9,9` | Main normal cursor from the set |
| Shining Sword | https://www.rw-designer.com/cursor-set/swordcollection | `Originals/shining-sword.ani` | `shining-sword-00.png` ... `shining-sword-07.png` | `15,2` | Main cursor from the set, 8 frames, 1.5333333333333s loop |

For animated cursors, PNG frames and hotspot coordinates came from the
corresponding RW Designer `cursor-css/{id}.css` endpoints. For static `.cur`
files, PNGs were produced with `sips`, and hotspots were read from the CUR
directory entries.
