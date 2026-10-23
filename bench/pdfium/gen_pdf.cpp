// gen_pdf.cpp - deterministic PDF input generator for the pdfium benchmarks.
//
// Generates synthetic documents with the PDFium edit API (no fonts needed -
// the base-14 standard fonts are built in) and saves them with
// FPDF_SaveAsCopy, which is deterministic (no timestamps): regenerating the
// same input yields a byte-identical file.
//
// Usage: gen_pdf <text|vector|images|book> <...>
//   text    <out.pdf> <pages> <lines>          lorem-ipsum text doc
//   vector  <out.pdf> <pages> <objects>        synthetic vector art doc
//   images  <out.pdf> <pages> <images>         gradient bitmap doc
//   book    <out.pdf> <pages> <in.pdf> [in2.pdf ...]
//                              repeat the first page of the input PDF(s)
//                              <pages> times, cycling through the inputs
//                              (single input = one-artwork book; multiple
//                              inputs = the demo vector gallery)
//   osm     <in.osm> <out.pdf>            render an OpenStreetMap export
//                              (Overpass out geom XML) as a vector map page:
//                              water, parks, buildings and roads of the
//                              historic peninsula of Istanbul
//   cat     <out.pdf> <in.pdf>...          concatenate ALL pages of the
//                              input PDFs in order (used for the math
//                              papers benchmark)

#include <fpdf_edit.h>
#include <fpdf_ppo.h>
#include <fpdf_save.h>
#include <fpdfview.h>

#include <cstdint>
#include <string>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <algorithm>
#include <vector>

// xorshift64 PRNG, fixed seed -> deterministic output
static uint64_t rng_state = 0x9E3779B97F4A7C15ull;
static uint64_t rnd() {
  uint64_t x = rng_state;
  x ^= x << 13; x ^= x >> 7; x ^= x << 17;
  return rng_state = x;
}
static double frnd() { return (double)(rnd() >> 11) / 9007199254740992.0; }
static int irnd(int n) { return (int)(rnd() % (uint64_t)n); }

struct MemSink : FPDF_FILEWRITE {
  std::vector<uint8_t> buf;
  static int writeBlock(FPDF_FILEWRITE* pthis, const void* data, unsigned long size) {
    MemSink* s = static_cast<MemSink*>(pthis);
    const uint8_t* d = (const uint8_t*)data;
    s->buf.insert(s->buf.end(), d, d + size);
    return 1;
  }
};

static void saveDoc(FPDF_DOCUMENT doc, const char* path) {
  MemSink sink;
  sink.version = 1;
  sink.WriteBlock = &MemSink::writeBlock;
  if (!FPDF_SaveAsCopy(doc, &sink, FPDF_NO_INCREMENTAL)) {
    fprintf(stderr, "gen_pdf: save failed\n");
    exit(1);
  }
  FILE* f = fopen(path, "wb");
  if (!f || fwrite(sink.buf.data(), 1, sink.buf.size(), f) != sink.buf.size()) {
    fprintf(stderr, "gen_pdf: write %s failed\n", path);
    exit(1);
  }
  fclose(f);
}

// --- book ------------------------------------------------------------------

static void genBook(const char* out, int pages, int nIn, char** inPaths) {
  std::vector<std::vector<uint8_t>> bufs(nIn);
  std::vector<FPDF_DOCUMENT> docs(nIn);
  for (int i = 0; i < nIn; i++) {
    FILE* f = fopen(inPaths[i], "rb");
    if (!f) { fprintf(stderr, "gen_pdf: cannot open %s\n", inPaths[i]); exit(1); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    bufs[i].resize((size_t)n);
    if (fread(bufs[i].data(), 1, (size_t)n, f) != (size_t)n) exit(1);
    fclose(f);
    docs[i] = FPDF_LoadMemDocument(bufs[i].data(), (int)bufs[i].size(), nullptr);
    if (!docs[i]) { fprintf(stderr, "gen_pdf: cannot load %s\n", inPaths[i]); exit(1); }
  }
  FPDF_DOCUMENT doc = FPDF_CreateNewDocument();
  for (int i = 0; i < pages; i++) {
    if (!FPDF_ImportPages(doc, docs[i % nIn], "1", 0)) {
      fprintf(stderr, "gen_pdf: import page %d failed\n", i);
      exit(1);
    }
  }
  saveDoc(doc, out);
  FPDF_CloseDocument(doc);
  for (int i = 0; i < nIn; i++) FPDF_CloseDocument(docs[i]);
}

// --- osm map -----------------------------------------------------------------

struct OsmWay {
  std::vector<std::pair<double, double>> pts;  // lon, lat
  std::string highway, building, natural, leisure;
};

static std::string unescapeXml(const std::string& s) {
  std::string r;
  for (size_t i = 0; i < s.size(); i++) {
    if (s[i] != '&') { r += s[i]; continue; }
    if (s.compare(i, 5, "&amp;") == 0) { r += '&'; i += 4; }
    else if (s.compare(i, 4, "&lt;") == 0) { r += '<'; i += 3; }
    else if (s.compare(i, 4, "&gt;") == 0) { r += '>'; i += 3; }
    else if (s.compare(i, 6, "&quot;") == 0) { r += '"'; i += 5; }
    else if (s.compare(i, 5, "&#39;") == 0) { r += '\''; i += 4; }
    else r += s[i];
  }
  return r;
}

static std::string osmAttr(const std::string& s, const char* key) {
  std::string k = std::string(key) + "=\"";
  size_t p = s.find(k);
  if (p == std::string::npos) return "";
  p += k.size();
  size_t e = s.find('"', p);
  if (e == std::string::npos) return "";
  return s.substr(p, e - p);
}

static std::vector<OsmWay> parseOsm(const std::string& xml) {
  std::vector<OsmWay> ways;
  size_t pos = 0;
  while ((pos = xml.find("<way ", pos)) != std::string::npos) {
    size_t end = xml.find("</way>", pos);
    if (end == std::string::npos) break;
    OsmWay w;
    size_t p = pos;
    while ((p = xml.find("<nd ", p)) != std::string::npos && p < end) {
      size_t e = xml.find('>', p);
      std::string nd = xml.substr(p, e - p);
      std::string lat = osmAttr(nd, "lat");
      std::string lon = osmAttr(nd, "lon");
      if (!lat.empty() && !lon.empty())
        w.pts.emplace_back(atof(lon.c_str()), atof(lat.c_str()));
      p = e;
    }
    p = pos;
    while ((p = xml.find("<tag ", p)) != std::string::npos && p < end) {
      size_t e = xml.find('>', p);
      std::string tag = xml.substr(p, e - p);
      std::string k = unescapeXml(osmAttr(tag, "k"));
      std::string v = unescapeXml(osmAttr(tag, "v"));
      if (k == "highway") w.highway = v;
      else if (k == "building") w.building = v;
      else if (k == "natural") w.natural = v;
      else if (k == "leisure") w.leisure = v;
      p = e;
    }
    if (w.pts.size() >= 2) ways.push_back(std::move(w));
    pos = end + 6;
  }
  return ways;
}

// OSM carto-ish colors
static const uint32_t COL_BG = 0xf2efe9;
static const uint32_t COL_WATER = 0xaadaff;
static const uint32_t COL_PARK = 0xcdebb0;
static const uint32_t COL_BUILDING = 0xd5cbc2;
static uint32_t highwayColor(const std::string& hw) {
  if (hw == "motorway" || hw == "trunk") return 0xe06060;
  if (hw == "primary") return 0xf0a060;
  if (hw == "secondary") return 0xf5d060;
  if (hw == "tertiary") return 0xfaf0c0;
  return 0xffffff;
}
static float highwayWidth(const std::string& hw) {
  if (hw == "motorway" || hw == "trunk") return 4.0f;
  if (hw == "primary") return 3.0f;
  if (hw == "secondary") return 2.5f;
  if (hw == "tertiary") return 2.0f;
  if (hw == "residential" || hw == "unclassified" || hw == "service") return 1.2f;
  return 0.8f;
}

static void genOsm(const char* inPath, const char* out,
                   double cMinLon, double cMinLat, double cMaxLon, double cMaxLat) {
  FILE* f = fopen(inPath, "rb");
  if (!f) { fprintf(stderr, "gen_pdf: cannot open %s\n", inPath); exit(1); }
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  std::string xml((size_t)n, '\0');
  if (fread(&xml[0], 1, (size_t)n, f) != (size_t)n) exit(1);
  fclose(f);
  std::vector<OsmWay> ways = parseOsm(xml);

  // clip to the query bbox: Overpass "out geom" returns the full geometry of
  // ways that merely CROSS the bbox (bridges, the E-5, coastal roads), which
  // would otherwise stretch the map bounds far beyond the peninsula
  size_t dropped = 0;
  for (auto& w : ways) {
    std::vector<std::pair<double, double>> pts;
    for (const auto& p : w.pts)
      if (p.first >= cMinLon && p.first <= cMaxLon &&
          p.second >= cMinLat && p.second <= cMaxLat)
        pts.push_back(p);
    dropped += w.pts.size() - pts.size();
    w.pts = std::move(pts);
  }
  ways.erase(std::remove_if(ways.begin(), ways.end(),
                            [](const OsmWay& w) { return w.pts.size() < 2; }),
             ways.end());
  fprintf(stderr, "gen_pdf osm: %zu ways after bbox clip (%zu nodes dropped)\n",
          ways.size(), dropped);

  // equirectangular projection, north up, 0.35 pt per meter (~1:5000)
  const double SCALE = 0.35;
  double minLon = 1e9, maxLon = -1e9, minLat = 1e9, maxLat = -1e9;
  for (const auto& w : ways)
    for (const auto& p : w.pts) {
      minLon = std::min(minLon, p.first);  maxLon = std::max(maxLon, p.first);
      minLat = std::min(minLat, p.second); maxLat = std::max(maxLat, p.second);
    }
  const double midLon = (minLon + maxLon) / 2, midLat = (minLat + maxLat) / 2;
  const double mPerDegLon =
      111320.0 * cos(midLat * 3.141592653589793 / 180.0);
  const double mPerDegLat = 110540.0;
  const double mapW = (maxLon - minLon) * mPerDegLon * SCALE;
  const double mapH = (maxLat - minLat) * mPerDegLat * SCALE;
  const double W = ceil(mapW) + 200, H = ceil(mapH) + 200;  // 100 pt margin
  fprintf(stderr, "gen_pdf osm: map %.0fx%.0f pt on a %.0fx%.0f pt page\n",
          mapW, mapH, W, H);
  auto px = [&](double lon) { return W / 2 + (lon - midLon) * mPerDegLon * SCALE; };
  auto py = [&](double lat) { return H / 2 + (lat - midLat) * mPerDegLat * SCALE; };

  FPDF_DOCUMENT doc = FPDF_CreateNewDocument();
  FPDF_PAGE page = FPDFPage_New(doc, 0, W, H);

  // background
  FPDF_PAGEOBJECT bg = FPDFPageObj_CreateNewRect(0, 0, W, H);
  FPDFPageObj_SetFillColor(bg, (COL_BG >> 16) & 0xff, (COL_BG >> 8) & 0xff, COL_BG & 0xff, 255);
  FPDFPath_SetDrawMode(bg, 1, 0);
  FPDFPage_InsertObject(page, bg);

  auto addPath = [&](const OsmWay& w, uint32_t col, int fill, int stroke, float width) {
    FPDF_PAGEOBJECT obj = FPDFPageObj_CreateNewPath((float)px(w.pts[0].first),
                                                    (float)py(w.pts[0].second));
    for (size_t i = 1; i < w.pts.size(); i++)
      FPDFPath_LineTo(obj, (float)px(w.pts[i].first), (float)py(w.pts[i].second));
    FPDFPath_Close(obj);
    if (fill)
      FPDFPageObj_SetFillColor(obj, (col >> 16) & 0xff, (col >> 8) & 0xff, col & 0xff, 255);
    if (stroke)
      FPDFPageObj_SetStrokeColor(obj, (col >> 16) & 0xff, (col >> 8) & 0xff, col & 0xff, 255);
    FPDFPath_SetDrawMode(obj, fill, stroke);
    if (stroke) FPDFPageObj_SetStrokeWidth(obj, width);
    FPDFPage_InsertObject(page, obj);
  };

  // water, parks, buildings (fills), then roads (strokes)
  for (const auto& w : ways)
    if (w.natural == "water") addPath(w, COL_WATER, 1, 0, 0);
  for (const auto& w : ways)
    if (w.leisure == "park") addPath(w, COL_PARK, 1, 0, 0);
  for (const auto& w : ways)
    if (!w.building.empty()) addPath(w, COL_BUILDING, 1, 0, 0);
  for (const auto& w : ways)
    if (!w.highway.empty()) addPath(w, highwayColor(w.highway), 0, 1, highwayWidth(w.highway));

  FPDFPage_GenerateContent(page);
  FPDF_ClosePage(page);
  saveDoc(doc, out);
  FPDF_CloseDocument(doc);
}

static void genCat(const char* out, int nIn, char** inPaths) {
  FPDF_DOCUMENT doc = FPDF_CreateNewDocument();
  for (int i = 0; i < nIn; i++) {
    FILE* f = fopen(inPaths[i], "rb");
    if (!f) { fprintf(stderr, "gen_pdf: cannot open %s\n", inPaths[i]); exit(1); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> buf((size_t)n);
    if (fread(buf.data(), 1, (size_t)n, f) != (size_t)n) exit(1);
    fclose(f);
    FPDF_DOCUMENT src = FPDF_LoadMemDocument(buf.data(), (int)buf.size(), nullptr);
    if (!src) { fprintf(stderr, "gen_pdf: cannot load %s\n", inPaths[i]); exit(1); }
    if (!FPDF_ImportPages(doc, src, nullptr, 0)) {
      fprintf(stderr, "gen_pdf: import of %s failed\n", inPaths[i]);
      exit(1);
    }
    FPDF_CloseDocument(src);
  }
  saveDoc(doc, out);
  FPDF_CloseDocument(doc);
}

int main(int argc, char** argv) {
  if (argc < 4 || (strcmp(argv[1], "osm") != 0 && argc < 5)) {
    fprintf(stderr,
            "usage: gen_pdf <book|osm|cat> <...>\n"
            "  book <out> <pages> <in.pdf>... | osm <in.osm> <out.pdf> [bbox] |\n"
            "  cat <out> <in.pdf>...\n");
    return 2;
  }
  FPDF_LIBRARY_CONFIG cfg;
  memset(&cfg, 0, sizeof(cfg));
  cfg.version = 2;
  FPDF_InitLibraryWithConfig(&cfg);

  const char* kind = argv[1];
  if (!strcmp(kind, "book")) {
    if (argc < 5) return 2;
    genBook(argv[2], atoi(argv[3]), argc - 4, &argv[4]);
  } else if (!strcmp(kind, "osm")) {
    if (argc < 4) return 2;
    // optional clip bbox: osm <in.osm> <out.pdf> [minlon minlat maxlon maxlat]
    double b0 = argc > 4 ? atof(argv[4]) : -1e9;
    double b1 = argc > 4 ? atof(argv[5]) : -1e9;
    double b2 = argc > 4 ? atof(argv[6]) : 1e9;
    double b3 = argc > 4 ? atof(argv[7]) : 1e9;
    genOsm(argv[2], argv[3], b0, b1, b2, b3);
  } else if (!strcmp(kind, "cat")) {
    if (argc < 4) return 2;
    genCat(argv[2], argc - 3, &argv[3]);
  } else { fprintf(stderr, "unknown kind %s\n", kind); return 2; }

  FPDF_DestroyLibrary();
  printf("gen_pdf %s: %d pages -> %s\n", kind, atoi(argv[3]), argv[2]);
  return 0;
}
