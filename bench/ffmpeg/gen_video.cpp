// gen_video.c - deterministic Y4M (YUV420p) video generator for ffmpeg
// benchmarks.  Integer-hash value noise with per-frame motion - the same
// content on every platform/regeneration.
//
// Usage: gen_video <width> <height> <frames> <out.y4m>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>

static uint32_t hash2(uint32_t x, uint32_t y, uint32_t seed)
{
	uint32_t h = seed;
	h ^= x * 0x9E3779B9u;
	h ^= y * 0x85EBCA77u;
	h ^= h >> 16;
	h *= 0x7FEB352Du;
	h ^= h >> 15;
	h *= 0x846CA68Bu;
	h ^= h >> 16;
	return h;
}

int main(int argc, char** argv)
{
	if (argc < 5)
	{
		fprintf(stderr, "usage: %s <width> <height> <frames> <out.y4m>\n", argv[0]);
		return 1;
	}
	const int w = atoi(argv[1]);
	const int h = atoi(argv[2]);
	const int frames = atoi(argv[3]);

	FILE* f = fopen(argv[4], "wb");
	if (!f)
		return 1;
	fprintf(f, "YUV4MPEG2 W%d H%d F25:1 Ip A1:1 C420jpeg\n", w, h);

	std::vector<unsigned char> y(w * h);
	std::vector<unsigned char> u(w / 2 * h / 2);
	std::vector<unsigned char> v(w / 2 * h / 2);

	for (int t = 0; t < frames; t++)
	{
		fwrite("FRAME\n", 1, 6, f);
		// slowly moving plasma: two moving noise fields + motion streaks
		for (int yy = 0; yy < h; yy++)
		{
			for (int x = 0; x < w; x++)
			{
				uint32_t n1 = hash2(x + t * 2, yy + t, 0x1234u) & 0xFF;
				uint32_t n2 = hash2(x - t * 3, yy + t * 2, 0x5678u) & 0xFF;
				uint32_t n3 = hash2(x * 7 + t * 5, yy * 3 - t * 7, 0x9ABCu) & 0xFF;
				y[yy * w + x] = (unsigned char)((n1 * 2 + n2 + n3) / 4);
			}
		}
		for (int yy = 0; yy < h / 2; yy++)
		{
			for (int x = 0; x < w / 2; x++)
			{
				uint32_t n1 = hash2(x * 2 + t, yy * 2 + t, 0x2468u) & 0xFF;
				uint32_t n2 = hash2(x * 2 - t, yy * 2 - t * 2, 0x1357u) & 0xFF;
				u[yy * w / 2 + x] = (unsigned char)(128 + (int)(n1 - n2) / 4);
				v[yy * w / 2 + x] = (unsigned char)(128 + (int)(n2 - n1) / 4);
			}
		}
		fwrite(y.data(), 1, y.size(), f);
		fwrite(u.data(), 1, u.size(), f);
		fwrite(v.data(), 1, v.size(), f);
	}
	fclose(f);
	fprintf(stderr, "gen_video: %dx%d, %d frames -> %s\n", w, h, frames, argv[4]);
	return 0;
}
