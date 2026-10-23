#!/usr/bin/env bash
# setup.sh - fetch/build the pdfium benchmark inputs (idempotent).
#
# Three benchmarks, all on real-world inputs (downloaded once, sha256-pinned,
# or converted by pinned tools; everything is content-deterministic - the
# generated PDFs self-check by rendering pixel-identically):
#
#   sdm.pdf         Intel Software Developer's Manual v092 (5363 pages)
#   vector_book.pdf 13-artwork vector gallery (tiger + 5 demo classics +
#                   OSM Istanbul map + 6 MPVG files), 52 pages
#   papers.pdf      6 formula-dense documents (2610 pages), cat'ed
#
# Sizes were calibrated so one benchmark iteration is ~16-21 s on this
# machine; see bench/pdfium/README.md.
# Usage: setup.sh

set -e

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

require "$INT_DIR/gen_pdf" "gen_pdf not found: $INT_DIR/gen_pdf (run $SCRIPT_DIR/build.sh)"
require "$INT_DIR/pdfium_bench" "pdfium_bench not found: $INT_DIR/pdfium_bench (run $SCRIPT_DIR/build.sh)"
mkdir -p "$INT_DIR"

# content-determinism self-check helper: regenerating a derived PDF must
# render pixel-identically (FPDF_SaveAsCopy output is NOT byte-identical
# between processes - absl hash seeding orders objects differently - but the
# CONTENT is).
check_deterministic() { # check_deterministic <name> <kind> <args...>
  local name=$1 kind=$2; shift 2
  local tmp="$INT_DIR/.${name%.pdf}.tmp"
  "$INT_DIR/gen_pdf" "$kind" "$tmp" "$@" > /dev/null
  A=$("$INT_DIR/pdfium_bench" thumb "$INT_DIR/$name" 1 2>/dev/null | grep -oE "checksum=[0-9a-f]+")
  B=$("$INT_DIR/pdfium_bench" thumb "$tmp" 1 2>/dev/null | grep -oE "checksum=[0-9a-f]+")
  rm -f "$tmp"
  [ -n "$A" ] && [ "$A" = "$B" ] \
    || { echo "ERROR: $name is not content-deterministic ($A vs $B)!"; exit 1; }
}

# --- real-world input: Intel Software Developer's Manual -------------------
# Fixed external artifact (Intel SDM v092, combined volumes). Downloaded once
# and integrity-checked; the URL/sha256 pin replaces a git pin here.
SDM_URL="https://cdrdv2-public.intel.com/922475/325462-092-sdm-vol-1-2abcd-3abcd-4.pdf"
SDM_SHA256="16a9336104750613ae2f2bab6eb7a1b21a7e1ef60ced35e9ab2e0d8c7efcec68"
SDM="$INT_DIR/sdm.pdf"
if [ ! -f "$SDM" ]; then
  echo "== downloading Intel SDM (092, $SDM_URL) ..."
  curl -sL -o "$SDM" "$SDM_URL"
fi
echo "$SDM_SHA256  $SDM" | sha256sum -c - > /dev/null \
  || { echo "ERROR: sdm.pdf checksum mismatch (delete it to re-download)"; exit 1; }

# --- vector gallery part 1: the Ghostscript tiger ---------------------------
# The classic tiger.eps (1990, pure vector art: ~2300 bezier paths, 227
# fills), converted to PDF with Ghostscript pdfwrite (stays vector). gs
# embeds timestamps, so the PDF bytes vary between conversions - the CONTENT
# is identical (self-checked when the gallery is built).
TIGER_URL="https://raw.githubusercontent.com/ArtifexSoftware/ghostpdl/master/examples/tiger.eps"
TIGER_SHA256="ed255555fdab768cce7f025dcde744a6807292cac40f80f73733fbffe61edb4f"
TIGER_EPS="$INT_DIR/tiger.eps"
TIGER_PDF="$INT_DIR/tiger.pdf"
if [ ! -f "$TIGER_EPS" ]; then
  echo "== downloading tiger.eps ($TIGER_URL) ..."
  curl -sL -o "$TIGER_EPS" "$TIGER_URL"
fi
echo "$TIGER_SHA256  $TIGER_EPS" | sha256sum -c - > /dev/null \
  || { echo "ERROR: tiger.eps checksum mismatch (delete it to re-download)"; exit 1; }
if [ ! -f "$TIGER_PDF" ]; then
  require "$(command -v gs || echo /nonexistent)" "ghostscript (gs) not found - needed to convert tiger.eps to PDF"
  echo "== converting tiger.eps -> tiger.pdf (gs pdfwrite) ..."
  gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -sOutputFile="$TIGER_PDF" "$TIGER_EPS"
fi

# --- vector gallery part 2: classic demo images ------------------------------
# Famous vector demo files from the Ghostscript examples set: golfer.eps
# (classic Adobe Illustrator demo), escher.ps, vasarely.ps, snowflak.ps
# (Koch snowflakes) and doretree.ps (Gustave Dore engraving, crosshatched
# with ~4800 thin lines). All convert to pure-vector PDFs (0 image
# XObjects; verified).
DEMO_BASE="https://raw.githubusercontent.com/ArtifexSoftware/ghostpdl/master/examples"
DEMO_SHA256=(  # name|sha256
  "golfer.eps|3417f1a4b33cd874596551d63f409f5b6a33eadd0b2e887fa27f58ff223a5a3a"
  "escher.ps|3b2e58b24e167ff0d63cfc79918e2be728174df1851488974501b01aa4a26f11"
  "vasarely.ps|ac15f3637f77ee7a9c0bd4add0e23d763a8f6266d2a8c539764d22f458e71a71"
  "snowflak.ps|8eabb819f44ee02808765f949130f39d9137a6e98815cec296a89558d329ed7b"
  "doretree.ps|2bfc8677738a4c641d84a6d95bc8100c008b11ea9205876da447c07ccff32398"
)
DEMO_PDFS=()
for entry in "${DEMO_SHA256[@]}"; do
  name=${entry%%|*}; want=${entry##*|}
  src="$INT_DIR/$name"
  if [ ! -f "$src" ]; then
    echo "== downloading $name ..."
    curl -sL -o "$src" "$DEMO_BASE/$name"
  fi
  echo "$want  $src" | sha256sum -c - > /dev/null \
    || { echo "ERROR: $name checksum mismatch (delete it to re-download)"; exit 1; }
  pdf="$INT_DIR/${name%.*}.pdf"
  if [ ! -f "$pdf" ]; then
    echo "== converting $name -> ${name%.*}.pdf (gs pdfwrite) ..."
    gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -sOutputFile="$pdf" "$src"
  fi
  DEMO_PDFS+=("$pdf")
done

# --- vector gallery part 3: the historic peninsula of Istanbul (OSM) --------
# Vector map data from OpenStreetMap via the Overpass API (bbox of the
# historic peninsula: 41.002-41.028 N, 28.932-28.990 E): 5440 highways,
# 22169 buildings, water and parks. The fetched .osm (Overpass "out geom"
# XML) is the pinned artifact (sha256); gen_pdf osm projects it and draws
# it as a 1881x1206 pt vector map page (clipped to the query bbox, north
# up).
OSM_QUERY='''[out:xml][timeout:120];
(
  way["highway"](41.002,28.932,41.028,28.990);
  way["building"](41.002,28.932,41.028,28.990);
  way["natural"="water"](41.002,28.932,41.028,28.990);
  way["leisure"="park"](41.002,28.932,41.028,28.990);
  way["landuse"](41.002,28.932,41.028,28.990);
);
out geom;'''
OSM_SHA256="3145253f2d2cb463b0346417cc3538207e395051d9a0b162946145f1ef962f6e"
OSM_XML="$INT_DIR/istanbul.osm"
OSM_PDF="$INT_DIR/istanbul.pdf"
if [ ! -f "$OSM_XML" ]; then
  echo "== fetching Istanbul historic peninsula from the Overpass API ..."
  printf '%s' "$OSM_QUERY" > "$INT_DIR/.overpass.query"
  curl -s --data-urlencode data@"$INT_DIR/.overpass.query" \
    "https://overpass-api.de/api/interpreter" -o "$OSM_XML"
  rm -f "$INT_DIR/.overpass.query"
fi
echo "$OSM_SHA256  $OSM_XML" | sha256sum -c - > /dev/null \
  || { echo "ERROR: istanbul.osm checksum mismatch (OSM data changed; delete it and update OSM_SHA256)"; exit 1; }
if [ ! -f "$OSM_PDF" ]; then
  echo "== building istanbul.pdf (gen_pdf osm) ..."
  "$INT_DIR/gen_pdf" osm "$OSM_XML" "$OSM_PDF" 28.932 41.002 28.990 41.028
fi

# --- vector gallery part 4: the MPVG dataset --------------------------------
# Six files from the MPVG ("Massively-Parallel Vector Graphics", Gan et al.
# 2014, IMPA) dataset: car, contour, drops, hawaii, paris-30k (30k paths!)
# and reschart. The SVG inputs come from the official inputs.tar.gz
# (sha256-pinned) and are converted to pure-vector PDFs with rsvg-convert
# (0 image XObjects; verified).
MPVG_URL="http://w3.impa.br/~diego/projects/GanEtAl14/inputs.tar.gz"
MPVG_SHA256="4fd444c1543e66a379c40bfd16e99e7139dc065b05ba155d35c332fa6a9b8ae9"
MPVG_TAR="$INT_DIR/mpvg-inputs.tar.gz"
MPVG_SVGS=("car" "contour" "drops" "hawaii" "paris-30k" "reschart")
if [ ! -f "$MPVG_TAR" ]; then
  echo "== downloading MPVG inputs ($MPVG_URL) ..."
  curl -sL -o "$MPVG_TAR" "$MPVG_URL"
fi
echo "$MPVG_SHA256  $MPVG_TAR" | sha256sum -c - > /dev/null \
  || { echo "ERROR: mpvg inputs.tar.gz checksum mismatch (delete it to re-download)"; exit 1; }
require "$(command -v rsvg-convert || echo /nonexistent)" "rsvg-convert not found - needed to convert MPVG SVGs to PDF"
for name in "${MPVG_SVGS[@]}"; do
  pdf="$INT_DIR/$name.pdf"
  if [ ! -f "$pdf" ]; then
    echo "== converting MPVG $name.svg -> $name.pdf (rsvg-convert) ..."
    tar xzf "$MPVG_TAR" -C "$INT_DIR" "inputs/svg/$name.svg"
    rsvg-convert -f pdf -o "$pdf" "$INT_DIR/inputs/svg/$name.svg"
    rm -rf "$INT_DIR/inputs"
  fi
done

# --- the vector gallery ------------------------------------------------------
# vector_book.pdf: 13 artworks (tiger, 5 demo classics, the Istanbul map and
# the 6 MPVG files), 52 pages = 4 full cycles
if [ ! -f "$INT_DIR/vector_book.pdf" ]; then
  echo "== building vector_book.pdf (13 artworks, 52 pages) ..."
  "$INT_DIR/gen_pdf" book "$INT_DIR/vector_book.pdf" 52 \
    "$TIGER_PDF" "${DEMO_PDFS[@]}" "$OSM_PDF" \
    "$INT_DIR/car.pdf" "$INT_DIR/contour.pdf" "$INT_DIR/drops.pdf" \
    "$INT_DIR/hawaii.pdf" "$INT_DIR/paris-30k.pdf" "$INT_DIR/reschart.pdf" > /dev/null
fi
check_deterministic vector_book.pdf book 52 \
  "$TIGER_PDF" "${DEMO_PDFS[@]}" "$OSM_PDF" \
  "$INT_DIR/car.pdf" "$INT_DIR/contour.pdf" "$INT_DIR/drops.pdf" \
  "$INT_DIR/hawaii.pdf" "$INT_DIR/paris-30k.pdf" "$INT_DIR/reschart.pdf"

# --- math papers: documents with dense, complex formulas ---------------------
# Six formula-dense documents (2610 pages, all sha256-pinned), concatenated
# into papers.pdf by gen_pdf cat. Measured formula density (equations per
# page via '=' in extracted text): Ginsparg, Applied Conformal Field Theory
# (arXiv:hep-th/9108028, 17.7 eq/pg - the densest), Tong's General
# Relativity notes (8.4), Siegel's Fields (1080 pages, 7.3), Qualls' CFT
# notes (arXiv:1511.04074, 6.9), Tong's QFT notes (6.4) and Vakil's
# algebraic geometry notes, "The Rising Sea" (4.4).
PAPER_URLS=(
  "ginsparg|https://export.arxiv.org/pdf/hep-th/9108028|af1003b015fc1a89eb7f2e15b8ef7380ba0de1cd73dfa5c3be32c19b6643b9cd"
  "gr|http://www.damtp.cam.ac.uk/user/tong/gr/gr.pdf|10f6ebede163c96474b3cdb84fa3112cddb24b0fbccae7454f885116cb6c1aca"
  "siegel|http://insti.physics.sunysb.edu/~siegel/Fields4.pdf|4f030003af22d4ba9cd289a3dc3fc8e29d1b862872697b0eba0c54d171c48c58"
  "qualls|https://export.arxiv.org/pdf/1511.04074|f0f461680f60e8e991b2ae6a3003d490b999a53fdadd7546331ad465abde5590"
  "tong|http://www.damtp.cam.ac.uk/user/tong/qft/qft.pdf|60a3156ba0fd04c3935b3b8889f6f3ff0e9a021240e121c1bbd44812554bda3b"
  "vakil|http://math.stanford.edu/~vakil/216blog/FOAGnov1817public.pdf|b956026cc9caddd372332b94f6ecdb77932a08ab0d90dc802bad37b7a6ee62c4"
)
PAPER_PDFS=()
for entry in "${PAPER_URLS[@]}"; do
  name=${entry%%|*}; rest=${entry#*|}; url=${rest%%|*}; want=${rest##*|}
  pdf="$INT_DIR/$name.pdf"
  if [ ! -f "$pdf" ]; then
    echo "== downloading $name ($url) ..."
    curl -sL -o "$pdf" "$url"
    sleep 2   # be polite to export.arxiv.org
  fi
  echo "$want  $pdf" | sha256sum -c - > /dev/null \
    || { echo "ERROR: $name.pdf checksum mismatch (delete it to re-download)"; exit 1; }
  PAPER_PDFS+=("$pdf")
done
if [ ! -f "$INT_DIR/papers.pdf" ]; then
  echo "== building papers.pdf (gen_pdf cat, ${#PAPER_PDFS[@]} papers) ..."
  "$INT_DIR/gen_pdf" cat "$INT_DIR/papers.pdf" "${PAPER_PDFS[@]}" > /dev/null
fi
check_deterministic papers.pdf cat "${PAPER_PDFS[@]}"

setup_done
