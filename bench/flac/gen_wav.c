/* gen_wav.c - deterministic music-like WAV generator for flac benchmarking.
 *
 * Synthesizes a 16-bit stereo 44.1kHz signal that resembles music:
 * a few harmonic partials with slow amplitude modulation (LFOs) plus a
 * small noise floor, so it compresses at a realistic ratio (~45-60%).
 * Pure CLI: gen_wav <seconds> <outfile.wav>
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define SAMPLE_RATE 44100
#define CHANNELS 2

static uint32_t rng_state = 0x9e3779b9u;
static uint32_t lcg(void) {
  rng_state = rng_state * 1664525u + 1013904223u;
  return rng_state;
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: %s <seconds> <outfile.wav>\n", argv[0]);
    return 1;
  }
  double seconds = atof(argv[1]);
  if (seconds <= 0) return 1;
  long nframes = (long)(seconds * SAMPLE_RATE);
  FILE *f = fopen(argv[2], "wb");
  if (!f) { perror("fopen"); return 1; }

  uint64_t data_bytes = (uint64_t)nframes * CHANNELS * 2;
  uint8_t hdr[82] = {0};
  if (data_bytes <= 0xFFFFFFF4u) {
    /* classic RIFF/WAVE with 32-bit sizes */
    memcpy(hdr, "RIFF", 4);
    *(uint32_t *)(hdr + 4) = (uint32_t)(data_bytes + 36);
    memcpy(hdr + 8, "WAVEfmt ", 8);
    *(uint32_t *)(hdr + 16) = 16;        /* fmt chunk size */
    *(uint16_t *)(hdr + 20) = 1;         /* PCM */
    *(uint16_t *)(hdr + 22) = CHANNELS;
    *(uint32_t *)(hdr + 24) = SAMPLE_RATE;
    *(uint32_t *)(hdr + 28) = SAMPLE_RATE * CHANNELS * 2;
    *(uint16_t *)(hdr + 32) = CHANNELS * 2;
    *(uint16_t *)(hdr + 34) = 16;
    memcpy(hdr + 36, "data", 4);
    *(uint32_t *)(hdr + 40) = (uint32_t)data_bytes;
    fwrite(hdr, 1, 44, f);
  } else {
    /* RF64 (64-bit sizes) for files > 4 GB */
    memcpy(hdr, "RF64", 4);
    *(uint32_t *)(hdr + 4) = 0xFFFFFFFFu;
    memcpy(hdr + 8, "WAVE", 4);
    memcpy(hdr + 12, "ds64", 4);
    *(uint32_t *)(hdr + 16) = 28;                 /* ds64 chunk size */
    *(uint64_t *)(hdr + 20) = data_bytes + 72;    /* RIFF size - 8 */
    *(uint64_t *)(hdr + 28) = data_bytes;         /* data size */
    *(uint64_t *)(hdr + 36) = (uint64_t)nframes;  /* sample count */
    *(uint32_t *)(hdr + 44) = 0;                  /* table length */
    memcpy(hdr + 48, "fmt ", 4);
    *(uint32_t *)(hdr + 52) = 16;
    *(uint16_t *)(hdr + 56) = 1;         /* PCM */
    *(uint16_t *)(hdr + 58) = CHANNELS;
    *(uint32_t *)(hdr + 60) = SAMPLE_RATE;
    *(uint32_t *)(hdr + 64) = SAMPLE_RATE * CHANNELS * 2;
    *(uint16_t *)(hdr + 68) = CHANNELS * 2;
    *(uint16_t *)(hdr + 70) = 16;
    memcpy(hdr + 72, "data", 4);
    *(uint32_t *)(hdr + 76) = 0xFFFFFFFFu;        /* extended size */
    fwrite(hdr, 1, 80, f);
  }

  /* note pattern: chord progression, each note lasts 2.5 s */
  const double notes[] = {
    220.0, 261.63, 329.63, 440.0,   /* A minor-ish */
    196.0, 246.94, 293.66, 392.0,
    174.61, 220.0, 261.63, 349.23,
    164.81, 207.65, 261.63, 329.63,
  };
  const int nnotes = (int)(sizeof(notes) / sizeof(notes[0]));
  const double note_len = 2.5;
  int16_t *buf = malloc(65536 * CHANNELS * sizeof(int16_t));
  long written = 0;
  while (written < nframes) {
    int chunk = (nframes - written) < 65536 ? (int)(nframes - written) : 65536;
    for (int i = 0; i < chunk; i++) {
      double t = (double)(written + i) / SAMPLE_RATE;
      int note_idx = (int)(t / note_len);
      int note = note_idx % nnotes;
      double freq = notes[note] * (1.0 + 0.0004 * sin(2 * M_PI * 0.13 * t));
      /* harmonic-rich tone: fundamental + 4 partials with LFO modulation */
      double s = 0.0;
      s += 0.5 * sin(2 * M_PI * freq * t);
      s += 0.125 * sin(2 * M_PI * 2 * freq * t + 0.5);
      s += 0.055 * sin(2 * M_PI * 3 * freq * t + 1.1);
      s += 0.03 * sin(2 * M_PI * 4 * freq * t + 2.0);
      s += 0.02 * sin(2 * M_PI * 5 * freq * t + 0.2);
      double amp = 0.6 + 0.4 * sin(2 * M_PI * 0.37 * t) * sin(2 * M_PI * 0.11 * t);
      /* envelope at note boundaries (use unwrapped note index for phase) */
      double ph = (t - note_idx * note_len) / note_len;
      double env = ph < 0.15 ? ph / 0.15 : (ph > 0.8 ? (1.0 - ph) / 0.2 : 1.0);
      s *= amp * env;
      /* noise floor: slight "air" */
      s += 0.0015 * ((double)lcg() / (double)UINT32_MAX * 2.0 - 1.0);
      int16_t v = (int16_t)(s * 28000.0);
      /* slight stereo separation: right channel detuned */
      double sr = 0.0;
      sr += 0.5 * sin(2 * M_PI * freq * 1.003 * t);
      sr += 0.125 * sin(2 * M_PI * 2 * freq * 1.003 * t + 0.5);
      sr += 0.055 * sin(2 * M_PI * 3 * freq * 1.003 * t + 1.1);
      sr += 0.03 * sin(2 * M_PI * 4 * freq * 1.003 * t + 2.0);
      sr += 0.02 * sin(2 * M_PI * 5 * freq * 1.003 * t + 0.2);
      sr *= amp * env;
      sr += 0.0015 * ((double)lcg() / (double)UINT32_MAX * 2.0 - 1.0);
      buf[i * CHANNELS] = v;
      buf[i * CHANNELS + 1] = (int16_t)(sr * 28000.0);
    }
    fwrite(buf, sizeof(int16_t) * CHANNELS, chunk, f);
    written += chunk;
  }
  free(buf);
  fclose(f);
  printf("wrote %lld frames (%llu bytes) to %s\n", (long long)nframes, (unsigned long long)(data_bytes + (data_bytes > 0xFFFFFFF4u ? 80 : 44)), argv[2]);
  return 0;
}
