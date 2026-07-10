#!/bin/bash

# Benchmarking script for FFmpeg Docker containers

SAMPLE_URL="https://samples.ffmpeg.org/MPEG-4/video.mp4"
SAMPLE_FILE="video.mp4"
GENERIC_IMAGE="datarhei/ffmpeg"
OPTIMIZED_IMAGE="somewatson/ffmpeg-ampere-n1"

# Download sample file
echo "Downloading sample file..."
curl -L $SAMPLE_URL -o $SAMPLE_FILE

if [ ! -f $SAMPLE_FILE ]; then
    echo "Failed to download sample file."
    exit 1
fi

run_benchmark() {
    local image=$1
    local label=$2
    local iteration=$3
    local output="out_${label}_${iteration}.mp4"
    
    echo "Running benchmark for $label ($image) - Iteration $iteration..."
    
    rm -f $output
    
    start_time=$(date +%s.%N)
    docker run --rm -v "$(pwd):/config" $image -i /config/$SAMPLE_FILE -c:v libx264 -preset medium -c:a copy /config/$output > /dev/null 2>&1
    end_time=$(date +%s.%N)
    
    runtime=$(echo "$end_time - $start_time" | bc)
    echo $runtime
}

echo "----------------------------------------"
ITERATIONS=${1:-3}
GENERIC_TOTAL=0
OPTIMIZED_TOTAL=0

echo "Running $ITERATIONS iterations..."

for i in $(seq 1 $ITERATIONS); do
    echo "Iteration $i..."
    G_TIME=$(run_benchmark $GENERIC_IMAGE "Generic" $i)
    O_TIME=$(run_benchmark $OPTIMIZED_IMAGE "Optimized" $i)
    
    echo "Generic: $G_TIME s | Optimized: $O_TIME s"
    GENERIC_TOTAL=$(echo "$GENERIC_TOTAL + $G_TIME" | bc)
    OPTIMIZED_TOTAL=$(echo "$OPTIMIZED_TOTAL + $O_TIME" | bc)
done
echo "----------------------------------------"

GENERIC_AVG=$(echo "scale=3; $GENERIC_TOTAL / $ITERATIONS" | bc)
OPTIMIZED_AVG=$(echo "scale=3; $OPTIMIZED_TOTAL / $ITERATIONS" | bc)

DIFF=$(echo "$GENERIC_AVG - $OPTIMIZED_AVG" | bc)
PERC=$(echo "scale=2; ($DIFF / $GENERIC_AVG) * 100" | bc)

echo "Avg Generic:   $GENERIC_AVG s"
echo "Avg Optimized: $OPTIMIZED_AVG s"
echo "Difference:    $DIFF s ($PERC% faster)"

# Cleanup
rm $SAMPLE_FILE out_Generic_*.mp4 out_Optimized_*.mp4
