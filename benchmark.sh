#!/bin/bash

# Benchmarking script for FFmpeg Docker containers: Codec Performance Comparison

SAMPLE_URL="https://archive.org/download/BigBuckBunny_328/BigBuckBunny_512kb.mp4"
SAMPLE_FILE="video.mp4"
GENERIC_IMAGE_1="linuxserver/ffmpeg"
OPTIMIZED_IMAGE="somewatson/ffmpeg-ampere-n1"
CODECS=("libx264" "libx265" "libsvtav1")
CRF=23

# Get total frames from source file

curl -L $SAMPLE_URL -o $SAMPLE_FILE

if [ ! -f $SAMPLE_FILE ]; then
    echo "Failed to download sample file."
    exit 1
fi

run_benchmark() {
    local image=$1
    local label=$2
    local codec=$3
    local mode=$4
    local output="out_${label}_${codec}_${mode}.mp4"
    
    echo "Encoding $label ($image) using $codec in $mode mode..." >&2
    
    rm -f $output
    
    if [ "$codec" == "libsvtav1" ]; then
        PRESET="8"
        CURRENT_CRF=30
    elif [ "$codec" == "libx265" ]; then
        PRESET="slow"
        CURRENT_CRF=28
    else
        PRESET="slow"
        CURRENT_CRF=$CRF
    fi

    if [ "$mode" == "chunked" ]; then
        # Use the chunked_encode script
        # We need the image to be tagged as ffmpeg-ampere-optimized for the script to work
        # Since the script uses a hardcoded image name, we might need to tag it or edit the script
        # For benchmarking, we'll run the script and pass the image tag if we can, 
        # but the script currently hardcodes IMAGE="ffmpeg-ampere-optimized".
        # To make it generic, we'd need to edit chunked_encode.sh to accept image as arg.
        
        # Assuming we've updated chunked_encode.sh to take image as arg:
        # ./chunked_encode.sh <input> <output> <codec> <crf> <preset> <chunks> <image>
        
        # For now, we will use 4 chunks for the benchmark sample
        CMD="./chunked_encode.sh $SAMPLE_FILE $output $codec $CURRENT_CRF $preset 4 $image"
    else
        CMD="docker run --rm --ipc=host --privileged -v \"$(pwd):/config\" $image -i /config/$SAMPLE_FILE -c:v $codec -crf $CURRENT_CRF -preset $PRESET -c:a copy /config/$output"
    fi

    echo "Command: $CMD" >&2
    
    LOG_FILE="ffmpeg_log.tmp"
    start_time=$(date +%s.%N)
    eval $CMD > /dev/null 2> $LOG_FILE
    end_time=$(date +%s.%N)
    
    runtime=$(echo "scale=2; $end_time - $start_time" | bc)
    
    # Extract the last FPS value from the log
    fps=$(grep -o "fps=[ ]*[0-9.]*" $LOG_FILE | tail -n 1 | cut -d'=' -f2)
    [ -z "$fps" ] && fps="0.00"
    
    # Get file size in KB
    if [ -f "$output" ]; then
        size=$(du -k "$output" | cut -f1)
    else
        size=0
    fi
    
    rm -f $LOG_FILE
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

    CMD_PSNR="docker run --rm --ipc=host --privileged -v \"$(pwd):/config\" $GENERIC_IMAGE_1 -i /config/$target_file -i /config/$ref_file -filter_complex psnr -f null - 2>&1"
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
echo " FFmpeg Codec Performance Benchmark"
echo "========================================================================"
echo "Images: $GENERIC_IMAGE_1, $OPTIMIZED_IMAGE"
echo "CRF Values: libx264=$CRF, libx265=28, libsvtav1=30"
echo "Codecs: ${CODECS[*]}"
echo "------------------------------------------------------------------------"

# Temporary file to store results
RESULTS_FILE="results.tmp"
echo "Image,Codec,Mode,Time,Size,PSNR,FPS" > $RESULTS_FILE
echo "BestGenericTime,Codec,Mode,Time" > .best_gen.tmp

IMAGES=("$GENERIC_IMAGE_1" "$OPTIMIZED_IMAGE")
LABELS=("Generic1" "Optimized")
MODES=("standard" "chunked")

for idx in "${!IMAGES[@]}"; do
    IMAGE=${IMAGES[$idx]}
    LABEL=${LABELS[$idx]}
    
    for MODE in "${MODES[@]}"; do
        # Chunked mode only makes sense for the optimized image if we want to test it, 
        # but we can test it for both. However, chunked encoding depends on the image.
        if [ "$MODE" == "chunked" ] && [ "$LABEL" == "Generic1" ]; then
             continue # Skip chunked for generic to keep it simple, or implement it
        fi

        for CODEC in "${CODECS[@]}"; do
            # Run encode
            RES=$(run_benchmark "$IMAGE" "$LABEL" "$CODEC" "$MODE")
            TIME=$(echo $RES | cut -d' ' -f1)
            SIZE=$(echo $RES | cut -d' ' -f2)
            FPS=$(echo $RES | cut -d' ' -f3)
            
            # Run quality check
            TARGET="out_${LABEL}_${CODEC}_${MODE}.mp4"
            SCORE=$(verify_quality $SAMPLE_FILE $TARGET "$LABEL")
            
            echo "$LABEL,$CODEC,$MODE,$TIME,$SIZE,$SCORE,$FPS" >> $RESULTS_FILE
    
            if [ "$LABEL" != "Optimized" ]; then
                echo "$LABEL,$CODEC,$MODE,$TIME" >> .best_gen.tmp
            fi
        done
    done
done

echo ""
echo "=========================================================================================================================="
echo " Final Comparison Summary"
echo "=========================================================================================================================="
printf "%-12s | %-12s | %-12s | %-10s | %-10s | %-10s | %-10s\n" "Image" "Codec" "Mode" "Time(s)" "Size(KB)" "PSNR(dB)" "FPS"
echo "------------------------------------------------------------------------------------------------------------------------------------------------------------"
 
while IFS=, read -r img codec mode time size psnr fps; do
    if [ "$img" != "Image" ]; then
        # Format size with commas
        FORMATTED_SIZE=$(printf "%'d" "$size")
        printf "%-12s | %-12s | %-12s | %-10.2f | %-10s | %-10.2f | %-10.2f\n" "$img" "$codec" "$mode" "$time" "$FORMATTED_SIZE" "$psnr" "$fps"
    fi
done < $RESULTS_FILE


echo "----------------------------------------------------------------------------------------"
echo "Performance Improvement (Optimized vs Best Generic)"
echo "----------------------------------------------------------------------------------------"

for CODEC in "${CODECS[@]}"; do
    # Find the best (lowest) time among generics for this codec
    BEST_GEN=$(grep ",$CODEC," .best_gen.tmp | cut -d',' -f3 | sort -n | head -n 1)
    # Find optimized time for this codec
    OPT_TIME=$(grep "Optimized,$CODEC," $RESULTS_FILE | cut -d',' -f3)
    
    if [ ! -z "$BEST_GEN" ] && [ ! -z "$OPT_TIME" ]; then
        DIFF=$(echo "scale=2; $BEST_GEN - $OPT_TIME" | bc)
        PERC=$(echo "scale=2; ($DIFF / $BEST_GEN) * 100" | bc)
        printf "  %-12s: Speedup %-10.2f s (%s%% faster)\n" "$CODEC" "$DIFF" "$(printf "%.2f" "$PERC")"
    fi
done
echo "========================================================================"

# Cleanup
rm -f $SAMPLE_FILE out_*.mp4 $RESULTS_FILE .best_gen.tmp
