# Build stage
FROM arm64v8/ubuntu:22.04 AS builder

# Avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install prerequisites
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    yasm \
    nasm \
    libnuma-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Setup directories
RUN mkdir -p /ffmpeg_sources /ffmpeg_build /bin
ENV PATH="/bin:$PATH"
ENV PKG_CONFIG_PATH="/ffmpeg_build/lib/pkgconfig"

# Build libx264
RUN cd /ffmpeg_sources && \
    git clone --depth 1 https://code.videolan.org/videolan/x264.git && \
    cd x264 && \
    ./configure --prefix="/ffmpeg_build" --bindir="/bin" --enable-static --enable-pic --extra-cflags="-mcpu=neoverse-n1" && \
    make -j $(nproc) && \
    make install

# Build libx265
RUN export CFLAGS="-mcpu=neoverse-n1" && \
    export CXXFLAGS="-mcpu=neoverse-n1" && \
    cd /ffmpeg_sources && \
    wget -O x265.tar.bz2 https://bitbucket.org/multicoreware/x265_git/get/master.tar.bz2 && \
    tar xjvf x265.tar.bz2 && \
    cd multicoreware*/build/linux && \
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="/ffmpeg_build" -DENABLE_SHARED=off ../../source && \
    make -j $(nproc) && \
    make install

# Build libvpx
RUN cd /ffmpeg_sources && \
    git clone --depth 1 https://chromium.googlesource.com/webm/libvpx.git && \
    cd libvpx && \
    ./configure --prefix="/ffmpeg_build" --disable-examples --disable-unit-tests --enable-vp9-highbitdepth --as=yasm --extra-cflags="-mcpu=neoverse-n1" --extra-cxxflags="-mcpu=neoverse-n1" && \
    make -j $(nproc) && \
    make install

# Build libaom
RUN export CFLAGS="-mcpu=neoverse-n1" && \
    export CXXFLAGS="-mcpu=neoverse-n1" && \
    cd /ffmpeg_sources && \
    git clone --depth 1 https://aomedia.googlesource.com/aom && \
    mkdir -p aom_build && \
    cd aom_build && \
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="/ffmpeg_build" -DENABLE_TESTS=OFF -DENABLE_NASM=on ../aom && \
    make -j $(nproc) && \
    make install

# Build FFmpeg
RUN cd /ffmpeg_sources && \
    wget -O ffmpeg-snapshot.tar.bz2 https://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2 && \
    tar xjvf ffmpeg-snapshot.tar.bz2 && \
    cd ffmpeg && \
    ./configure \
        --prefix="/ffmpeg_build" \
        --pkg-config-flags="--static" \
        --extra-cflags="-I/ffmpeg_build/include -mcpu=neoverse-n1" \
        --extra-cxxflags="-mcpu=neoverse-n1" \
        --extra-ldflags="-L/ffmpeg_build/lib" \
        --extra-libs="-lpthread -lm" \
        --ld="g++" \
        --bindir="/bin" \
        --enable-gpl \
        --enable-libaom \
        --enable-libvpx \
        --enable-libx264 \
        --enable-libx265 \
        --enable-nonfree && \
    make -j $(nproc) && \
    make install

# Final stage
FROM arm64v8/ubuntu:22.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libnuma1 \
    && rm -rf /var/lib/apt/lists/*

# Copy binaries from builder
COPY --from=builder /bin /bin
COPY --from=builder /ffmpeg_build /ffmpeg_build

ENV PATH="/bin:$PATH"

ENTRYPOINT ["ffmpeg"]
CMD ["-version"]
