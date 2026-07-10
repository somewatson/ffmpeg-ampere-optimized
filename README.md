# FFmpeg Ampere Neoverse-N1 Optimized Image

This image provides a build of FFmpeg optimized specifically for the ARM Neoverse-N1 architecture, following the Ampere Computing tuning guidelines.

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
To transcode a video file, mount your local media directory to the container:

```bash
docker run --rm -v $(pwd):/media ffmpeg-ampere-n1 \
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
docker run --rm -v $(pwd):/media ffmpeg-ampere-n1 \
  -i /media/input.mp4 \
  -c:v libx265 \
  -crf 28 \
  /media/output_hevc.mp4
```

### AV1 Encoding
Utilizing `libaom-av1` for high-efficiency encoding:

```bash
docker run --rm -v $(pwd):/media ffmpeg-ampere-n1 \
  -i /media/input.mp4 \
  -c:v libaom-av1 \
  -crf 30 \
  -b:v 0 \
  /media/output_av1.mp4
```

## Optimizations applied
- Target CPU: `neoverse-n1`
- Libraries: `libx264`, `libx265`, `libvpx`, `libaom`
- Compiler flags: `-mcpu=neoverse-n1` used across all build stages.

## Credits
This project was created by [Some Watson](https://somewatson.com/) with the assistance of opencode, an AI software engineering agent.
