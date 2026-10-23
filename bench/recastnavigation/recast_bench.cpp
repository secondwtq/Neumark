// recast_bench.cpp - headless RecastNavigation benchmark harness.
//
// Three workloads, one binary:
//   build:  full Recast navmesh-building pipeline (rasterization, filters,
//           watershed regions, contours, poly mesh, detail mesh, Detour
//           navmesh) run N times on the input .obj mesh.
//   path:   build once, then M deterministic dtNavMeshQuery findPath +
//           findStraightPath queries between seeded-random points.
//   crowd:  build once, then run a dtCrowd simulation of A agents for F
//           frames (obstacle avoidance + path following).
//
// Uses only the project libraries (Recast/Detour/DetourCrowd) - no demo
// GUI code, fully headless.  All RNG is seeded -> reproducible runs.
//
// Usage: recast_bench <build|path|crowd> <mesh> <counts...> [cs] [ch]
//   build: recast_bench build <mesh> <builds> [cs] [ch]
//   path:  recast_bench path  <mesh> <queries> [cs] [ch]
//   crowd: recast_bench crowd <mesh> <agents> <frames> [cs] [ch]
// [cs] [ch] override the default 0.3/0.2 navmesh cell size / cell height
// (higher resolution = smaller values).

#include "Recast.h"
#include "DetourNavMesh.h"
#include "DetourNavMeshQuery.h"
#include "DetourNavMeshBuilder.h"
#include "DetourCrowd.h"

#include <cstdio>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>

// ---------------- minimal .obj loader (v + f lines) ---------------------

static bool loadObj(const char* path, std::vector<float>& verts,
					std::vector<int>& tris, float bmin[3], float bmax[3])
{
	FILE* f = fopen(path, "r");
	if (!f)
		return false;
	char line[512];
	int idx = 0;
	bmin[0] = bmin[1] = bmin[2] = 1e30f;
	bmax[0] = bmax[1] = bmax[2] = -1e30f;
	while (fgets(line, sizeof(line), f))
	{
		if (line[0] == 'v' && line[1] == ' ')
		{
			float x, y, z;
			if (sscanf(line + 2, "%f %f %f", &x, &y, &z) == 3)
			{
				verts.push_back(x);
				verts.push_back(y);
				verts.push_back(z);
				for (int k = 0; k < 3; k++)
				{
					float v = (k == 0) ? x : (k == 1) ? y : z;
					if (v < bmin[k]) bmin[k] = v;
					if (v > bmax[k]) bmax[k] = v;
				}
			}
		}
		else if (line[0] == 'f' && line[1] == ' ')
		{
			// supports "f a b c", "f a/b c/d e/f", "f a//b c//d e//f", quads
			int v[4] = {0, 0, 0, 0};
			int n = sscanf(line + 2, "%d/%*d/%*d %d/%*d/%*d %d/%*d/%*d %d/%*d/%*d",
						  &v[0], &v[1], &v[2], &v[3]);
			if (n < 3)
				n = sscanf(line + 2, "%d/%*d %d/%*d %d/%*d %d/%*d", &v[0], &v[1], &v[2], &v[3]);
			if (n < 3)
				n = sscanf(line + 2, "%d %d %d %d", &v[0], &v[1], &v[2], &v[3]);
			if (n >= 3)
			{
				tris.push_back(v[0] - 1);
				tris.push_back(v[1] - 1);
				tris.push_back(v[2] - 1);
				idx++;
				if (n == 4)
				{
					tris.push_back(v[0] - 1);
					tris.push_back(v[2] - 1);
					tris.push_back(v[3] - 1);
					idx++;
				}
			}
		}
	}
	fclose(f);
	return idx > 0;
}

// ---------------- binary mesh loader (gen_mesh format) ----------------------

static bool loadBinMesh(const char* path, std::vector<float>& verts,
						std::vector<int>& tris, float bmin[3], float bmax[3])
{
	FILE* f = fopen(path, "rb");
	if (!f)
		return false;
	uint32_t nverts = 0, ntris = 0;
	if (fread(&nverts, 4, 1, f) != 1 || fread(&ntris, 4, 1, f) != 1)
		return false;
	verts.resize((size_t)nverts * 3);
	tris.resize((size_t)ntris * 3);
	if (fread(verts.data(), 12, nverts, f) != nverts)
		return false;
	if (fread(tris.data(), 12, ntris, f) != ntris)
		return false;
	fclose(f);
	bmin[0] = bmin[1] = bmin[2] = 1e30f;
	bmax[0] = bmax[1] = bmax[2] = -1e30f;
	for (size_t i = 0; i < verts.size(); i += 3)
		for (int k = 0; k < 3; k++)
		{
			if (verts[i + k] < bmin[k]) bmin[k] = verts[i + k];
			if (verts[i + k] > bmax[k]) bmax[k] = verts[i + k];
		}
	return true;
}

// ---------------- mesh tiling -------------------------------------------------

static void tileMesh(const std::vector<float>& srcVerts, const std::vector<int>& srcTris,
					 const float bmin[3], const float bmax[3], int tiles,
					 std::vector<float>& verts, std::vector<int>& tris)
{
	verts.clear();
	tris.clear();
	verts.reserve(srcVerts.size() * tiles * tiles);
	tris.reserve(srcTris.size() * tiles * tiles);
	const float spanX = bmax[0] - bmin[0] + 2.0f;
	const float spanZ = bmax[2] - bmin[2] + 2.0f;
	const int nsrc = (int)srcVerts.size() / 3;
	for (int tx = 0; tx < tiles; tx++)
	{
		for (int tz = 0; tz < tiles; tz++)
		{
			const float offx = tx * spanX;
			const float offz = tz * spanZ;
			const int base = (int)verts.size() / 3;
			for (int i = 0; i < nsrc; i++)
			{
				verts.push_back(srcVerts[i * 3 + 0] + offx);
				verts.push_back(srcVerts[i * 3 + 1]);
				verts.push_back(srcVerts[i * 3 + 2] + offz);
			}
			for (size_t i = 0; i < srcTris.size(); i++)
				tris.push_back(srcTris[i] + base);
		}
	}
}

// ---------------- navmesh build (Sample_SoloMesh pipeline) ----------------

static dtNavMesh* buildNavMesh(rcContext* ctx, const std::vector<float>& verts,
							   const std::vector<int>& tris, const float meshMin[3],
							   const float meshMax[3], float cs, float ch)
{
	rcConfig cfg;
	memset(&cfg, 0, sizeof(cfg));
	cfg.cs = cs;
	cfg.ch = ch;
	cfg.walkableSlopeAngle = 45.0f;
	// agent metrics in world units; voxel params derived as in Sample_SoloMesh
	const float agentHeight = 2.0f;
	const float agentRadius = 0.6f;
	const float agentMaxClimb = 0.9f;
	cfg.walkableHeight = (int)ceilf(agentHeight / cfg.ch);
	cfg.walkableClimb = (int)ceilf(agentMaxClimb / cfg.ch);
	cfg.walkableRadius = (int)ceilf(agentRadius / cfg.cs);
	cfg.maxEdgeLen = 12;
	cfg.maxSimplificationError = 1.3f;
	cfg.minRegionArea = 8;
	cfg.mergeRegionArea = 20;
	cfg.maxVertsPerPoly = 6;
	cfg.detailSampleDist = 6.0f;
	cfg.detailSampleMaxError = 1.0f;
	rcVcopy(cfg.bmin, meshMin);
	rcVcopy(cfg.bmax, meshMax);
	rcCalcGridSize(cfg.bmin, cfg.bmax, cfg.cs, &cfg.width, &cfg.height);

	const int nverts = (int)verts.size() / 3;
	const int ntris = (int)tris.size() / 3;

	// heightfield
	rcHeightfield* solid = rcAllocHeightfield();
	if (!solid || !rcCreateHeightfield(ctx, *solid, cfg.width, cfg.height, cfg.bmin, cfg.bmax, cfg.cs, cfg.ch))
	{ fprintf(stderr, "  stage: heightfield failed (grid %dx%d)\n", cfg.width, cfg.height); return nullptr; }

	std::vector<unsigned char> triareas(ntris);
	rcMarkWalkableTriangles(ctx, cfg.walkableSlopeAngle, verts.data(), nverts,
							tris.data(), ntris, triareas.data());
	if (!rcRasterizeTriangles(ctx, verts.data(), nverts, tris.data(), triareas.data(), ntris,
							  *solid, cfg.walkableClimb))
	{ fprintf(stderr, "  stage: rasterize failed\n"); return nullptr; }
	rcFilterLowHangingWalkableObstacles(ctx, cfg.walkableClimb, *solid);
	rcFilterLedgeSpans(ctx, cfg.walkableHeight, cfg.walkableClimb, *solid);
	rcFilterWalkableLowHeightSpans(ctx, cfg.walkableHeight, *solid);

	// compact heightfield + erosion
	rcCompactHeightfield* chf = rcAllocCompactHeightfield();
	if (!chf || !rcBuildCompactHeightfield(ctx, cfg.walkableHeight, cfg.walkableClimb, *solid, *chf))
	{ fprintf(stderr, "  stage: compact heightfield failed\n"); return nullptr; }
	rcFreeHeightField(solid);
	if (!rcErodeWalkableArea(ctx, cfg.walkableRadius, *chf))
	{ fprintf(stderr, "  stage: erosion failed\n"); return nullptr; }

	// watershed partitioning
	{
		int walkable = 0;
		for (int i = 0; i < chf->spanCount; i++)
			if (chf->areas[i] != RC_NULL_AREA)
				walkable++;
	}
	if (!rcBuildDistanceField(ctx, *chf))
	{ fprintf(stderr, "  stage: distance field failed\n"); return nullptr; }
	{
		int sentinel = 0;
		for (int i = 0; i < chf->spanCount; i++)
			if (chf->dist[i] == 0xffff)
				sentinel++;
	}
	if (!rcBuildRegions(ctx, *chf, 0, cfg.minRegionArea, cfg.mergeRegionArea))
	{ fprintf(stderr, "  stage: regions failed\n"); return nullptr; }
	{
		int regged = 0;
		for (int i = 0; i < chf->spanCount; i++)
			if (chf->spans[i].reg != 0)
				regged++;
	}

	// contours + poly mesh + detail mesh
	rcContourSet* cset = rcAllocContourSet();
	if (!cset || !rcBuildContours(ctx, *chf, cfg.maxSimplificationError, cfg.maxEdgeLen,
								  *cset, RC_CONTOUR_TESS_WALL_EDGES | RC_CONTOUR_TESS_AREA_EDGES))
	{ fprintf(stderr, "  stage: contours failed\n"); return nullptr; }

	rcPolyMesh* pmesh = rcAllocPolyMesh();
	if (!pmesh || !rcBuildPolyMesh(ctx, *cset, cfg.maxVertsPerPoly, *pmesh))
	{ fprintf(stderr, "  stage: poly mesh failed\n"); return nullptr; }

	rcPolyMeshDetail* dmesh = rcAllocPolyMeshDetail();
	if (!dmesh || !rcBuildPolyMeshDetail(ctx, *pmesh, *chf, cfg.detailSampleDist,
										 cfg.detailSampleMaxError, *dmesh))
	{ fprintf(stderr, "  stage: detail mesh failed\n"); return nullptr; }

	rcFreeCompactHeightfield(chf);
	rcFreeContourSet(cset);

	// Update poly flags from areas (as Sample_SoloMesh does).
	for (int i = 0; i < pmesh->npolys; ++i)
	{
		if (pmesh->areas[i] == RC_WALKABLE_AREA)
			pmesh->areas[i] = 1;  // SAMPLE_POLYAREA_GROUND
		if (pmesh->areas[i] == 1 || pmesh->areas[i] == 2 || pmesh->areas[i] == 3)
			pmesh->flags[i] = 0x01;  // SAMPLE_POLYFLAGS_WALK
		else if (pmesh->areas[i] == 4)
			pmesh->flags[i] = 0x02;  // SWIM
		else if (pmesh->areas[i] == 5)
			pmesh->flags[i] = 0x01 | 0x04;  // WALK | DOOR
	}

	// Detour navmesh
	dtNavMeshCreateParams params;
	memset(&params, 0, sizeof(params));
	params.verts = pmesh->verts;
	params.vertCount = pmesh->nverts;
	params.polys = pmesh->polys;
	params.polyAreas = pmesh->areas;
	params.polyFlags = pmesh->flags;
	params.polyCount = pmesh->npolys;
	params.nvp = pmesh->nvp;
	params.detailMeshes = dmesh->meshes;
	params.detailVerts = dmesh->verts;
	params.detailVertsCount = dmesh->nverts;
	params.detailTris = dmesh->tris;
	params.detailTriCount = dmesh->ntris;
	params.walkableHeight = agentHeight;
	params.walkableRadius = agentRadius;
	params.walkableClimb = agentMaxClimb;
	rcVcopy(params.bmin, pmesh->bmin);
	rcVcopy(params.bmax, pmesh->bmax);
	params.cs = cfg.cs;
	params.ch = cfg.ch;
	params.buildBvTree = true;

	fprintf(stderr, "  polymesh: %d verts, %d polys\n", pmesh->nverts, pmesh->npolys);
	unsigned char* navData = nullptr;
	int navDataSize = 0;
	if (!dtCreateNavMeshData(&params, &navData, &navDataSize))
	{ fprintf(stderr, "  stage: dtCreateNavMeshData failed\n"); return nullptr; }
	fprintf(stderr, "  navmesh: %d polys, %d verts, %d detail tris\n",
			pmesh->npolys, pmesh->nverts, dmesh->ntris);

	dtNavMesh* nav = dtAllocNavMesh();
	if (!nav || dtStatusFailed(nav->init(navData, navDataSize, DT_TILE_FREE_DATA)))
		return nullptr;

	rcFreePolyMesh(pmesh);
	rcFreePolyMeshDetail(dmesh);
	return nav;
}

// ---------------- rcContext that surfaces build errors -----------------------

struct LogContext : rcContext
{
	LogContext() : rcContext(true) {}
protected:
	void doLog(const rcLogCategory category, const char* msg, const int len) override
	{
		if (category == RC_LOG_ERROR)
			fprintf(stderr, "recast: %.*s\n", len, msg);
	}
};

// ---------------- deterministic RNG ---------------------------------------

static uint32_t rngState = 0x9e3779b9u;
static float frand()
{
	rngState = rngState * 1664525u + 1013904223u;
	return (float)(rngState >> 8) / (float)(1 << 24);
}

// ---------------- workloads ------------------------------------------------

static int runBuild(rcContext* ctx, const std::vector<float>& verts,
					const std::vector<int>& tris, const float bmin[3],
					const float bmax[3], int builds, float cs, float ch)
{
	for (int i = 0; i < builds; i++)
	{
		dtNavMesh* nav = buildNavMesh(ctx, verts, tris, bmin, bmax, cs, ch);
		if (!nav)
		{
			fprintf(stderr, "build %d failed\n", i);
			return 1;
		}
		dtFreeNavMesh(nav);
	}
	printf("recast_bench: %d navmesh builds done\n", builds);
	return 0;
}

static int runPath(rcContext* ctx, const std::vector<float>& verts,
				   const std::vector<int>& tris, const float bmin[3],
				   const float bmax[3], int queries, float cs, float ch)
{
	dtNavMesh* nav = buildNavMesh(ctx, verts, tris, bmin, bmax, cs, ch);
	if (!nav)
		return 1;
	dtNavMeshQuery* query = dtAllocNavMeshQuery();
	if (!query || dtStatusFailed(query->init(nav, 2048)))
		return 1;

	dtQueryFilter filter;
	filter.setIncludeFlags(0xFFFF);
	filter.setExcludeFlags(0);
	const float ext[3] = {2.0f, 4.0f, 2.0f};

	// pool of walkable points (sampled with the engine's own findRandomPoint)
	const int poolSize = 4096;
	std::vector<float> pool(poolSize * 3);
	std::vector<dtPolyRef> poolRef(poolSize);
	int poolN = 0;
	for (int i = 0; i < poolSize; i++)
	{
		dtPolyRef ref;
		float pt[3];
		if (dtStatusSucceed(query->findRandomPoint(&filter, frand, &ref, pt)) && ref)
		{
			poolRef[poolN] = ref;
			pool[poolN * 3 + 0] = pt[0];
			pool[poolN * 3 + 1] = pt[1];
			pool[poolN * 3 + 2] = pt[2];
			poolN++;
		}
	}

	int resolved = 0;
	for (int i = 0; i < queries; i++)
	{
		const int si = (int)(frand() * poolN) % poolN;
		const int ei = (int)(frand() * poolN) % poolN;
		const float* sp = &pool[si * 3];
		const float* ep = &pool[ei * 3];

		dtPolyRef sref, eref;
		float sn[3], en[3];
		if (dtStatusFailed(query->findNearestPoly(sp, ext, &filter, &sref, sn)))
			continue;
		if (dtStatusFailed(query->findNearestPoly(ep, ext, &filter, &eref, en)))
			continue;

		dtPolyRef path[256];
		int npath = 0;
		if (dtStatusFailed(query->findPath(sref, eref, sn, en, &filter, path, &npath, 256)))
			continue;
		if (npath > 0)
		{
			float straight[256 * 3];
			unsigned char flags[256];
			dtPolyRef refs[256];
			int nstraight = 0;
			query->findStraightPath(sn, en, path, npath, straight, flags, refs, &nstraight, 256);
			resolved++;
		}
	}

	dtFreeNavMeshQuery(query);
	dtFreeNavMesh(nav);
	printf("recast_bench: %d path queries done (%d resolved)\n", queries, resolved);
	return 0;
}

static int runCrowd(rcContext* ctx, const std::vector<float>& verts,
					const std::vector<int>& tris, const float bmin[3],
					const float bmax[3], int agents, int frames, float cs, float ch)
{
	dtNavMesh* nav = buildNavMesh(ctx, verts, tris, bmin, bmax, cs, ch);
	if (!nav)
		return 1;

	dtCrowd* crowd = dtAllocCrowd();
	if (!crowd || !crowd->init(agents, 0.6f, nav))
		return 1;

	dtNavMeshQuery* query = dtAllocNavMeshQuery();
	if (!query || dtStatusFailed(query->init(nav, 2048)))
		return 1;
	dtQueryFilter filter;
	filter.setIncludeFlags(0xFFFF);
	const float ext[3] = {2.0f, 4.0f, 2.0f};
	const float topY = bmin[1] + 2.0f;  // just above the floor

	dtCrowdAgentParams ap;
	memset(&ap, 0, sizeof(ap));
	ap.radius = 0.6f;
	ap.height = 2.0f;
	ap.maxAcceleration = 8.0f;
	ap.maxSpeed = 3.5f;
	ap.collisionQueryRange = 12.0f;
	ap.pathOptimizationRange = 30.0f;
	ap.separationWeight = 2.0f;
	ap.updateFlags = DT_CROWD_ANTICIPATE_TURNS | DT_CROWD_OBSTACLE_AVOIDANCE |
					 DT_CROWD_SEPARATION | DT_CROWD_OPTIMIZE_VIS | DT_CROWD_OPTIMIZE_TOPO;

	// scatter agents at walkable random points; each gets a walkable target
	for (int i = 0; i < agents; i++)
	{
		float pos[3];
		dtPolyRef ref;
		if (dtStatusFailed(query->findRandomPoint(&filter, frand, &ref, pos)) || !ref)
			continue;
		int idx = crowd->addAgent(pos, &ap);
		if (idx == -1)
			continue;

		float tpos[3];
		dtPolyRef tref;
		if (dtStatusSucceed(query->findRandomPoint(&filter, frand, &tref, tpos)) && tref)
			crowd->requestMoveTarget(idx, tref, tpos);
	}

	const float dt = 1.0f / 60.0f;
	for (int i = 0; i < frames; i++)
	{
		crowd->update(dt, nullptr);
	}

	int active = 0;
	for (int i = 0; i < crowd->getAgentCount(); i++)
	{
		const dtCrowdAgent* a = crowd->getAgent(i);
		if (a && a->active)
			active++;
	}

	dtFreeCrowd(crowd);
	dtFreeNavMeshQuery(query);
	dtFreeNavMesh(nav);
	printf("recast_bench: crowd sim done: %d agents, %d frames (%d active)\n", agents, frames, active);
	return 0;
}

int main(int argc, char** argv)
{
	if (argc < 4)
	{
		fprintf(stderr,
				"usage: %s <build|path|crowd> <mesh.obj> <counts...>\n"
				"  build: %s build <mesh.obj> <builds>\n"
				"  path:  %s path  <mesh.obj> <queries>\n"
				"  crowd: %s crowd <mesh.obj> <agents> <frames>\n",
				argv[0], argv[0], argv[0], argv[0]);
		return 1;
	}

	std::vector<float> verts;
	std::vector<int> tris;
	float bmin[3], bmax[3];
	bool ok = strstr(argv[2], ".bin") ? loadBinMesh(argv[2], verts, tris, bmin, bmax)
									  : loadObj(argv[2], verts, tris, bmin, bmax);
	if (!ok)
	{
		fprintf(stderr, "failed to load %s\n", argv[2]);
		return 1;
	}

	int tiles = 1;
	if (strcmp(argv[1], "crowd") == 0)
		tiles = argc > 5 ? atoi(argv[5]) : 1;   // crowd <agents> <frames> [tiles]
	else
		tiles = argc > 4 ? atoi(argv[4]) : 1;   // build/path <count> [tiles]
	if (tiles > 1)
	{
		std::vector<float> tverts;
		std::vector<int> ttris;
		tileMesh(verts, tris, bmin, bmax, tiles, tverts, ttris);
		verts.swap(tverts);
		tris.swap(ttris);
		// recompute bounds from the tiled vertices
		bmin[0] = bmin[1] = bmin[2] = 1e30f;
		bmax[0] = bmax[1] = bmax[2] = -1e30f;
		for (size_t i = 0; i < verts.size(); i += 3)
			for (int k = 0; k < 3; k++)
			{
				if (verts[i + k] < bmin[k]) bmin[k] = verts[i + k];
				if (verts[i + k] > bmax[k]) bmax[k] = verts[i + k];
			}
	}

	LogContext ctx;
	fprintf(stderr, "mesh: %d verts, %d tris (tiles=%d)\n",
			(int)verts.size() / 3, (int)tris.size() / 3, tiles);
	// optional trailing [cs] [ch] override the default 0.3/0.2 navmesh resolution
	float cs = 0.3f;
	float ch = 0.2f;
	if (strcmp(argv[1], "build") == 0 && argc > 5)
	{ cs = (float)atof(argv[4]); ch = (float)atof(argv[5]); }
	else if (strcmp(argv[1], "path") == 0 && argc > 5)
	{ cs = (float)atof(argv[4]); ch = (float)atof(argv[5]); }
	else if (strcmp(argv[1], "crowd") == 0 && argc > 6)
	{ cs = (float)atof(argv[5]); ch = (float)atof(argv[6]); }

	int rc = 0;
	if (strcmp(argv[1], "build") == 0)
		rc = runBuild(&ctx, verts, tris, bmin, bmax, atoi(argv[3]), cs, ch);
	else if (strcmp(argv[1], "path") == 0)
		rc = runPath(&ctx, verts, tris, bmin, bmax, atoi(argv[3]), cs, ch);
	else if (strcmp(argv[1], "crowd") == 0)
		rc = runCrowd(&ctx, verts, tris, bmin, bmax, atoi(argv[3]), argc > 4 ? atoi(argv[4]) : 600, cs, ch);
	else
	{
		fprintf(stderr, "unknown mode %s\n", argv[1]);
		return 1;
	}
	return rc;
}
