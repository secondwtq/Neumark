// gen_json.cpp - deterministic large JSON document generator for jq
// benchmarks.  One array of N objects: {"id", "name", "value", "tags"}.
//
// Usage: gen_json <N> <out.json>

#include <cstdint>
#include <cstdio>
#include <cstdlib>

static uint32_t hash1(uint32_t x)
{
	uint32_t h = x * 0x9E3779B9u;
	h ^= h >> 16;
	h *= 0x7FEB352Du;
	h ^= h >> 15;
	h *= 0x846CA68Bu;
	h ^= h >> 16;
	return h;
}

int main(int argc, char** argv)
{
	if (argc < 3)
	{
		fprintf(stderr, "usage: %s <N> <out.json>\n", argv[0]);
		return 1;
	}
	const int n = atoi(argv[1]);
	static const char* tags[] = {"alpha", "beta", "gamma", "delta", "eps", "zeta", "eta", "theta"};
	FILE* f = fopen(argv[2], "wb");
	if (!f)
		return 1;
	fprintf(f, "[\n");
	for (int i = 0; i < n; i++)
	{
		uint32_t h = hash1((uint32_t)i);
		fprintf(f, "{\"id\":%d,\"name\":\"item-%d\",\"value\":%u,\"tags\":[\"%s\",\"%s\"]}%s\n",
				i, i, h % 1000000u, tags[h % 8], tags[(h >> 8) % 8],
				i == n - 1 ? "" : ",");
	}
	fprintf(f, "]\n");
	fclose(f);
	fprintf(stderr, "gen_json: %d objects -> %s\n", n, argv[2]);
	return 0;
}
