#!/bin/bash
# Start tracker node, get initialization parameters from temporary file

echo "=== Starting Tracker Node ==="
echo ""

# PID file path
RUN_IN_SIM_PID_FILE="/tmp/run_in_sim.pid"
# Shared temporary file path
POSITION_TMP_FILE="/tmp/drone_position.tmp"

# Cleanup function
cleanup() {
    echo ""
    echo "=== Received interrupt signal, starting cleanup... ==="
    
    if [ -f "$RUN_IN_SIM_PID_FILE" ]; then
        RUN_IN_SIM_PID=$(cat "$RUN_IN_SIM_PID_FILE" 2>/dev/null)
        if [ ! -z "$RUN_IN_SIM_PID" ] && kill -0 "$RUN_IN_SIM_PID" 2>/dev/null; then
            echo "  Terminating run_in_sim.launch (PID: $RUN_IN_SIM_PID)"
            kill -TERM "$RUN_IN_SIM_PID" 2>/dev/null
            kill -KILL "$RUN_IN_SIM_PID" 2>/dev/null
        fi
        rm -f "$RUN_IN_SIM_PID_FILE"
    fi
    
    pkill -f "run_in_sim.launch" 2>/dev/null
    
    echo "=== Cleanup completed, script exiting ==="
    exit 1
}

# Register signal handlers
trap cleanup SIGINT SIGTERM SIGQUIT

# 1. Get initialization parameters from temporary file
echo "1. Getting initialization parameters from temporary file..."

# Set default values
INIT_X="0.0"
INIT_Y="0.0"
INIT_Z="2.0"
INIT_YAW="0.0"

# Check if temporary file exists
if [ -f "$POSITION_TMP_FILE" ]; then
    echo "  Found shared temporary file: $POSITION_TMP_FILE"
    
    # Read parameters from file
    if source "$POSITION_TMP_FILE" 2>/dev/null; then
        # Check if parameters are valid
        if [ ! -z "$INIT_X" ] && [ ! -z "$INIT_Y" ] && [ ! -z "$INIT_Z" ]; then
            echo "  Parameters read successfully: x=$INIT_X, y=$INIT_Y, z=$INIT_Z, yaw=$INIT_YAW rad"
        else
            echo "  ⚠ File parameter format error, using default values"
        fi
    else
        # If source fails, try manual parsing
        echo "  Attempting to parse file manually..."
        INIT_X=$(grep "^INIT_X=" "$POSITION_TMP_FILE" | cut -d'=' -f2 2>/dev/null | head -1)
        INIT_Y=$(grep "^INIT_Y=" "$POSITION_TMP_FILE" | cut -d'=' -f2 2>/dev/null | head -1)
        INIT_Z=$(grep "^INIT_Z=" "$POSITION_TMP_FILE" | cut -d'=' -f2 2>/dev/null | head -1)
        INIT_YAW=$(grep "^INIT_YAW=" "$POSITION_TMP_FILE" | cut -d'=' -f2 2>/dev/null | head -1)
        
        # Use defaults if parameters are empty
        if [ -z "$INIT_X" ] || [ -z "$INIT_Y" ] || [ -z "$INIT_Z" ]; then
            echo "  ⚠ Parameters missing, using default values"
            INIT_X="0.0"
            INIT_Y="0.0"
            INIT_Z="2.0"
            INIT_YAW="0.0"
        else
            echo "  Parameters read successfully: x=$INIT_X, y=$INIT_Y, z=$INIT_Z, yaw=$INIT_YAW rad"
        fi
    fi
else
    echo "  ⚠ Temporary file $POSITION_TMP_FILE not found, using default values"
fi

echo ""
echo "2. Launching run_in_sim.launch..."

# Enter ego-planner directory and launch
cd ego-planner
source devel/setup.sh

# Cleanup previous PID file
rm -f "$RUN_IN_SIM_PID_FILE"

# Launch run_in_sim.launch
roslaunch ego_planner run_in_sim.launch \
    init_x:="$INIT_X" \
    init_y:="$INIT_Y" \
    init_z:="$INIT_Z" \
    init_yaw:="$INIT_YAW" &
RUN_IN_SIM_PID=$!

echo $RUN_IN_SIM_PID > "$RUN_IN_SIM_PID_FILE"
echo "  run_in_sim.launch started (PID: $RUN_IN_SIM_PID)"

cd ..

echo ""
echo "=== ego-plan started ==="

# Wait for user to press Ctrl+C
wait
