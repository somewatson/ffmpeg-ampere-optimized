#!/bin/bash
set -e

# Usage: ./chunked_encode.sh <input_file> <output_file> <codec> <crf> <preset> <chunks> [image]
if [ "$#" -lt 6 ]; then
    echo "Usage: $0 <input_file> <output_file> <codec> <crf> <preset> <chunks> [image]"
    echo "Example: $0 input.mp4 output.mp4 libx265 28 slow 10 somewatson/ffmpeg-ampere-n1"
    exit 1
fi

INPUT=$1
OUTPUT=$2
CODEC=$3
CRF=$4
PRESET=$5
CHUNKS=$6
IMAGE=${7:-"somewatson/ffmpeg-ampere-n1"}

TEMP_DIR=$(mktemp -d)
SEGMENTS_DIR="$TEMP_DIR/segments"
ENCODED_DIR="$TEMP_DIR/encoded"
mkdir -p "$SEGMENTS_DIR" "$ENCODED_DIR"

echo "Step 1: Segmenting input into $CHUNKS chunks..."
# Remove problematic early segmentation attempts
# Jump directly to duration calculation using the corrected container call
CHUNKS_DIR="chunks_tmp"
ENCODED_DIR="encoded_tmp"
mkdir -p "$CHUNKS_DIR" "$ENCODED_DIR"

# Get duration using ffprobe from within the container
# Since ENTRYPOINT is ["ffmpeg"], we override it to call ffprobe
DURATION=$(docker run --rm --entrypoint ffprobe -v "$(pwd):/config" $IMAGE -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "/config/$INPUT")

if [ -z "$DURATION" ]; then
    echo "Error: Could not determine duration of $INPUT. Ensure the image has ffprobe installed."
    exit 1
fi

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
