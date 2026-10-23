// pdfium_bench.cpp - headless PDFium benchmark harness.
//
// Five workloads, one binary (deterministic, single-threaded, in-memory):
//   render   <pdf> <passes> [scale]  render every page at <scale> (default
//                                    1.0 = 72dpi) with ANNOT|LCD_TEXT flags,
//                                    checksum each bitmap buffer
//   thumb    <pdf> <passes>          render every page at 0.25x scale
//   text     <pdf> <passes>          FPDFText_LoadPage + FPDFText_GetText for
//                                    every page, checksum extracted chars
//   search   <pdf> <passes> <query...>  FPDFText_FindStart/FindNext; pass i
//                                    searches queries[i % n], checksum folds
//                                    all passes' hit counts + query bytes
//   merge    <pdf> <passes>          import all pages into a fresh doc, save
//                                    to memory (FPDF_SaveAsCopy), re-parse the
//                                    result; checksum saved bytes + page count
//
// Every workload prints a final FNV-1a checksum for A/B verification and
// exits non-zero on failure (broken binary -> driver aborts).
//
// Usage: pdfium_bench <workload> <input.pdf> <passes> [args...]

#include <fpdf_edit.h>
#include <fpdf_ppo.h>
#include <fpdf_save.h>
#include <fpdf_text.h>
#include <fpdfview.h>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static uint64_t fnv1a(const uint8_t* p, size_t n, uint64_t h = 1469598103934665603ull) {
  // Large buffers (rendered bitmaps) are sampled every 16th byte: the
  // checksum only needs to detect changes, and hashing the whole bitmap
  // would dominate the render benchmarks (10+ GB per iteration). Small
  // buffers (text, hit counts) are hashed in full.
  const size_t step = n > (1u << 16) ? 16 : 1;  // sample buffers > 64 KB
  for (size_t i = 0; i < n; i += step) {
    h ^= p[i];
    h *= 1099511628211ull;
  }
  return h;
}

static bool loadDoc(const char* path, std::vector<uint8_t>& buf, FPDF_DOCUMENT& doc) {
  FILE* f = fopen(path, "rb");
  if (!f) return false;
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  buf.resize((size_t)n);
  if (fread(buf.data(), 1, (size_t)n, f) != (size_t)n) { fclose(f); return false; }
  fclose(f);
  doc = FPDF_LoadMemDocument(buf.data(), (int)buf.size(), nullptr);
  return doc != nullptr;
}

// --- render ----------------------------------------------------------------

static int runRender(FPDF_DOCUMENT doc, int passes, double scale, uint64_t& outHash) {
  const int pages = FPDF_GetPageCount(doc);
  uint64_t hash = 0;
  for (int pass = 0; pass < passes; pass++) {
    hash = 1469598103934665603ull;  // per-pass hash; the LAST pass's checksum
    for (int i = 0; i < pages; i++) {   // is reported, so it is pass-independent
      FPDF_PAGE page = FPDF_LoadPage(doc, i);
      if (!page) { fprintf(stderr, "load page %d failed\n", i); return 1; }
      int w = (int)(FPDF_GetPageWidthF(page) * scale);
      int h = (int)(FPDF_GetPageHeightF(page) * scale);
      FPDF_BITMAP bmp = FPDFBitmap_Create(w, h, 1); // BGRA
      FPDFBitmap_FillRect(bmp, 0, 0, w, h, 0xFFFFFFFF);
      FPDF_RenderPageBitmap(bmp, page, 0, 0, w, h, 0, FPDF_ANNOT | FPDF_LCD_TEXT);
      hash = fnv1a((const uint8_t*)FPDFBitmap_GetBuffer(bmp),
                   (size_t)FPDFBitmap_GetStride(bmp) * (size_t)h, hash);
      FPDFBitmap_Destroy(bmp);
      FPDF_ClosePage(page);
    }
  }
  outHash = hash;
  return 0;
}

// --- text ------------------------------------------------------------------

static int runText(FPDF_DOCUMENT doc, int passes, uint64_t& outHash) {
  const int pages = FPDF_GetPageCount(doc);
  uint64_t hash = 0;
  for (int pass = 0; pass < passes; pass++) {
    hash = 1469598103934665603ull;  // per-pass hash; last pass is reported
    for (int i = 0; i < pages; i++) {
      FPDF_PAGE page = FPDF_LoadPage(doc, i);
      FPDF_TEXTPAGE tp = FPDFText_LoadPage(page);
      if (!tp) { fprintf(stderr, "text load page %d failed\n", i); return 1; }
      int n = FPDFText_CountChars(tp);
      std::vector<unsigned short> buf((size_t)n + 1);
      FPDFText_GetText(tp, 0, n, buf.data());
      hash = fnv1a((const uint8_t*)buf.data(), (size_t)n * 2, hash);
      hash = fnv1a((const uint8_t*)&n, sizeof(n), hash);
      FPDFText_ClosePage(tp);
      FPDF_ClosePage(page);
    }
  }
  outHash = hash;
  return 0;
}

// --- search ----------------------------------------------------------------

static int runSearch(FPDF_DOCUMENT doc, int passes, const char* const* queries,
                     int nq, uint64_t& outHash) {
  const int pages = FPDF_GetPageCount(doc);
  std::vector<std::vector<unsigned short>> qs(nq);
  for (int i = 0; i < nq; i++) {
    for (const char* p = queries[i]; *p; p++) qs[i].push_back((unsigned char)*p);
    qs[i].push_back(0);
  }
  // Unlike the other workloads, the checksum folds ALL passes (and the query
  // bytes), so with multiple queries every query's hit counts are verified.
  uint64_t hash = 0;
  for (int pass = 0; pass < passes; pass++) {
    const std::vector<unsigned short>& q = qs[pass % nq];
    hash = fnv1a((const uint8_t*)q.data(), (q.size() - 1) * 2, hash);
    for (int i = 0; i < pages; i++) {
      FPDF_PAGE page = FPDF_LoadPage(doc, i);
      FPDF_TEXTPAGE tp = FPDFText_LoadPage(page);
      if (!tp) { fprintf(stderr, "text load page %d failed\n", i); return 1; }
      FPDF_SCHHANDLE f = FPDFText_FindStart(tp, q.data(), 0, 0);
      if (!f) { fprintf(stderr, "find start page %d failed\n", i); return 1; }
      int hits = 0;
      while (FPDFText_FindNext(f)) hits++;
      hash = fnv1a((const uint8_t*)&hits, sizeof(hits), hash);
      FPDFText_FindClose(f);
      FPDFText_ClosePage(tp);
      FPDF_ClosePage(page);
    }
  }
  outHash = hash;
  return 0;
}

// --- merge -----------------------------------------------------------------

struct MemSink : FPDF_FILEWRITE {
  std::vector<uint8_t> buf;
  static int writeBlock(FPDF_FILEWRITE* pthis, const void* data, unsigned long size) {
    MemSink* s = static_cast<MemSink*>(pthis);
    const uint8_t* d = (const uint8_t*)data;
    s->buf.insert(s->buf.end(), d, d + size);
    return 1;
  }
};

static int runMerge(FPDF_DOCUMENT src, int passes, int copies, uint64_t& outHash) {
  const int pages = FPDF_GetPageCount(src);
  uint64_t hash = 0;
  for (int pass = 0; pass < passes; pass++) {
    hash = 1469598103934665603ull;  // per-pass hash; last pass is reported
    FPDF_DOCUMENT dst = FPDF_CreateNewDocument();
    for (int c = 0; c < copies; c++) {
      if (!FPDF_ImportPages(dst, src, nullptr, 0)) {
        fprintf(stderr, "import failed\n");
        return 1;
      }
    }
    int outPages = FPDF_GetPageCount(dst);
    MemSink sink;
    sink.version = 1;
    sink.WriteBlock = &MemSink::writeBlock;
    if (!FPDF_SaveAsCopy(dst, &sink, FPDF_NO_INCREMENTAL)) {
      fprintf(stderr, "save failed\n");
      return 1;
    }
    // re-parse the written bytes and verify the page count, then pixel-check a
    // sample of the re-parsed doc (byte-level output is NOT deterministic - absl
    // hash seeding varies object emission order between processes - but the
    // *content* is, so rendering must be pixel-identical)
    FPDF_DOCUMENT chk = FPDF_LoadMemDocument(sink.buf.data(), (int)sink.buf.size(), nullptr);
    if (!chk || FPDF_GetPageCount(chk) != outPages) {
      fprintf(stderr, "verify failed (pages=%d)\n", chk ? FPDF_GetPageCount(chk) : -1);
      return 1;
    }
    hash = fnv1a((const uint8_t*)&outPages, sizeof(outPages), hash);
    int sample = outPages < 16 ? outPages : 16;
    for (int i = 0; i < sample; i++) {
      FPDF_PAGE page = FPDF_LoadPage(chk, i);
      int w = (int)(FPDF_GetPageWidthF(page) * 0.25);
      int h = (int)(FPDF_GetPageHeightF(page) * 0.25);
      FPDF_BITMAP bmp = FPDFBitmap_Create(w, h, 1);
      FPDFBitmap_FillRect(bmp, 0, 0, w, h, 0xFFFFFFFF);
      FPDF_RenderPageBitmap(bmp, page, 0, 0, w, h, 0, FPDF_ANNOT | FPDF_LCD_TEXT);
      hash = fnv1a((const uint8_t*)FPDFBitmap_GetBuffer(bmp),
                   (size_t)FPDFBitmap_GetStride(bmp) * (size_t)h, hash);
      FPDFBitmap_Destroy(bmp);
      FPDF_ClosePage(page);
    }
    FPDF_CloseDocument(chk);
    FPDF_CloseDocument(dst);
  }
  outHash = hash;
  return 0;
}

// --- main ------------------------------------------------------------------

int main(int argc, char** argv) {
  if (argc < 4) {
    fprintf(stderr,
            "usage: pdfium_bench <render|thumb|text|search|merge> <input.pdf> <passes> [scale|query...|copies]\n");
    return 2;
  }
  const char* workload = argv[1];
  const char* path = argv[2];
  int passes = atoi(argv[3]);

  FPDF_LIBRARY_CONFIG cfg;
  memset(&cfg, 0, sizeof(cfg));
  cfg.version = 2;
  FPDF_InitLibraryWithConfig(&cfg);

  std::vector<uint8_t> buf;
  FPDF_DOCUMENT doc;
  if (!loadDoc(path, buf, doc)) {
    fprintf(stderr, "cannot load %s (err=%lu)\n", path, FPDF_GetLastError());
    return 1;
  }
  int npages = FPDF_GetPageCount(doc);
  uint64_t hash = 0;
  int rc = 0;
  if (!strcmp(workload, "render")) {
    double scale = argc > 4 ? atof(argv[4]) : 1.0;
    rc = runRender(doc, passes, scale, hash);
  } else if (!strcmp(workload, "thumb")) {
    rc = runRender(doc, passes, 0.25, hash);
  } else if (!strcmp(workload, "text")) {
    rc = runText(doc, passes, hash);
  } else if (!strcmp(workload, "search")) {
    // one or more queries; pass i searches for queries[i % nqueries]
    static const char* defq[] = {"the"};
    const char* const* queries = argc > 4 ? &argv[4] : defq;
    int nq = argc > 4 ? argc - 4 : 1;
    rc = runSearch(doc, passes, queries, nq, hash);
  } else if (!strcmp(workload, "merge")) {
    int copies = argc > 4 ? atoi(argv[4]) : 1;
    rc = runMerge(doc, passes, copies, hash);
  } else {
    fprintf(stderr, "unknown workload %s\n", workload);
    rc = 2;
  }

  if (rc == 0)
    printf("pdfium_bench %s: pages=%d passes=%d checksum=%016llx\n", workload,
           npages, passes, (unsigned long long)hash);
  FPDF_CloseDocument(doc);
  FPDF_DestroyLibrary();
  return rc;
}
