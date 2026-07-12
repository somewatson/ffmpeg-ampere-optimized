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

  **Test Configuration:**
  - **Source**: `BigBuckBunny_512kb.mp4`
  - **Settings**: CRF 23, Preset Slow (or Preset 8 for SVT-AV1)
  - **Runtime**: `--ipc=host`, `--privileged`

  | Image | Codec | Time (s) | Size (KB) | PSNR (dB) | FPS |
  | :--- | :--- | :--- | :--- | :--- | :--- |
  | Generic | libx264 | 51.92 | 26,092 | 41.36 | 285.00 |
  | **Optimized** | **libx264** | **51.03** | **26,092** | **41.36** | **285.00** |
  | Generic | libx265 | 375.37 | 30,936 | 42.69 | 38.00 |
  | **Optimized** | **libx265** | **294.91** | **31,108** | **42.63** | **49.00** |
  | Generic | libsvtav1 | 36.90 | 44,176 | 44.05 | 408.00 |
  | **Optimized** | **libsvtav1** | **28.11** | **44,200** | **44.06** | **527.00** |

  **Performance Improvement (Optimized vs Generic):**
  - **libx264**: 1.00% faster
  - **libx265**: 21.00% faster (Speedup: 80.46s)
  - **libsvtav1**: 23.00% faster (Speedup: 8.78s)

  ## Optimizations applied
  - **Target CPU**: `-mcpu=neoverse-n1` (Optimized for the Ampere Neoverse-N1 architecture)
  - **Link-Time Optimization**: `-flto=auto` enabled across all libraries and FFmpeg for improved inter-procedural optimization.
  - **Compiler Flags**:
      - Standard optimization level (Default `-O2`) used for stability and peak performance on N1.
  - **Libraries**: `libx264`, `libx265`, `libvpx`, `libsvtav1`
  - **Architecture**: Built specifically for ARM64 / Ampere N1.


  ## Credits
  This project was created by [Some Watson](https://somewatson.com/) with the assistance of opencode, an AI software engineering agent.
