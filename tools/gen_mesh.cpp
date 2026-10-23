// gen_mesh.cpp - deterministic mesh generator for meshoptimizer and
// RecastNavigation benchmarks.  Pure integer-hash value noise (no libm),
// so the mesh is bit-identical on any platform.
//
// Output format: if <out> ends in ".obj" -> standard Wavefront OBJ
//                ("v x y z" / "f a b c", 1-based indices); otherwise the
//                compact binary format: uint32 nverts, uint32 ntris,
//                float verts[nverts][3], uint32 indices[ntris][3]
//
// Usage: gen_mesh <grid_N> <out[.bin|.obj]> [scene]
//   scene: terrain (default) - plain heightfield
//          city - heightfield + buildings + floating slabs + ramps
//                 (multi-level geometry with overhangs/caves)

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static uint32_t hash2(uint32_t x, uint32_t z, uint32_t seed)
{
	uint32_t h = seed;
	h ^= x * 0x9E3779B9u;
	h ^= z * 0x85EBCA77u;
	h ^= h >> 16;
	h *= 0x7FEB352Du;
	h ^= h >> 15;
	h *= 0x846CA68Bu;
	h ^= h >> 16;
	return h;
}

// value noise with bilinear interpolation on an s x s lattice, range [0,1]
static float noise(float x, float z, uint32_t s, uint32_t seed)
{
	int lx = (int)(x / s);
	int lz = (int)(z / s);
	float fx = x / s - lx;
	float fz = z / s - lz;
	fx = fx * fx * (3.0f - 2.0f * fx);
	fz = fz * fz * (3.0f - 2.0f * fz);
	float n00 = (hash2(lx, lz, seed) & 0xFFFF) / 65535.0f;
	float n10 = (hash2(lx + 1, lz, seed) & 0xFFFF) / 65535.0f;
	float n01 = (hash2(lx, lz + 1, seed) & 0xFFFF) / 65535.0f;
	float n11 = (hash2(lx + 1, lz + 1, seed) & 0xFFFF) / 65535.0f;
	float n0 = n00 + (n10 - n00) * fx;
	float n1 = n01 + (n11 - n01) * fx;
	return n0 + (n1 - n0) * fz;
}

static uint32_t rngState = 0x13579BDFu;
static uint32_t rng()
{
	rngState = rngState * 1664525u + 1013904223u;
	return rngState;
}

// add a sloped ramp (walkable surface, 2 triangles) to the mesh buffers
static void addRamp(std::vector<float>& verts, std::vector<uint32_t>& indices,
					float cx, float cz, float len, float width, float h0, int dir)
{
	// dir 0: +x, 1: -x, 2: +z, 3: -z; rise = 0.5*len (slope ~27 deg < 45)
	const float rise = len * 0.5f;
	float dx = 0, dz = 0;
	switch (dir & 3)
	{
		case 0: dx = 1; break;
		case 1: dx = -1; break;
		case 2: dz = 1; break;
		default: dz = -1; break;
	}
	const float px = -dz, pz = dx;  // perpendicular
	uint32_t base = (uint32_t)(verts.size() / 3);
	const float v[4][3] = {
		{cx - px * width / 2, h0, cz - pz * width / 2},
		{cx + px * width / 2, h0, cz + pz * width / 2},
		{cx - px * width / 2 + dx * len, h0 + rise, cz - pz * width / 2 + dz * len},
		{cx + px * width / 2 + dx * len, h0 + rise, cz + pz * width / 2 + dz * len},
	};
	for (int i = 0; i < 4; i++)
	{
		verts.push_back(v[i][0]);
		verts.push_back(v[i][1]);
		verts.push_back(v[i][2]);
	}
	// winding so the normal points up
	indices.push_back(base + 0);
	indices.push_back(base + 2);
	indices.push_back(base + 1);
	indices.push_back(base + 1);
	indices.push_back(base + 2);
	indices.push_back(base + 3);
}

// add a box (4 walls + roof + floor) to the mesh buffers
static void addBox(std::vector<float>& verts, std::vector<uint32_t>& indices,
				   float cx, float cz, float w, float h, float baseY)
{
	uint32_t base = (uint32_t)(verts.size() / 3);
	float x0 = cx - w / 2, x1 = cx + w / 2;
	float z0 = cz - w / 2, z1 = cz + w / 2;
	float y0 = baseY, y1 = baseY + h;
	const float v[8][3] = {
		{x0, y0, z0}, {x1, y0, z0}, {x1, y0, z1}, {x0, y0, z1},
		{x0, y1, z0}, {x1, y1, z0}, {x1, y1, z1}, {x0, y1, z1},
	};
	for (int i = 0; i < 8; i++)
	{
		verts.push_back(v[i][0]);
		verts.push_back(v[i][1]);
		verts.push_back(v[i][2]);
	}
	const uint32_t t[12][3] = {
		{0, 1, 2}, {0, 2, 3},  // floor
		{4, 6, 5}, {4, 7, 6},  // roof
		{0, 5, 1}, {0, 4, 5},  // walls
		{1, 6, 2}, {1, 5, 6},
		{2, 7, 3}, {2, 6, 7},
		{3, 4, 0}, {3, 7, 4},
	};
	for (int i = 0; i < 12; i++)
	{
		indices.push_back(base + t[i][0]);
		indices.push_back(base + t[i][1]);
		indices.push_back(base + t[i][2]);
	}
}

int main(int argc, char** argv)
{
	if (argc < 3)
	{
		fprintf(stderr, "usage: %s <grid_N> <out.bin> [terrain|city]\n", argv[0]);
		return 1;
	}
	int n = atoi(argv[1]);
	if (n < 2)
		return 1;
	const char* scene = argc > 3 ? argv[3] : "terrain";
	bool city = strcmp(scene, "city") == 0;

	const uint32_t nverts = (uint32_t)n * n;
	const uint32_t ntris = (uint32_t)(n - 1) * (n - 1) * 2;
	const uint32_t nBoxes = city ? 215 : 0;             // 145 buildings + 70 slabs
	const uint32_t nRamps = city ? 55 : 0;
	// (the solo Recast navmesh caps at 65535 polys/verts - each box roof is
	//  its own region at ~220 verts - so the counts are tuned to the limit)
	const uint32_t extraVerts = nBoxes * 8 + nRamps * 4;
	const uint32_t extraTris = nBoxes * 12 + nRamps * 2;
	const uint32_t totVerts = nverts + extraVerts;
	const uint32_t totTris = ntris + extraTris;

	// height = 3 octaves of value noise (scales 256/64/16), amplitude 60
	std::vector<float> heights(nverts);
	for (int z = 0; z < n; z++)
	{
		for (int x = 0; x < n; x++)
		{
			float h = noise((float)x, (float)z, 256, 0x1234u) * 0.5f +
					  noise((float)x, (float)z, 64, 0x5678u) * 0.3f +
					  noise((float)x, (float)z, 16, 0x9ABCu) * 0.2f;
			heights[z * n + x] = (h - 0.5f) * 60.0f;
		}
	}

	// vertices: (x, height, z) with 1-unit spacing
	// (sized for the terrain only; city boxes append via push_back)
	std::vector<float> verts(nverts * 3);
	for (int z = 0; z < n; z++)
		for (int x = 0; x < n; x++)
		{
			verts[(z * n + x) * 3 + 0] = (float)x;
			verts[(z * n + x) * 3 + 1] = heights[z * n + x];
			verts[(z * n + x) * 3 + 2] = (float)z;
		}

	// indices: two triangles per grid cell (city boxes append via push_back)
	std::vector<uint32_t> indices(ntris * 3);
	uint32_t t = 0;
	for (int z = 0; z < n - 1; z++)
		for (int x = 0; x < n - 1; x++)
		{
			uint32_t a = z * n + x;
			uint32_t b = z * n + x + 1;
			uint32_t c = (z + 1) * n + x;
			uint32_t d = (z + 1) * n + x + 1;
			// winding: (a, c, b) / (b, c, d) so normals point up (+y)
			indices[t++] = a;
			indices[t++] = c;
			indices[t++] = b;
			indices[t++] = b;
			indices[t++] = c;
			indices[t++] = d;
		}

	if (city)
	{
		// 145 buildings on the terrain (walls + roofs = extra walkable level)
		for (int i = 0; i < 145; i++)
		{
			float cx = rng() % n;
			float cz = rng() % n;
			float w = 20.0f + (rng() % 60);
			float h = 30.0f + (rng() % 90);
			float baseY = heights[(int)cz * n + (int)cx];
			addBox(verts, indices, cx, cz, w, h, baseY);
		}
		// 70 floating slabs: overhangs / cave ceilings at various heights
		for (int i = 0; i < 70; i++)
		{
			float cx = rng() % n;
			float cz = rng() % n;
			float w = 40.0f + (rng() % 80);
			float baseY = 60.0f + (rng() % 80);
			addBox(verts, indices, cx, cz, w, 6.0f, baseY);
		}
		// 55 ramps: walkable slopes connecting levels (keep inside bounds)
		for (int i = 0; i < 55; i++)
		{
			float cx = 32 + rng() % (n - 64);
			float cz = 32 + rng() % (n - 64);
			float len = 60.0f + (rng() % 60);
			float width = 20.0f + (rng() % 40);
			float h0 = 10.0f + (rng() % 60);
			int dir = (int)(rng() % 4);
			addRamp(verts, indices, cx, cz, len, width, h0, dir);
		}
	}

	FILE* f = fopen(argv[2], "wb");
	if (!f)
		return 1;
	const bool asObj = strstr(argv[2], ".obj") != nullptr;
	if (asObj)
	{
		for (uint32_t i = 0; i < totVerts; i++)
			fprintf(f, "v %.6f %.6f %.6f\n", verts[i * 3], verts[i * 3 + 1], verts[i * 3 + 2]);
		for (uint32_t i = 0; i < totTris; i++)
			fprintf(f, "f %u %u %u\n", indices[i * 3] + 1, indices[i * 3 + 1] + 1, indices[i * 3 + 2] + 1);
	}
	else
	{
		fwrite(&totVerts, 4, 1, f);
		fwrite(&totTris, 4, 1, f);
		fwrite(verts.data(), 12, totVerts, f);
		fwrite(indices.data(), 12, totTris, f);
	}
	fclose(f);

	fprintf(stderr, "gen_mesh: %u verts, %u tris (%s) -> %s\n", totVerts, totTris, scene, argv[2]);
	return 0;
}
