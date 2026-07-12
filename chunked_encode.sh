#!/bin/bash
set -e

# Usage: ./chunked_encode.sh <input_file> <output_file> <codec> <crf> <preset> <chunks> <image>
if [ "$#" -ne 7 ]; then
    echo "Usage: $0 <input_file> <output_file> <codec> <crf> <preset> <chunks> <image>"
    echo "Example: $0 input.mp4 output.mp4 libx265 28 slow 10 ffmpeg-ampere-optimized"
    exit 1
fi

INPUT=$1
OUTPUT=$2
CODEC=$3
CRF=$4
PRESET=$5
CHUNKS=$6
IMAGE=$7

TEMP_DIR=$(mktemp -d)
SEGMENTS_DIR="$TEMP_DIR/segments"
ENCODED_DIR="$TEMP_DIR/encoded"
mkdir -p "$SEGMENTS_DIR" "$ENCODED_DIR"

echo "Step 1: Segmenting input into $CHUNKS chunks..."
# Use ffmpeg to split input into segments without re-encoding
docker run --rm -v "$(pwd):/config" $IMAGE -i "/config/$INPUT" -f segment -segment_time $(($(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT") / $CHUNKS)) -c copy "/config/$SEGMENTS_DIR/seg_%03d.mp4"

# Wait, the above docker run might not work because SEGMENTS_DIR is inside /tmp. 
# Let's use local paths for temporary files.
# Redoing segmentation with local mount.

# Corrected Segmentation
docker run --rm -v "$TEMP_DIR:/tmp/chunks" $IMAGE -i "/config/$INPUT" -f segment -segment_time $(($(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT") / $CHUNKS)) -c copy "/tmp/chunks/seg_%03d.mp4" 2>/dev/null || \
docker run --rm -v "$(pwd):/config" $IMAGE -i "/config/$INPUT" -f segment -segment_time $(( $(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT") / $CHUNKS )) -c copy "/config/$SEGMENTS_DIR/seg_%03d.mp4"

# Let's simplify and use a local directory for chunks to avoid docker mount complexity
# I'll use a local directory in the current workspace
CHUNKS_DIR="chunks_tmp"
ENCODED_DIR="encoded_tmp"
mkdir -p "$CHUNKS_DIR" "$ENCODED_DIR"

echo "Step 1: Segmenting input..."
# Get duration
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT")
SEG_TIME=$(echo "$DURATION / $CHUNKS" | bc)

docker run --rm -v "$(pwd):/config" $IMAGE -i "/config/$INPUT" -f segment -segment_time "$SEG_TIME" -c copy "/config/$CHUNKS_DIR/seg_%03d.mp4"

echo "Step 2: Encoding chunks in parallel..."
# Create a list of segments
SEGMENTS=$(ls "$CHUNKS_DIR"/*.mp4 | sort)

# Use xargs to run encoding in parallel. 
# -P 0 uses as many processes as possible, but we might want to limit it based on core count vs codec overhead.
# For libx265, it's already multi-threaded, so we don't want too many concurrent ffmpeg instances.
# Recommendation: total_cores / 16 (approx)
CONCURRENT_JOBS=$(($(nproc) / 16))
if [ "$CONCURRENT_JOBS" -lt 1 ]; then CONCURRENT_JOBS=1; fi

echo "Running with $CONCURRENT_JOBS concurrent instances..."

export -f docker # not possible with xargs easily, use a loop or a helper script

# Helper function for encoding
encode_chunk() {
    local seg=$1
    local codec=$2
    local crf=$3
    local preset=$4
    local image=$5
    local base=$(basename "$seg")
    local out="encoded_tmp/enc_$base"
    
    docker run --rm --ipc=host --privileged -v "$(pwd):/config" "$image" -i "/config/$seg" -c:v "$codec" -crf "$crf" -preset "$preset" -c:a copy "/config/$out"
}
export -f encode_chunk

# Use GNU Parallel if available, otherwise a simple loop with backgrounding
if command -v parallel >/dev/null 2>&1; then
    parallel -j "$CONCURRENT_JOBS" encode_chunk {} "$CODEC" "$CRF" "$PRESET" "$IMAGE" ::: $SEGMENTS
else
    # Fallback to manual backgrounding with limit
    count=0
    for seg in $SEGMENTS; do
        encode_chunk "$seg" "$CODEC" "$CRF" "$PRESET" "$IMAGE" &
        count=$((count + 1))
        if [ "$count" -ge "$CONCURRENT_JOBS" ]; then
            wait -n
            count=$((count - 1))
        fi
    done
    wait
fi

echo "Step 3: Concatenating results..."
# Create a list file for concat
CONCAT_LIST="concat_list.txt"
> "$CONCAT_LIST"
for seg in $(ls "$ENCODED_DIR"/*.mp4 | sort); do
    echo "file '$seg'" >> "$CONCAT_LIST"
done

docker run --rm -v "$(pwd):/config" $IMAGE -f concat -safe 0 -i "/config/$CONCAT_LIST" -c copy "/config/$OUTPUT"

# Cleanup
rm -rf "$CHUNKS_DIR" "$ENCODED_DIR" "$CONCAT_LIST"
echo "Done! Final output: $OUTPUT"
