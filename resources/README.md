# Resources

This directory contains curated, copied resources from the vendor package plus
live captures from the connected board.

Original source package:

```text
/mnt/c/baidunetdiskdownload/SDR-Z203
```

## Layout

- `board/` - schematic, EXT_IO spreadsheet, selected chip references.
- `firmware/` - copied QSPI and SD-card factory firmware sets.
- `examples/gnuradio/` - vendor GNU Radio flowgraphs.
- `examples/matlab/` - vendor MATLAB/Simulink examples.
- `examples/openwifi-devicetree.dts` - openwifi Z203 devicetree source.
- `source-index/` - generated indexes for large external source archives.
- `vendor-notes/` - selected vendor quick-start PDFs.
- `live-captures/` - outputs captured from the currently connected board/host.
- `MANIFEST.sha256` - checksums for copied resources and captures.

The `vendor-notes/` folder includes both quick-test documents and source
porting documents for Pluto firmware, no-OS, and openwifi.

Schematic findings extracted from `board/SDR-Z203原理图.pdf` are summarized in
`../docs/schematic-notes.md`.

## Not Copied

These files are useful but too large or too broad for this repo by default:

- Pluto firmware source zips, about 3.1 GiB each.
- openwifi SD images, about 15 GiB each.
- Vivado, MATLAB, VMware, Ubuntu ISO, and Windows installer packages.
- Full ADI/Linux source trees from large archives.

Keep those in the original vendor package or external artifact storage unless a
specific task requires importing a smaller extracted subset.

After changing curated resources, run:

```sh
./tools/update_manifest.sh
```
