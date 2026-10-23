// diff_bench.cpp - headless benchmark harness for git's diff engine (xdiff).
//
// Four workloads, one binary (all deterministic, single-threaded), each
// running xdl_diff over a pair of inputs:
//   myers:      default algorithm + indent heuristic (git diff's default)
//   minimal:    XDF_NEED_MINIMAL (full-cost Myers)
//   patience:   XDF_PATIENCE_DIFF
//   histogram:  XDF_HISTOGRAM_DIFF
//
// Inputs are either two FILES (one diff per pass) or two DIRECTORIES
// (tree mode: every changed file is diffed per pass, like
// `git diff old_tree new_tree`; byte-identical files are skipped, binary
// files are skipped per git's NUL-byte heuristic).
//
// Every pass is verified: the context is set to the whole file, so the
// emitted unified diff must reproduce BOTH input files exactly (line count
// + FNV-1a digest of the reconstructed pre/post image).  A broken binary
// fails loudly instead of silently producing wrong output (same spirit as
// the meshopt codec roundtrip check).  The full-file emit costs little vs.
// the diff search itself (a few percent of iteration time), and the search
// is what the benchmark measures.
//
// Usage: diff_bench <myers|minimal|patience|histogram>
//                   <old_file|old_dir> <new_file|new_dir> <passes>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include <dirent.h>
#include <sys/stat.h>

// xdiff.h is normally included after git-compat-util.h, which provides
// these (regex_t / size_t are used in xpparam_t)
#include <stddef.h>
#include <regex.h>

#include "xdiff.h"

// --- shims for git-compat-util symbols the xdiff engine references --------
// The xdiff .c files are compiled as C and expect git's wrappers; these are
// the only external symbols they need (verified with nm -u on the objects).
extern "C" void *xmalloc(size_t n)
{
	void *p = malloc(n ? n : 1);
	if (!p)
		abort();
	return p;
}
extern "C" void *xcalloc(size_t n, size_t sz)
{
	void *p = calloc(n ? n : 1, sz ? sz : 1);
	if (!p)
		abort();
	return p;
}
extern "C" void *xrealloc(void *p, size_t n)
{
	void *q = realloc(p, n ? n : 1);
	if (!q)
		abort();
	return q;
}
extern "C" void BUG_fl(const char *file, int line, const char *fmt, ...)
{
	(void)file;
	(void)line;
	(void)fmt;
	abort();
}

// sane_ctype[256] - git's locale-independent ASCII ctype table (ctype.c);
// sane-ctype.h remaps isalpha/isspace/isdigit/tolower/... onto it.  Mask
// values: S=0x01, D=0x02, A=0x04, G=0x08, R=0x10, P=0x20, X=0x40, U=0x80.
extern "C" const unsigned char sane_ctype[256] = {
	0x40,0x40,0x40,0x40,0x40,0x40,0x40,0x40,0x40,0x41,0x41,0x40,0x40,0x41,0x40,0x40,
	0x40,0x40,0x40,0x40,0x40,0x40,0x40,0x40,0x40,0x40,0x40,0x40,0x40,0x40,0x40,0x40,
	0x01,0x20,0x20,0x20,0x10,0x20,0x20,0x20,0x10,0x10,0x08,0x10,0x20,0x20,0x10,0x20,
	0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x20,0x20,0x20,0x20,0x20,0x08,
	0x20,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,
	0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x08,0x08,0x80,0x10,0x20,
	0x20,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,
	0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x10,0x10,0x80,0x20,0x40,
};

// --- file loading + per-line digest ----------------------------------------

struct File {
	std::vector<char> data;              // file bytes
	uint64_t lines = 0;                  // line count
	// FNV-1a over each line, incl. its '\n'; the offset basis is the
	// digest of an empty stream, so a default-constructed (empty) File
	// matches the verification of an empty diff side.
	uint64_t digest = 1469598103934665603ull;
};

static bool loadFile(const std::string &path, File &f)
{
	FILE *fp = fopen(path.c_str(), "rb");
	if (!fp)
		return false;
	fseek(fp, 0, SEEK_END);
	long sz = ftell(fp);
	fseek(fp, 0, SEEK_SET);
	if (sz < 0)
		return false;
	f.data.resize((size_t)sz);
	if (sz > 0 && fread(f.data.data(), 1, (size_t)sz, fp) != (size_t)sz) {
		fclose(fp);
		return false;
	}
	fclose(fp);

	uint64_t h = 1469598103934665603ull;   // FNV-1a offset basis
	size_t start = 0;
	for (size_t i = 0; i < f.data.size(); i++) {
		if (f.data[i] == '\n') {
			for (size_t j = start; j <= i; j++) {
				h ^= (uint8_t)f.data[j];
				h *= 1099511628211ull;
			}
			f.lines++;
			start = i + 1;
		}
	}
	if (start < f.data.size()) {   // final line without '\n'
		for (size_t j = start; j < f.data.size(); j++) {
			h ^= (uint8_t)f.data[j];
			h *= 1099511628211ull;
		}
		f.lines++;
	}
	f.digest = h;
	return true;
}

// --- xdiff callbacks: reconstruct + verify the emitted stream --------------

struct Verify {
	const File *oldF;
	const File *newF;
	uint64_t oldLines = 0, newLines = 0;
	uint64_t oldDigest = 1469598103934665603ull;
	uint64_t newDigest = 1469598103934665603ull;
	uint64_t hunks = 0;
};

static inline void hashBytes(uint64_t &h, const char *p, long n)
{
	for (long i = 0; i < n; i++) {
		h ^= (uint8_t)p[i];
		h *= 1099511628211ull;
	}
}

// out_hunk: hunk header (structured callback).  The hunk ranges are not
// needed for the roundtrip check; count them for the summary.
static int out_hunk(void *priv, long, long, long, long, const char *, long)
{
	Verify *v = (Verify *)priv;
	v->hunks++;
	return 0;
}

// out_line: one record = [prefix][content]([no-newline notice]).
//   ' ' context -> part of BOTH files
//   '-' removed  -> part of the OLD file
//   '+' added    -> part of the NEW file
// Reconstruct both files from the stream and compare against the originals.
static int out_line(void *priv, mmbuffer_t *mb, int nbuf)
{
	Verify *v = (Verify *)priv;
	if (nbuf < 2 || mb[0].size != 1)
		return 0;   // hunk headers only (not emitted when out_hunk is set)
	const char *content = mb[1].ptr;
	long n = mb[1].size;
	switch (mb[0].ptr[0]) {
	case ' ':
		hashBytes(v->oldDigest, content, n);
		hashBytes(v->newDigest, content, n);
		v->oldLines++;
		v->newLines++;
		break;
	case '-':
		hashBytes(v->oldDigest, content, n);
		v->oldLines++;
		break;
	case '+':
		hashBytes(v->newDigest, content, n);
		v->newLines++;
		break;
	default:
		return -1;
	}
	return 0;
}

// --- one diff pass ----------------------------------------------------------

enum Algo { ALGO_MYERS, ALGO_MINIMAL, ALGO_PATIENCE, ALGO_HISTOGRAM };

static Algo parseAlgo(const char *s)
{
	if (strcmp(s, "myers") == 0)
		return ALGO_MYERS;
	if (strcmp(s, "minimal") == 0)
		return ALGO_MINIMAL;
	if (strcmp(s, "patience") == 0)
		return ALGO_PATIENCE;
	if (strcmp(s, "histogram") == 0)
		return ALGO_HISTOGRAM;
	return (Algo)-1;
}

static const char *algoName(Algo a)
{
	switch (a) {
	case ALGO_MINIMAL:   return "minimal";
	case ALGO_PATIENCE:  return "patience";
	case ALGO_HISTOGRAM: return "histogram";
	default:             return "myers";
	}
}

// diffPair - one xdl_diff over the pair; returns 0 on success (output
// verified against the originals), 1 on failure.  On success *hunksOut
// receives the number of hunks emitted.
static int diffPair(const File &oldF, const File &newF, Algo algo, int pass,
		    uint64_t *hunksOut)
{
	mmfile_t mf1 = { const_cast<char *>(oldF.data.data()),
			 (long)oldF.data.size() };
	mmfile_t mf2 = { const_cast<char *>(newF.data.data()),
			 (long)newF.data.size() };

	xpparam_t xpp = { 0 };
	switch (algo) {
	case ALGO_MYERS:
		xpp.flags = XDF_INDENT_HEURISTIC;   // git diff's default
		break;
	case ALGO_MINIMAL:
		xpp.flags = XDF_NEED_MINIMAL;
		break;
	case ALGO_PATIENCE:
		xpp.flags = XDF_PATIENCE_DIFF;
		break;
	case ALGO_HISTOGRAM:
		xpp.flags = XDF_HISTOGRAM_DIFF;
		break;
	}

	// ctxlen = whole file: every line is emitted, so the output is a
	// lossless encoding of the input pair and can be verified exactly.
	// (xdl_get_hunk clamps the context to the file length.)
	xdemitconf_t xecfg = { 0 };
	xecfg.ctxlen = (1L << 30);

	xdemitcb_t ecb = { 0 };
	Verify v = { &oldF, &newF };
	ecb.priv = &v;
	ecb.out_hunk = out_hunk;
	ecb.out_line = out_line;

	if (xdl_diff(&mf1, &mf2, &xpp, &xecfg, &ecb) < 0) {
		fprintf(stderr, "diff_bench: xdl_diff failed\n");
		return 1;
	}

	if (hunksOut)
		*hunksOut = v.hunks;
	// The roundtrip check below is the real correctness gate: for any
	// non-empty input, a silently-empty diff would fail the line-count
	// comparison.  hunks may legitimately be 0 for an empty vs. empty
	// pair (e.g. an empty file deleted between tree versions).
	if (v.oldLines != oldF.lines || v.oldDigest != oldF.digest ||
	    v.newLines != newF.lines || v.newDigest != newF.digest) {
		fprintf(stderr,
			"diff_bench: roundtrip mismatch on pass %d: "
			"old %llu/%llu lines digest %016llx/%016llx, "
			"new %llu/%llu lines digest %016llx/%016llx\n",
			pass,
			(unsigned long long)v.oldLines,
			(unsigned long long)oldF.lines,
			(unsigned long long)v.oldDigest,
			(unsigned long long)oldF.digest,
			(unsigned long long)v.newLines,
			(unsigned long long)newF.lines,
			(unsigned long long)v.newDigest,
			(unsigned long long)newF.digest);
		return 1;
	}
	return 0;
}

// --- tree mode: diff every changed file between two directories ----------

struct TreeStats {
	uint64_t files = 0;       // regular files examined (union of both trees)
	uint64_t diffed = 0;      // files actually diffed
	uint64_t identical = 0;   // byte-identical, skipped (like git)
	uint64_t binary = 0;      // skipped as binary (git's NUL heuristic)
	uint64_t hunks = 0;
	uint64_t oldLines = 0, newLines = 0;
};

static bool isDir(const std::string &p)
{
	struct stat st;
	return stat(p.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

static bool isReg(const std::string &p)
{
	struct stat st;
	return stat(p.c_str(), &st) == 0 && S_ISREG(st.st_mode);
}

// collectFiles - recursive listing of regular files under root/rel,
// deterministic (sorted) order.
static bool collectFiles(const std::string &root, const std::string &rel,
			 std::vector<std::string> &out)
{
	std::string dir = rel.empty() ? root : root + "/" + rel;
	DIR *d = opendir(dir.c_str());
	if (!d)
		return false;
	std::vector<std::string> names;
	struct dirent *e;
	while ((e = readdir(d))) {
		if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0)
			continue;
		names.push_back(e->d_name);
	}
	closedir(d);
	std::sort(names.begin(), names.end());
	for (const auto &n : names) {
		std::string r = rel.empty() ? n : rel + "/" + n;
		std::string full = root + "/" + r;
		if (isDir(full))
			collectFiles(root, r, out);
		else if (isReg(full))
			out.push_back(r);
	}
	return true;
}

// looksBinary - git's binary heuristic: a NUL byte in the first 8000 bytes.
static bool looksBinary(const File &f)
{
	size_t n = f.data.size() < 8000 ? f.data.size() : 8000;
	for (size_t i = 0; i < n; i++)
		if (f.data[i] == 0)
			return true;
	return false;
}

static bool filesEqual(const File &a, const File &b)
{
	return a.data.size() == b.data.size() &&
	       memcmp(a.data.data(), b.data.data(), a.data.size()) == 0;
}

// diffTree - one pass over the whole tree pair: diff every changed file,
// verify each roundtrip, accumulate stats.  Returns 0 on success.
static int diffTree(const std::string &oldDir, const std::string &newDir,
		    Algo algo, int pass, TreeStats *st)
{
	std::vector<std::string> oldFiles, newFiles;
	if (!collectFiles(oldDir, "", oldFiles) ||
	    !collectFiles(newDir, "", newFiles))
		return 1;

	size_t i = 0, j = 0;
	while (i < oldFiles.size() || j < newFiles.size()) {
		bool haveOld = i < oldFiles.size();
		bool haveNew = j < newFiles.size();
		int cmp = 0;
		if (haveOld && haveNew)
			cmp = oldFiles[i].compare(newFiles[j]);
		else
			cmp = haveOld ? -1 : 1;

		uint64_t h = 0;
		if (cmp == 0) {
			// present in both trees
			File a, b;
			if (!loadFile(oldDir + "/" + oldFiles[i], a) ||
			    !loadFile(newDir + "/" + newFiles[j], b))
				return 1;
			st->files++;
			if (filesEqual(a, b)) {
				st->identical++;
			} else if (looksBinary(a) || looksBinary(b)) {
				st->binary++;
			} else {
				if (diffPair(a, b, algo, pass, &h) != 0) {
					fprintf(stderr, "diff_bench: diff failed on %s\n",
						oldFiles[i].c_str());
					return 1;
				}
				st->diffed++;
				st->hunks += h;
				st->oldLines += a.lines;
				st->newLines += b.lines;
			}
			i++;
			j++;
		} else if (cmp < 0) {
			// deleted in new tree: diff against the empty file
			File a, empty;
			if (!loadFile(oldDir + "/" + oldFiles[i], a))
				return 1;
			st->files++;
			if (looksBinary(a)) {
				st->binary++;
			} else {
				if (diffPair(a, empty, algo, pass, &h) != 0)
					return 1;
				st->diffed++;
				st->hunks += h;
				st->oldLines += a.lines;
			}
			i++;
		} else {
			// added in new tree: diff the empty file against it
			File empty, b;
			if (!loadFile(newDir + "/" + newFiles[j], b))
				return 1;
			st->files++;
			if (looksBinary(b)) {
				st->binary++;
			} else {
				if (diffPair(empty, b, algo, pass, &h) != 0)
					return 1;
				st->diffed++;
				st->hunks += h;
				st->newLines += b.lines;
			}
			j++;
		}
	}
	return 0;
}

int main(int argc, char **argv)
{
	if (argc != 5) {
		fprintf(stderr,
			"usage: %s <myers|minimal|patience|histogram> "
			"<old_file|old_dir> <new_file|new_dir> <passes>\n",
			argv[0]);
		return 1;
	}
	Algo algo = parseAlgo(argv[1]);
	if ((int)algo < 0) {
		fprintf(stderr, "diff_bench: unknown algorithm '%s'\n", argv[1]);
		return 1;
	}
	int passes = atoi(argv[4]);
	if (passes < 1) {
		fprintf(stderr, "diff_bench: passes must be >= 1\n");
		return 1;
	}

	if (isDir(argv[2]) && isDir(argv[3])) {
		// tree mode: one pass = full diff of every changed file
		TreeStats st;
		for (int p = 1; p <= passes; p++) {
			TreeStats passSt;
			if (diffTree(argv[2], argv[3], algo, p, &passSt) != 0)
				return 1;
			st = passSt;
		}
		printf("diff_bench: %d %s pass%s done (tree: %llu files, "
		       "%llu diffed, %llu identical, %llu binary, %llu hunks, "
		       "old %llu lines, new %llu lines, roundtrip verified)\n",
		       passes, algoName(algo), passes == 1 ? "" : "es",
		       (unsigned long long)st.files,
		       (unsigned long long)st.diffed,
		       (unsigned long long)st.identical,
		       (unsigned long long)st.binary,
		       (unsigned long long)st.hunks,
		       (unsigned long long)st.oldLines,
		       (unsigned long long)st.newLines);
		return 0;
	}

	File oldF, newF;
	if (!loadFile(argv[2], oldF) || !loadFile(argv[3], newF)) {
		fprintf(stderr, "diff_bench: cannot load input files\n");
		return 1;
	}

	uint64_t hunks = 0;
	for (int p = 1; p <= passes; p++)
		if (diffPair(oldF, newF, algo, p, &hunks) != 0)
			return 1;

	printf("diff_bench: %d %s pass%s done (old %llu lines, new %llu lines, "
	       "%llu hunks, roundtrip verified)\n",
	       passes, algoName(algo), passes == 1 ? "" : "es",
	       (unsigned long long)oldF.lines,
	       (unsigned long long)newF.lines,
	       (unsigned long long)hunks);
	return 0;
}
