#!/bin/bash

# Benchmarking script for FFmpeg Docker containers

SAMPLE_URL="https://samples.ffmpeg.org/MPEG-4/video.mp4"
SAMPLE_FILE="video.mp4"
GENERIC_IMAGE_1="datarhei/ffmpeg"
GENERIC_IMAGE_2="linuxserver/ffmpeg"
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
    
    echo "Running benchmark for $label ($image) - Iteration $iteration..." >&2
    
    rm -f $output
    
    CMD="docker run --rm -v \"$(pwd):/config\" $image -i /config/$SAMPLE_FILE -c:v libx264 -preset medium -c:a copy /config/$output"
    echo "Command: $CMD" >&2
    
    start_time=$(date +%s.%N)
    eval $CMD > /dev/null 2>&1
    end_time=$(date +%s.%N)
    
    runtime=$(echo "$end_time - $start_time" | bc)
    echo "$runtime"
}

verify_quality() {
    local ref_file=$1
    local target_file=$2
    local label=$3
    
    echo "Verifying quality for $label (PSNR vs Original)..." >&2
    PSNR=$(docker run --rm -v "$(pwd):/config" $GENERIC_IMAGE_1 -i /config/$target_file -i /config/$ref_file -filter_complex psnr -f null - 2>&1 | grep "average:" | sed 's/.*average:\([0-9.]*\).*/\1/')
    if [ -z "$PSNR" ] || [ "$PSNR" == "inf" ]; then
        PSNR="0"
    fi
    echo "$PSNR"
}

echo "========================================================================"
echo " FFmpeg Docker Performance Benchmark"
echo "========================================================================"
ITERATIONS=${1:-3}
G1_TOTAL=0
G2_TOTAL=0
OPTIMIZED_TOTAL=0

echo "Settings: $ITERATIONS iterations"
echo "------------------------------------------------------------------------"

for i in $(seq 1 $ITERATIONS); do
    echo "Iteration $i of $ITERATIONS"
    T1=$(run_benchmark $GENERIC_IMAGE_1 "Generic1" $i | tail -n 1)
    T2=$(run_benchmark $GENERIC_IMAGE_2 "Generic2" $i | tail -n 1)
    TO=$(run_benchmark $OPTIMIZED_IMAGE "Optimized" $i | tail -n 1)
    
    printf "    Results -> G1: %-10s G2: %-10s Opt: %-10s\n" "$T1 s" "$T2 s" "$TO s"
    G1_TOTAL=$(echo "$G1_TOTAL + $T1" | bc)
    G2_TOTAL=$(echo "$G2_TOTAL + $T2" | bc)
    OPTIMIZED_TOTAL=$(echo "$OPTIMIZED_TOTAL + $TO" | bc)
    echo ""
done

echo "========================================================================"
echo " Quality Verification (vs Original)"
echo "========================================================================"
G1_LAST="out_Generic1_${ITERATIONS}.mp4"
G2_LAST="out_Generic2_${ITERATIONS}.mp4"
O_LAST="out_Optimized_${ITERATIONS}.mp4"

G1_SCORE=$(verify_quality $SAMPLE_FILE $G1_LAST "Generic1")
G2_SCORE=$(verify_quality $SAMPLE_FILE $G2_LAST "Generic2")
O_SCORE=$(verify_quality $SAMPLE_FILE $O_LAST "Optimized")

printf "  Generic1 PSNR:   %s dB\n" "$G1_SCORE"
printf "  Generic2 PSNR:   %s dB\n" "$G2_SCORE"
printf "  Optimized PSNR:  %s dB\n" "$O_SCORE"

Q_DIFF=$(echo "$O_SCORE - $G1_SCORE" | bc)
echo "  Quality Diff:    $Q_DIFF dB (Optimized vs Generic1)"
echo "------------------------------------------------------------------------"

G1_AVG=$(echo "scale=3; $G1_TOTAL / $ITERATIONS" | bc)
G2_AVG=$(echo "scale=3; $G2_TOTAL / $ITERATIONS" | bc)
OPTIMIZED_AVG=$(echo "scale=3; $OPTIMIZED_TOTAL / $ITERATIONS" | bc)

BEST_GENERIC_AVG=$(echo "if ($G1_AVG < $G2_AVG) $G1_AVG else $G2_AVG" | bc -l)
DIFF=$(echo "$BEST_GENERIC_AVG - $OPTIMIZED_AVG" | bc)
PERC=$(echo "scale=2; ($DIFF / $BEST_GENERIC_AVG) * 100" | bc)

echo ""
echo "========================================================================"
echo " Final Performance Results (Average)"
echo "========================================================================"
printf "  Avg Generic1:   %s s\n" "$G1_AVG"
printf "  Avg Generic2:   %s s\n" "$G2_AVG"
printf "  Avg Optimized:  %s s\n" "$OPTIMIZED_AVG"
echo "------------------------------------------------------------------------"
printf "  Speedup vs Best Generic: %s s (%s%% faster)\n" "$DIFF" "$PERC"
echo "========================================================================"

# Cleanup
rm -f $SAMPLE_FILE out_Generic1_*.mp4 out_Generic2_*.mp4 out_Optimized_*.mp4
