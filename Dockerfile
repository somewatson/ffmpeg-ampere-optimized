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
    git clone --depth 1 https://bitbucket.org/multicoreware/x265_git.git x265 && \
    cd x265/build/linux && \
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="/ffmpeg_build" -DENABLE_SHARED=off -DENABLE_SVE=OFF -DCMAKE_C_FLAGS="-mcpu=neoverse-n1" -DCMAKE_CXX_FLAGS="-mcpu=neoverse-n1" ../../source && \
    cmake --build . -j $(nproc) && \
    make install && \
    mkdir -p /ffmpeg_build/lib/pkgconfig && \
    cat <<EOF > /ffmpeg_build/lib/pkgconfig/x265.pc
prefix=/ffmpeg_build
exec_prefix=/ffmpeg_build
libdir=/ffmpeg_build/lib
includedir=/ffmpeg_build/include

Name: x265
Description: HEVC encoder
Version: 0.0.0
Libs: -L/ffmpeg_build/lib -lx265 -lnuma
Cflags: -I/ffmpeg_build/include
EOF

# Build libvpx
RUN export CFLAGS="-mcpu=neoverse-n1" && \
    export CXXFLAGS="-mcpu=neoverse-n1" && \
    cd /ffmpeg_sources && \
    git clone --depth 1 https://chromium.googlesource.com/webm/libvpx.git && \
    cd libvpx && \
    ./configure --prefix="/ffmpeg_build" --disable-examples --disable-unit-tests --enable-vp9-highbitdepth --as=yasm && \
    make -j $(nproc) && \
    make install

# Build SVT-AV1
RUN export CFLAGS="-mcpu=neoverse-n1" && \
    export CXXFLAGS="-mcpu=neoverse-n1" && \
    cd /ffmpeg_sources && \
    git clone --depth 1 https://gitlab.com/AOMediaCodec/SVT-AV1.git && \
    cd SVT-AV1 && \
    cmake -B Bin/Release -S . -DCMAKE_INSTALL_PREFIX="/ffmpeg_build" -DCMAKE_BUILD_TYPE="Release" && \
    cmake --build Bin/Release -j && \
    cmake --install Bin/Release


# Build FFmpeg
RUN cd /ffmpeg_sources && \
    wget -O ffmpeg-snapshot.tar.bz2 https://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2 && \
    tar xjvf ffmpeg-snapshot.tar.bz2 && \
    cd ffmpeg

RUN cd /ffmpeg_sources/ffmpeg && \
    PKG_CONFIG_PATH="/ffmpeg_build/lib/pkgconfig" ./configure \
        --prefix="/ffmpeg_build" \
        --pkg-config-flags="--static" \
        --extra-cflags="-I/ffmpeg_build/include -mcpu=neoverse-n1" \
        --extra-cxxflags="-mcpu=neoverse-n1" \
        --extra-ldflags="-L/ffmpeg_build/lib" \
        --extra-libs="-lpthread -lm" \
        --ld="g++" \
        --bindir="/bin" \
        --enable-gpl \
        --enable-libsvtav1 \
        --enable-libvpx \
        --enable-libx264 \
        --enable-libx265 \
        --enable-nonfree

RUN cd /ffmpeg_sources/ffmpeg && \
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
ENV LD_LIBRARY_PATH="/ffmpeg_build/lib"

ENTRYPOINT ["ffmpeg"]
CMD ["-version"]
