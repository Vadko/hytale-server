#!/bin/bash
set -e

cd "$SERVER_HOME"

# Auto-download if enabled and files don't exist
if [ "$AUTO_DOWNLOAD" = "true" ] && { [ ! -f "HytaleServer.jar" ] || [ ! -f "Assets.zip" ]; }; then
    echo "=============================================="
    echo "  DOWNLOADING SERVER FILES"
    echo "=============================================="
    echo ""
    echo "This will download the latest Hytale server."
    echo "You may need to authenticate..."
    echo ""
    
    # Download using official downloader
    if command -v hytale-downloader &> /dev/null; then
        echo "Downloading with hytale-downloader..."
        hytale-downloader --download-path /tmp/hytale-game.zip || {
            echo ""
            echo "=============================================="
            echo "  AUTHENTICATION REQUIRED"
            echo "=============================================="
            echo ""
            echo "Run this command to authenticate:"
            echo "  hytale-downloader --login"
            echo ""
            echo "Or download manually from https://hytale.com"
            echo "and place files in ./server folder:"
            echo "  - HytaleServer.jar"
            echo "  - Assets.zip"
            echo ""
            echo "Waiting for files..."
            echo "=============================================="
            
            # Wait for manual files
            while [ ! -f "HytaleServer.jar" ] || [ ! -f "Assets.zip" ]; do
                sleep 10
            done
        }
        
        # Extract if download succeeded
        if [ -f "/tmp/hytale-game.zip" ]; then
            echo "Extracting files..."
            unzip -o /tmp/hytale-game.zip -d /tmp/hytale-extract
            
            # Find and move files
            find /tmp/hytale-extract -name "HytaleServer.jar" -exec cp {} "$SERVER_HOME/" \;
            find /tmp/hytale-extract -name "Assets.zip" -exec cp {} "$SERVER_HOME/" \;
            
            rm -rf /tmp/hytale-game.zip /tmp/hytale-extract
            echo "Download complete!"
        fi
    fi
fi

# Final check - wait if still missing
if [ ! -f "HytaleServer.jar" ] || [ ! -f "Assets.zip" ]; then
    echo "=============================================="
    echo "  WAITING FOR SERVER FILES"
    echo "=============================================="
    echo ""
    echo "Place these files in ./server folder:"
    echo "  - HytaleServer.jar"
    echo "  - Assets.zip"
    echo ""
    echo "Download from: https://hytale.com"
    echo "Checking every 10 seconds..."
    echo "=============================================="
    
    while [ ! -f "HytaleServer.jar" ] || [ ! -f "Assets.zip" ]; do
        sleep 10
        if [ -f "HytaleServer.jar" ] && [ -f "Assets.zip" ]; then
            echo "Files found! Starting server..."
            break
        fi
    done
fi

echo ""
echo "=============================================="
echo "  Starting Hytale Server"
echo "=============================================="
echo "RAM: ${JAVA_XMS} - ${JAVA_XMX}"
echo "Bind: ${BIND_ADDR}:${BIND_PORT}/udp"
echo ""

# Base JVM flags
JAVA_FLAGS="-Xms${JAVA_XMS} -Xmx${JAVA_XMX}"

# G1GC optimizations
if [ "$USE_G1GC" = "true" ]; then
    JAVA_FLAGS="$JAVA_FLAGS \
        -XX:+UseG1GC \
        -XX:+ParallelRefProcEnabled \
        -XX:MaxGCPauseMillis=${MAX_GC_PAUSE_MILLIS:-200} \
        -XX:+UnlockExperimentalVMOptions \
        -XX:+DisableExplicitGC \
        -XX:G1NewSizePercent=${G1_NEW_SIZE_PERCENT:-30} \
        -XX:G1MaxNewSizePercent=${G1_MAX_NEW_SIZE_PERCENT:-40} \
        -XX:G1HeapRegionSize=${G1_HEAP_REGION_SIZE:-8M} \
        -XX:G1ReservePercent=20 \
        -XX:G1HeapWastePercent=5 \
        -XX:G1MixedGCCountTarget=4 \
        -XX:InitiatingHeapOccupancyPercent=15 \
        -XX:G1MixedGCLiveThresholdPercent=90 \
        -XX:G1RSetUpdatingPauseTimePercent=5 \
        -XX:SurvivorRatio=32 \
        -XX:+PerfDisableSharedMem \
        -XX:MaxTenuringThreshold=1"
fi

# AOT cache for faster startup
if [ -f "HytaleServer.aot" ]; then
    JAVA_FLAGS="$JAVA_FLAGS -XX:AOTCache=HytaleServer.aot"
    echo "Using AOT cache"
fi

# Custom JVM flags
if [ -n "$JAVA_EXTRA_FLAGS" ]; then
    JAVA_FLAGS="$JAVA_FLAGS $JAVA_EXTRA_FLAGS"
fi

# Build server arguments
SERVER_ARGS="--assets Assets.zip --bind ${BIND_ADDR}:${BIND_PORT}"

# Optional server arguments
if [ -n "$VIEW_DISTANCE" ]; then
    SERVER_ARGS="$SERVER_ARGS --view-distance $VIEW_DISTANCE"
fi

if [ -n "$MAX_PLAYERS" ]; then
    SERVER_ARGS="$SERVER_ARGS --max-players $MAX_PLAYERS"
fi

if [ -n "$SERVER_NAME" ]; then
    SERVER_ARGS="$SERVER_ARGS --name $SERVER_NAME"
fi

if [ -n "$SERVER_EXTRA_ARGS" ]; then
    SERVER_ARGS="$SERVER_ARGS $SERVER_EXTRA_ARGS"
fi

# Create command pipe for web panel
PIPE="/tmp/hytale-console"
rm -f "$PIPE"
mkfifo "$PIPE"
chmod 666 "$PIPE"

# Background process to read from pipe
(while true; do
    if read -r cmd < "$PIPE" 2>/dev/null; then
        echo "$cmd"
    fi
done) &
PIPE_PID=$!

trap "kill $PIPE_PID 2>/dev/null; rm -f $PIPE" EXIT

exec java $JAVA_FLAGS -jar HytaleServer.jar $SERVER_ARGS
