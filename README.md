# FFmpeg Ampere Neoverse-N1 Optimized Image

This image provides a build of FFmpeg optimized specifically for the ARM Neoverse-N1 architecture, following the Ampere Computing tuning guidelines.

**Docker Image**: [somewatson/ffmpeg-ampere-n1](https://hub.docker.com/r/somewatson/ffmpeg-ampere-n1)

**Source**: [Ampere FFmpeg Tuning Guide](https://amperecomputing.com/tuning-guides/FFmpeg-Tuning-Guide)

## Build the Image

Build the image from the local Dockerfile:

```bash
docker build -t ffmpeg-ampere-n1 .
```

**Note on High Core Counts**: This Dockerfile uses `$(nproc)` to maximize parallelism. On machines with a very high number of cores (e.g., 128+), ensure you have sufficient RAM (roughly 2GB per core) to avoid Out-Of-Memory (OOM) errors during compilation. If the build fails due to memory, you may need to limit the parallelism by replacing `$(nproc)` with a fixed number in the Dockerfile.

## Usage

The image is configured with `ffmpeg` as the entrypoint.

### Check Version
Verify the installation and optimization:
```bash
docker run --rm ffmpeg-ampere-n1 -version
```

### Basic Transcoding
To transcode a video file, mount your local media directory to the container. We recommend using `--shm-size=2g` and `--privileged` for maximum performance on Ampere N1:

```bash
docker run --rm --shm-size=2g --privileged -v $(pwd):/media ffmpeg-ampere-n1 \
  -i /media/input.mp4 \
  -c:v libx264 \
  -preset medium \
  -crf 23 \
  -c:a aac \
  /media/output.mp4
```

### H.265 (HEVC) Encoding
Utilizing the optimized `libx265`:

```bash
docker run --rm --shm-size=2g --privileged -v $(pwd):/media ffmpeg-ampere-n1 \
  -i /media/input.mp4 \
  -c:v libx265 \
  -crf 28 \
  /media/output_hevc.mp4
```

### AV1 Encoding
Utilizing `libsvtav1` for high-performance, scalable encoding. 

**Note**: This image uses `SVT-AV1` instead of the reference `libaom-av1` implementation. SVT-AV1 is specifically designed for massive multi-core parallelism, making it significantly faster and more efficient on high-core-count systems (e.g., 128+ cores).

```bash
docker run --rm --shm-size=2g --privileged -v $(pwd):/media ffmpeg-ampere-n1 \
  -i /media/input.mp4 \
  -c:v libsvtav1 \
  -crf 30 \
  -preset 6 \
  /media/output_av1.mp4
```

## Large-Scale Encoding (Chunked Parallelism)

For maximum throughput on high-core-count systems, use chunked encoding. This process splits the input into segments, encodes them in parallel across multiple FFmpeg instances, and concatenates the results.

Use the provided helper script:
```bash
chmod +x chunked_encode.sh
./chunked_encode.sh <input_file> <output_file> <codec> <crf> <preset> <chunks> <image_tag>

# Example: Split into 10 chunks using libx265
./chunked_encode.sh input.mp4 output.mp4 libx265 28 slow 10 ffmpeg-ampere-n1
```

## Benchmarks
Performance comparison between a generic FFmpeg image and the optimized `ffmpeg-ampere-n1` image on Ampere Neoverse-N1 architecture.

**Quality Metric (PSNR):**
PSNR (Peak Signal-to-Noise Ratio) measures reconstruction quality. 
- **> 40 dB**: Excellent (imperceptible difference from source)
- **30-40 dB**: Good to Very Good
- **< 30 dB**: Noticeable quality loss

**Test Configuration:**
- **Source**: `BigBuckBunny_512kb.mp4`
- **Settings**: CRF 23, Preset Slow (or Preset 8 for SVT-AV1)
- **Runtime**: `--ipc=host`, `--privileged`

### Standard Mode
| Image | Codec | Time (s) | Size (KB) | PSNR (dB) | FPS |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Generic | libx264 | 51.84 | 26,092 | 41.36 | 286.00 |
| **Optimized** | **libx264** | **50.93** | **26,092** | **41.36** | **286.00** |
| Generic | libx265 | 312.62 | 17,268 | 39.44 | 46.00 |
| **Optimized** | **libx265** | **253.01** | **17,420** | **39.36** | **57.00** |
| Generic | libsvtav1 | 36.62 | 29,188 | 41.94 | 412.00 |
| **Optimized** | **libsvtav1** | **28.82** | **29,232** | **41.95** | **515.00** |

**Standard Mode Performance Improvement:**
- **libx264**: 1.00% faster (Speedup: 0.91s)
- **libx265**: 19.00% faster (Speedup: 59.61s)
- **libsvtav1**: 21.00% faster (Speedup: 7.80s)

### Chunked Mode (Parallelism)
| Image | Codec | Time (s) | Size (KB) | PSNR (dB) | FPS |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Generic | libx264 | 20.58 | 26,116 | 41.36 | 280.00 |
| **Optimized** | **libx264** | **18.34** | **26,116** | **41.36** | **279.25** |
| Generic | libx265 | 99.44 | 17,288 | 39.44 | 44.50 |
| **Optimized** | **libx265** | **77.57** | **17,440** | **39.36** | **56.00** |
| Generic | libsvtav1 | 15.82 | 29,224 | 41.94 | 391.75 |
| **Optimized** | **libsvtav1** | **13.57** | **29,244** | **41.95** | **475.50** |

**Chunked Mode Performance Improvement:**
- **libx264**: 10.00% faster (Speedup: 2.24s)
- **libx265**: 21.00% faster (Speedup: 21.87s)
- **libsvtav1**: 14.00% faster (Speedup: 2.25s)

## Optimizations applied
- **Target CPU**: `-mcpu=neoverse-n1` (Optimized for the Ampere Neoverse-N1 architecture)
- **Link-Time Optimization**: `-flto=auto` enabled across all libraries and FFmpeg for improved inter-procedural optimization.
- **Compiler Flags**:
    - Standard optimization level (Default `-O2`) used for stability and peak performance on N1.
- **Libraries**: `libx264`, `libx265`, `libvpx`, `libsvtav1`
- **Architecture**: Built specifically for ARM64 / Ampere N1.


## Credits
This project was created by [Some Watson](https://somewatson.com/) with the assistance of opencode, an AI software engineering agent.
