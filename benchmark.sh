#!/bin/bash

# Benchmarking script for FFmpeg Docker containers: Bitrate vs Quality Analysis

SAMPLE_URL="https://samples.ffmpeg.org/MPEG-4/video.mp4"
SAMPLE_FILE="video.mp4"
GENERIC_IMAGE_1="datarhei/ffmpeg"
GENERIC_IMAGE_2="linuxserver/ffmpeg"
OPTIMIZED_IMAGE="somewatson/ffmpeg-ampere-n1"
CRF_VALUES=(23 28)

# Get total frames from source file
TOTAL_FRAMES=$(docker run --rm $GENERIC_IMAGE_1 -i $SAMPLE_FILE -vf null -f null - 2>&1 | grep "frame=" | tail -n 1 | awk -F'frame=' '{print $2}' | cut -d' ' -f1)

if [ -z "$TOTAL_FRAMES" ]; then
    echo "Warning: Could not detect total frames. FPS will be N/A." >&2
fi

curl -L $SAMPLE_URL -o $SAMPLE_FILE

if [ ! -f $SAMPLE_FILE ]; then
    echo "Failed to download sample file."
    exit 1
fi

run_benchmark() {
    local image=$1
    local label=$2
    local crf=$3
    local output="out_${label}_crf${crf}.mp4"
    
    echo "Encoding $label ($image) CRF $crf..." >&2
    
    rm -f $output
    
    # Use CRF for quality control
    CMD="docker run --rm --shm-size=2g --privileged -v \"$(pwd):/config\" $image -i /config/$SAMPLE_FILE -c:v libx264 -crf $crf -preset medium -c:a copy /config/$output"
    echo "Command: $CMD" >&2
    
    start_time=$(date +%s.%N)
    eval $CMD > /dev/null 2>&1
    end_time=$(date +%s.%N)
    
    runtime=$(echo "scale=2; $end_time - $start_time" | bc)
    
    # Calculate FPS
    if [ ! -z "$TOTAL_FRAMES" ] && [ "$TOTAL_FRAMES" != "0" ]; then
        fps=$(echo "scale=2; $TOTAL_FRAMES / $runtime" | bc)
    else
        fps="0.00"
    fi
    
    # Get file size in KB
    if [ -f "$output" ]; then
        size=$(du -k "$output" | cut -f1)
    else
        size=0
    fi
    
    echo "$runtime $size $fps"
}

verify_quality() {
    local ref_file=$1
    local target_file=$2
    local label=$3
    
    if [ ! -f "$target_file" ]; then
        echo "0"
        return
    fi

    CMD_PSNR="docker run --rm --shm-size=2g --privileged -v \"$(pwd):/config\" $GENERIC_IMAGE_1 -i /config/$target_file -i /config/$ref_file -filter_complex psnr -f null - 2>&1"
    PSNR=$(eval $CMD_PSNR | grep "average:" | sed 's/.*average:\([0-9.]*\).*/\1/')
    
    # Handle inf or empty results
    if [ -z "$PSNR" ]; then
        # Check if it was inf
        if eval $CMD_PSNR | grep -q "average:inf"; then
            PSNR="99.0"
        else
            PSNR="0"
        fi
    elif [ "$PSNR" == "inf" ]; then
        PSNR="99.0"
    fi
    echo "$PSNR"
}

echo "========================================================================"
echo " FFmpeg Bitrate vs Quality Benchmark"
echo "========================================================================"
echo "Images: $GENERIC_IMAGE_1, $GENERIC_IMAGE_2, $OPTIMIZED_IMAGE"
echo "CRF Levels: ${CRF_VALUES[*]}"
echo "------------------------------------------------------------------------"

# Temporary file to store results
RESULTS_FILE="results.tmp"
echo "Image,CRF,Time,Size,PSNR,FPS" > $RESULTS_FILE
echo "BestGenericTime,CRF,Time" > .best_gen.tmp

IMAGES=("$GENERIC_IMAGE_1" "$GENERIC_IMAGE_2" "$OPTIMIZED_IMAGE")
LABELS=("Generic1" "Generic2" "Optimized")

for idx in "${!IMAGES[@]}"; do
    IMAGE=${IMAGES[$idx]}
    LABEL=${LABELS[$idx]}
    
    for CRF in "${CRF_VALUES[@]}"; do
        # Run encode
        RES=$(run_benchmark "$IMAGE" "$LABEL" "$CRF")
        TIME=$(echo $RES | cut -d' ' -f1)
        SIZE=$(echo $RES | cut -d' ' -f2)
        FPS=$(echo $RES | cut -d' ' -f3)
        
        # Run quality check
        TARGET="out_${LABEL}_crf${CRF}.mp4"
        SCORE=$(verify_quality $SAMPLE_FILE $TARGET "$LABEL")
        
        echo "$LABEL,$CRF,$TIME,$SIZE,$SCORE,$FPS" >> $RESULTS_FILE

        if [ "$LABEL" != "Optimized" ]; then
            echo "$LABEL,$CRF,$TIME" >> .best_gen.tmp
        fi
    done
done

echo ""
echo "========================================================================"
echo " Final Comparison Summary"
echo "========================================================================"
printf "%-12s | %-5s | %-10s | %-10s | %-10s | %-10s\n" "Image" "CRF" "Time(s)" "Size(KB)" "PSNR(dB)" "FPS"
echo "----------------------------------------------------------------------------------------"

while IFS=, read -r img crf time size psnr fps; do
    if [ "$img" != "Image" ]; then
        printf "%-12s | %-5s | %-10.2f | %-10s | %-10.2f | %-10.2f\n" "$img" "$crf" "$time" "$size" "$psnr" "$fps"
    fi
done < $RESULTS_FILE

echo "----------------------------------------------------------------------------------------"
echo "Performance Improvement (Optimized vs Best Generic)"
echo "----------------------------------------------------------------------------------------"

for CRF in "${CRF_VALUES[@]}"; do
    # Find the best (lowest) time among generics for this CRF
    BEST_GEN=$(grep ",$CRF," .best_gen.tmp | cut -d',' -f3 | sort -n | head -n 1)
    # Find optimized time for this CRF
    OPT_TIME=$(grep "Optimized,$CRF," $RESULTS_FILE | cut -d',' -f3)
    
    if [ ! -z "$BEST_GEN" ] && [ ! -z "$OPT_TIME" ]; then
        DIFF=$(echo "scale=2; $BEST_GEN - $OPT_TIME" | bc)
        PERC=$(echo "scale=2; ($DIFF / $BEST_GEN) * 100" | bc)
        printf "  CRF %-2s: Speedup %-10s (%s%% faster)\n" "$CRF" "$DIFF s" "$PERC%"
    fi
done
echo "========================================================================"

# Cleanup
rm -f $SAMPLE_FILE out_*.mp4 $RESULTS_FILE .best_gen.tmp
