#!/bin/bash
# Start track node, support RViz point selection to set target initial position (car version)

echo "=== Starting Track Node (Car Target) ==="
echo ""

# PID file paths
FAKE_TARGET_PID_FILE="/tmp/fake_target.pid"
SIMULATION_PID_FILE="/tmp/simulation1.pid"
CLICKED_POINT_FILE="/tmp/clicked_point.tmp"

# Cleanup function
cleanup() {
    echo ""
    echo "=== Received interrupt signal, starting cleanup... ==="
    
    # Cleanup point selection listener
    if [ ! -z "$POINT_LISTENER_PID" ] && kill -0 "$POINT_LISTENER_PID" 2>/dev/null; then
        echo "  Terminating point selection listener (PID: $POINT_LISTENER_PID)"
        kill -TERM "$POINT_LISTENER_PID" 2>/dev/null
    fi
    
    # Cleanup other processes
    if [ -f "$FAKE_TARGET_PID_FILE" ]; then
        FAKE_TARGET_PID=$(cat "$FAKE_TARGET_PID_FILE" 2>/dev/null)
        if [ ! -z "$FAKE_TARGET_PID" ] && kill -0 "$FAKE_TARGET_PID" 2>/dev/null; then
            echo "  Terminating fake_car_target.launch (PID: $FAKE_TARGET_PID)"
            kill -TERM "$FAKE_TARGET_PID" 2>/dev/null
        fi
        rm -f "$FAKE_TARGET_PID_FILE"
    fi
    
    if [ -f "$SIMULATION_PID_FILE" ]; then
        SIMULATION_PID=$(cat "$SIMULATION_PID_FILE" 2>/dev/null)
        if [ ! -z "$SIMULATION_PID" ] && kill -0 "$SIMULATION_PID" 2>/dev/null; then
            echo "  Terminating simulation1.launch (PID: $SIMULATION_PID)"
            kill -TERM "$SIMULATION_PID" 2>/dev/null
        fi
        rm -f "$SIMULATION_PID_FILE"
    fi
    
    pkill -f "fake_car_target.launch" 2>/dev/null
    pkill -f "simulation1.launch" 2>/dev/null
    rm -f "$CLICKED_POINT_FILE"
    
    echo "=== Cleanup completed, script exiting ==="
    exit 1
}

# Register signal handlers
trap cleanup SIGINT SIGTERM SIGQUIT

# 1. Target initial position setup - only supports RViz point selection
echo "1. Target initial position setup:"
echo "  Please use Publish Point tool in RViz to click on map to set target position..."
echo "  Waiting 30 seconds, if no point selected use default position (x=2, y=0, z=0.8)"
        
# Cleanup old point selection file
rm -f "$CLICKED_POINT_FILE"
        
# Start point selection listener (listen only once)
echo "  Starting point selection listener (waiting 30 seconds)..."
rostopic echo -n 1 /clicked_point > "$CLICKED_POINT_FILE" &
POINT_LISTENER_PID=$!
        
# Wait for point selection or timeout
TIMEOUT=30
POINT_RECEIVED=false
for i in $(seq 1 $TIMEOUT); do
    if [ -s "$CLICKED_POINT_FILE" ]; then
        POINT_RECEIVED=true
        break
    fi
    sleep 1
    echo -n "."
done
echo ""
        
# Stop listener
if [ ! -z "$POINT_LISTENER_PID" ] && kill -0 "$POINT_LISTENER_PID" 2>/dev/null; then
    kill -TERM "$POINT_LISTENER_PID" 2>/dev/null
fi
        
if [ "$POINT_RECEIVED" = true ]; then
    # Parse selected point position, only get x,y, z uses value from original launch file
    X=$(grep "x:" "$CLICKED_POINT_FILE" | awk '{print $2}')
    Y=$(grep "y:" "$CLICKED_POINT_FILE" | awk '{print $2}')
    
    if [ ! -z "$X" ] && [ ! -z "$Y" ]; then
        TARGET_X="$X"
        TARGET_Y="$Y"
        echo "  Selected point position: x=$TARGET_X, y=$TARGET_Y, z=0.8 (fixed)"
    else
        echo "  ⚠ Unable to parse selected point position, using default values"
        TARGET_X="2"
        TARGET_Y="0"
    fi
else
    echo "  ⚠ No point selected, using default values"
    TARGET_X="2"
    TARGET_Y="0"
fi
        
# Cleanup point selection file
rm -f "$CLICKED_POINT_FILE"

# 2. Drone initial position setup - keep original logic unchanged
echo ""
echo "2. Drone initial position setup (using original script logic)..."

# Read temporary file from original script (if exists)
POSITION_TMP_FILE="/tmp/drone_position.tmp"
if [ -f "$POSITION_TMP_FILE" ]; then
    echo "  Reading drone position from temporary file..."
    # Try to source file
    if source "$POSITION_TMP_FILE" 2>/dev/null; then
        echo "  Parameters read successfully"
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
            echo "  Parameters read successfully"
        fi
    fi
else
    echo "  ⚠ Temporary file $POSITION_TMP_FILE not found, using default values"
    INIT_X="0.0"
    INIT_Y="0.0"
    INIT_Z="2.0"
    INIT_YAW="0.0"
fi

echo ""
echo "=== Startup Parameters ==="
echo "  Target (car) position: x=$TARGET_X, y=$TARGET_Y, z=0.8"
echo "  UAV position: x=$INIT_X, y=$INIT_Y, z=$INIT_Z, yaw=$INIT_YAW rad"

# Start new node
cd Elastic-Tracker
source devel/setup.sh

# Cleanup previous PID files
rm -f "$FAKE_TARGET_PID_FILE" "$SIMULATION_PID_FILE"

echo ""
echo "3. Launching fake_car_target.launch..."
# Directly pass parameters in launch command
roslaunch planning fake_car_target.launch \
    init_x:="$TARGET_X" \
    init_y:="$TARGET_Y" &
FAKE_TARGET_PID=$!
echo $FAKE_TARGET_PID > "$FAKE_TARGET_PID_FILE"
echo "  fake_car_target.launch started (PID: $FAKE_TARGET_PID)"

echo ""
echo "4. Launching simulation1.launch..."
# Drone part uses original parameter names unchanged
roslaunch planning simulation1.launch \
    init_x_:="$INIT_X" \
    init_y_:="$INIT_Y" \
    init_z_:="$INIT_Z" \
    init_yaw_:="$INIT_YAW" &
SIMULATION_PID=$!
echo $SIMULATION_PID > "$SIMULATION_PID_FILE"
echo "  simulation1.launch started (PID: $SIMULATION_PID)"

cd ..

echo ""
echo "5. Publishing trigger message..."
rostopic pub -1 /triger geometry_msgs/PoseStamped "header:
  seq: 0
  stamp:
    secs: 0
    nsecs: 0
  frame_id: ''
pose:
  position:
    x: 0.0
    y: 0.0
    z: 0.0
  orientation:
    x: 0.0
    y: 0.0
    z: 0.0
    w: 0.0"

echo "  Trigger message published"

echo ""
echo "=== track-car started ==="
echo "Target (car) position: ($TARGET_X, $TARGET_Y, 0.8)"
echo "UAV start position: ($INIT_X, $INIT_Y, $INIT_Z, yaw=$INIT_YAW)"

# Wait for user to press Ctrl+C
wait
