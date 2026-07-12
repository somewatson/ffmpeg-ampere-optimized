import subprocess
import sys
import re
import os

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 ffmpeg_filter.py <log_file> <command>")
        sys.exit(1)

    log_file_path = sys.argv[1]
    command = " ".join(sys.argv[2:])

    # Open log file for writing
    with open(log_file_path, "w") as log_file:
        # Use subprocess.Popen with stderr=subprocess.STDOUT to merge streams
        # We use a shell=True because the command passed from benchmark.sh contains quotes/vars
        process = subprocess.Popen(
            command,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0, # Unbuffered
            universal_newlines=False # Read bytes to handle \r correctly
        )

        buffer = b""
        while True:
            char = process.stdout.read(1)
            if not char:
                break
            
            log_file.write(char.decode('utf-8', errors='ignore'))
            
            if char == b'\r':
                # We hit a line update, search for fps/time in the current buffer
                line = buffer.decode('utf-8', errors='ignore')
                # Regex to find fps=... and time=...
                fps_match = re.search(r'fps=[0-9.]+', line)
                time_match = re.search(r'time=[0-9:.]+', line)
                
                if fps_match or time_match:
                    output = ""
                    if time_match:
                        output += f"{time_match.group(0)} "
                    if fps_match:
                        output += fps_match.group(0)
                    
                    if output:
                        sys.stdout.write(f"\r{output}")
                        sys.stdout.flush()
                
                buffer = b""
            else:
                buffer += char

        process.wait()
        sys.stdout.write("\n") # Final newline

if __name__ == "__main__":
    main()
