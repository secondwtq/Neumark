// gen_dot.cpp - deterministic large DOT graph generator for graphviz
// benchmarks.  Layered digraph: <layers> layers of <per> nodes, chain +
// skip + cross edges (all deterministic).
//
// Usage: gen_dot <layers> <per_layer> <out.dot> [mode]  (mode 0: cross edges, 1: clean)

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
	if (argc < 4)
	{
		fprintf(stderr, "usage: %s <layers> <per_layer> <out.dot>\n", argv[0]);
		return 1;
	}
	const int layers = atoi(argv[1]);
	const int per = atoi(argv[2]);
	const int n = layers * per;
	FILE* f = fopen(argv[3], "wb");
	if (!f)
		return 1;
	fprintf(f, "digraph g {\n");
	for (int l = 0; l < layers; l++)
		for (int p = 0; p < per; p++)
			fprintf(f, "  n%d_l%d;\n", p, l);
	for (int l = 0; l < layers - 1; l++)
	{
		for (int p = 0; p < per; p++)
		{
			// chain edge to the next layer
			fprintf(f, "  n%d_l%d -> n%d_l%d;\n", p, l, p, l + 1);
			// skip edge (to the layer after next)
			if (l + 2 < layers)
				fprintf(f, "  n%d_l%d -> n%d_l%d;\n", p, l, (p + 1) % per, l + 2);
			// deterministic cross edges (mode 0 only)
			if (argc > 4 && atoi(argv[4]) == 0)
			{
				uint32_t h = hash1((uint32_t)(p * 31 + l * 17));
				if ((h & 3) == 0 && l + 1 < layers)
					fprintf(f, "  n%d_l%d -> n%d_l%d;\n", p, l, (int)(h >> 8) % per, l + 1);
			}
		}
	}
	fprintf(f, "}\n");
	fclose(f);
	fprintf(stderr, "gen_dot: %d nodes (%d layers x %d) -> %s\n", n, layers, per, argv[3]);
	return 0;
}
