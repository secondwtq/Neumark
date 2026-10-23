// meshopt_bench.cpp - headless meshoptimizer benchmark harness.
//
// Four workloads, one binary (all deterministic, single-threaded):
//   simplify:      meshopt_simplify to 50% triangle count, K times
//   optimize:      vertex-cache + overdraw + vertex-fetch optimization
//                  pipeline, K times
//   codec_encode:  meshopt_encodeIndexBuffer + encodeVertexBuffer, K times
//   codec_decode:  encode once up front, then decode both buffers K times
//                  (output verified byte-exact against the originals once
//                  at startup)
//
// Usage: meshopt_bench <simplify|optimize|codec_encode|codec_decode>
//                      <mesh.bin> <iterations>

#include "meshoptimizer.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static bool loadMesh(const char* path, std::vector<float>& verts,
					 std::vector<unsigned int>& indices)
{
	FILE* f = fopen(path, "rb");
	if (!f)
		return false;
	uint32_t nverts = 0, ntris = 0;
	if (fread(&nverts, 4, 1, f) != 1 || fread(&ntris, 4, 1, f) != 1)
		return false;
	verts.resize((size_t)nverts * 3);
	indices.resize((size_t)ntris * 3);
	if (fread(verts.data(), 12, nverts, f) != nverts)
		return false;
	if (fread(indices.data(), 12, ntris, f) != ntris)
		return false;
	fclose(f);
	return true;
}

static int runSimplify(const std::vector<float>& verts,
					   const std::vector<unsigned int>& indices, int iters)
{
	const size_t index_count = indices.size();
	std::vector<unsigned int> dest(index_count);
	float error = 0;
	for (int i = 0; i < iters; i++)
	{
		size_t res = meshopt_simplify(dest.data(), indices.data(), index_count,
									  verts.data(), verts.size() / 3, 12,
									  index_count / 2, 1e-2f, 0, &error);
		if (res == 0)
		{
			fprintf(stderr, "simplify iteration %d failed\n", i);
			return 1;
		}
	}
	printf("meshopt_bench: %d simplify passes done (error %.4f)\n", iters, error);
	return 0;
}

static int runOptimize(const std::vector<float>& verts,
					   const std::vector<unsigned int>& indices, int iters)
{
	const size_t index_count = indices.size();
	const size_t vertex_count = verts.size() / 3;
	std::vector<unsigned int> tmp0(index_count), tmp1(index_count);
	std::vector<float> vtmp(verts.size());
	for (int i = 0; i < iters; i++)
	{
		// vertex cache -> overdraw -> vertex fetch (the classic pipeline)
		meshopt_optimizeVertexCache(tmp0.data(), indices.data(), index_count, vertex_count);
		meshopt_optimizeOverdraw(tmp1.data(), tmp0.data(), index_count,
								 verts.data(), vertex_count, 12, 1.01f);
		meshopt_optimizeVertexFetch(vtmp.data(), tmp1.data(), index_count,
									verts.data(), vertex_count, 12);
	}
	printf("meshopt_bench: %d optimize passes done\n", iters);
	return 0;
}

static int runCodecEncode(const std::vector<float>& verts,
						  const std::vector<unsigned int>& indices, int iters)
{
	const size_t index_count = indices.size();
	const size_t vertex_count = verts.size() / 3;
	const size_t ibound = meshopt_encodeIndexBufferBound(index_count, 4);
	const size_t vbound = meshopt_encodeVertexBufferBound(vertex_count, 12);
	std::vector<unsigned char> ibuf(ibound), vbuf(vbound);
	size_t isize = 0, vsize = 0;
	for (int i = 0; i < iters; i++)
	{
		isize = meshopt_encodeIndexBuffer(ibuf.data(), ibuf.size(),
										  indices.data(), index_count);
		vsize = meshopt_encodeVertexBuffer(vbuf.data(), vbuf.size(),
										   verts.data(), vertex_count, 12);
	}
	printf("meshopt_bench: %d codec encode passes done (index %zu B, vertex %zu B)\n",
		   iters, isize, vsize);
	return 0;
}

static int runCodecDecode(const std::vector<float>& verts,
						  const std::vector<unsigned int>& indices, int iters)
{
	const size_t index_count = indices.size();
	const size_t vertex_count = verts.size() / 3;
	const size_t ibound = meshopt_encodeIndexBufferBound(index_count, 4);
	const size_t vbound = meshopt_encodeVertexBufferBound(vertex_count, 12);
	std::vector<unsigned char> ibuf(ibound), vbuf(vbound);
	size_t isize = meshopt_encodeIndexBuffer(ibuf.data(), ibuf.size(),
											 indices.data(), index_count);
	size_t vsize = meshopt_encodeVertexBuffer(vbuf.data(), vbuf.size(),
											  verts.data(), vertex_count, 12);

	// verify decode once against the originals
	std::vector<unsigned int> idec(index_count);
	std::vector<float> vdec(verts.size());
	int irc = meshopt_decodeIndexBuffer(idec.data(), index_count, 4, ibuf.data(), isize);
	int vrc = meshopt_decodeVertexBuffer(vdec.data(), vertex_count, 12, vbuf.data(), vsize);
	// the codec preserves triangle order but may rotate each triangle
	// (README: "it can rotate each triangle to improve compression ratio")
	bool iok = true;
	for (size_t t = 0; t < index_count / 3 && iok; t++)
	{
		unsigned a0 = indices[t * 3 + 0], b0 = indices[t * 3 + 1], c0 = indices[t * 3 + 2];
		unsigned a1 = idec[t * 3 + 0], b1 = idec[t * 3 + 1], c1 = idec[t * 3 + 2];
		iok = (a1 == a0 && b1 == b0 && c1 == c0) ||
			  (a1 == b0 && b1 == c0 && c1 == a0) ||
			  (a1 == c0 && b1 == a0 && c1 == b0);
	}
	bool vok = memcmp(vdec.data(), verts.data(), verts.size() * 4) == 0;
	if (irc != 0 || vrc != 0 || !iok || !vok)
	{
		fprintf(stderr, "codec roundtrip mismatch: idec=%d vdec=%d idx=%d vtx=%d\n", irc, vrc, iok, vok);
		return 1;
	}

	for (int i = 0; i < iters; i++)
	{
		meshopt_decodeIndexBuffer(idec.data(), index_count, 4, ibuf.data(), isize);
		meshopt_decodeVertexBuffer(vdec.data(), vertex_count, 12, vbuf.data(), vsize);
	}
	printf("meshopt_bench: %d codec decode passes done\n", iters);
	return 0;
}

int main(int argc, char** argv)
{
	if (argc < 4)
	{
		fprintf(stderr,
				"usage: %s <simplify|optimize|codec_encode|codec_decode> <mesh.bin> <iterations>\n",
				argv[0]);
		return 1;
	}

	std::vector<float> verts;
	std::vector<unsigned int> indices;
	if (!loadMesh(argv[2], verts, indices))
	{
		fprintf(stderr, "failed to load %s\n", argv[2]);
		return 1;
	}
	fprintf(stderr, "mesh: %zu verts, %zu tris\n", verts.size() / 3, indices.size() / 3);

	const int iters = atoi(argv[3]);
	if (strcmp(argv[1], "simplify") == 0)
		return runSimplify(verts, indices, iters);
	if (strcmp(argv[1], "optimize") == 0)
		return runOptimize(verts, indices, iters);
	if (strcmp(argv[1], "codec_encode") == 0)
		return runCodecEncode(verts, indices, iters);
	if (strcmp(argv[1], "codec_decode") == 0)
		return runCodecDecode(verts, indices, iters);
	fprintf(stderr, "unknown mode %s\n", argv[1]);
	return 1;
}
