#!/bin/bash

# Store PIDs of background processes
declare -a PIDS=()

# Ctrl+C signal handler
cleanup() {
    echo -e "\nInterrupt received, cleaning up all background processes..."
    
    # 1. First clean up our specifically recorded processes
    for pid in "${PIDS[@]}"; do
        if [ -n "$pid" ] && kill -0 $pid 2>/dev/null; then
            echo "Terminating process $pid"
            # Try normal termination first
            kill -15 $pid 2>/dev/null
            sleep 0.5
            # Force kill if still running
            if kill -0 $pid 2>/dev/null; then
                kill -9 $pid 2>/dev/null
            fi
        fi
    done
    
    # 2. Clean up process groups (very important!)
    # Many ROS nodes create child processes, need to clean entire process group
    for pid in "${PIDS[@]}"; do
        if [ -n "$pid" ] && kill -0 $pid 2>/dev/null; then
            # Terminate entire process group
            kill -9 -$pid 2>/dev/null
        fi
    done
    
    # 3. Clean up all ROS-related processes (by type)
    echo "Cleaning up all ROS-related processes..."
    
    # Clean up specific nodes first
    pkill -f "fake_target.launch" 2>/dev/null
    pkill -f "simulation1.launch" 2>/dev/null
    pkill -f "simulation2.launch" 2>/dev/null
    pkill -f "simulation_landing.launch" 2>/dev/null
    pkill -f "fake_car_target.launch" 2>/dev/null
    pkill -f "map_generator.launch" 2>/dev/null
    pkill -f "run_in_sim.launch" 2>/dev/null
    pkill -f "perching.launch" 2>/dev/null
    
    # Clean up all roslaunch processes
    pkill -f "roslaunch" 2>/dev/null
    sleep 1
    pkill -9 -f "roslaunch" 2>/dev/null
    
    # Clean up all rosmaster/roscore processes
    pkill -f "rosmaster" 2>/dev/null
    pkill -f "roscore" 2>/dev/null
    sleep 1
    pkill -9 -f "rosmaster" 2>/dev/null
    pkill -9 -f "roscore" 2>/dev/null
    
    # Clean up rviz
    pkill -f "rviz" 2>/dev/null
    sleep 0.5
    pkill -9 -f "rviz" 2>/dev/null
    
    # 4. Clean up rosout and rosclean
    pkill -f "rosout" 2>/dev/null
    pkill -f "rosclean" 2>/dev/null
    
    # 5. Clean up specific scripts
    pkill -f "pub_triger.sh" 2>/dev/null
    pkill -f "land_triger.sh" 2>/dev/null
    
    # 6. Final cleanup of any remaining processes
    echo "Cleaning up residual processes..."
    # Clean up all python processes (many ROS nodes are Python-based)
    pkill -f "python.*ros" 2>/dev/null
    pkill -f "python.*planning" 2>/dev/null
    pkill -f "python.*ego" 2>/dev/null
    pkill -f "python.*perching" 2>/dev/null
    
    # 7. Clean up port occupancy (optional)
    echo "Cleaning up occupied ports..."
    # If roscore occupies port 11311
    fuser -k 11311/tcp 2>/dev/null
    
    # 8. Wait for all processes to truly terminate
    sleep 2
    
    echo "All processes terminated"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Clean up possible residual processes before starting
echo "Checking and cleaning up possible residual processes..."
cleanup_residual() {
    pkill -f "roslaunch" 2>/dev/null
    pkill -f "roscore" 2>/dev/null
    pkill -f "rviz" 2>/dev/null
    sleep 1
}
cleanup_residual

# Start map_generator.launch
echo "Starting map_generator.launch..."
cd ego-planner
source devel/setup.sh

# Use process group for easier cleanup
setsid roslaunch ego_planner map_generator.launch &
LAUNCH_PID=$!
PIDS+=($LAUNCH_PID)

# Wait for launch file to fully start
echo "Waiting for map_generator.launch to fully start..."
sleep 5

# Check if map_generator started successfully
if ! kill -0 $LAUNCH_PID 2>/dev/null; then
    echo "Error: map_generator.launch failed to start!"
    cleanup
    exit 1
fi

# Get all child process PIDs started by roslaunch
sleep 2
ROS_PIDS=$(ps -o pid= --ppid $LAUNCH_PID 2>/dev/null || ps -o pid= --ppid $(ps -o ppid= -p $LAUNCH_PID 2>/dev/null | tr -d ' ') 2>/dev/null)
for pid in $ROS_PIDS; do
    PIDS+=($pid)
done

# Wait for Rviz to start
echo "Waiting for Rviz to start..."
RVIZ_READY=0
MAX_WAIT=8
WAIT_COUNT=0

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if pgrep -f "rviz" > /dev/null; then
        echo "Rviz started"
        RVIZ_READY=1
        # Record Rviz PID
        RVIZ_PID=$(pgrep -f "rviz")
        PIDS+=($RVIZ_PID)
        break
    fi
    
    echo "Waiting for Rviz to start... ($((WAIT_COUNT+1))/$MAX_WAIT seconds)"
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT+1))
done

if [ $RVIZ_READY -eq 0 ]; then
    echo "Warning: Rviz not detected within $MAX_WAIT seconds, but continuing..."
fi

sleep 2

echo "map_generator.launch successfully started"
echo "Now starting to get task_id message..."

# Attempt multiple times to get task_id
echo "Attempting to get task_id message..."
task_id=""
MAX_RETRIES=10
RETRY_COUNT=0

while [ -z "$task_id" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Attempting to get task_id... (Attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
    
    task_id=$(rostopic echo -n 1 /task_id 2>/dev/null | grep -E "data:|data" | head -1 | grep -oE '[0-9]+')
    
    if [ -z "$task_id" ]; then
        sleep 2
    fi
    
    RETRY_COUNT=$((RETRY_COUNT+1))
done

# If still not obtained, prompt user for input
if [ -z "$task_id" ]; then
    echo "========================================="
    echo "Warning: Unable to automatically obtain task_id from ROS topic"
    rostopic list 2>/dev/null | head -20
    echo ""
    echo "Please manually enter task_id (1,2,3,4,5):"
    read task_id
else
    echo "Successfully obtained task_id from ROS message: $task_id"
fi

# Validate if task_id is valid (modified to 1-5)
if ! [[ "$task_id" =~ ^[1-5]$ ]]; then
    echo "Error: Invalid task_id, please enter a number between 1-5"
    cleanup
    exit 1
fi

# Execute different operations based on task_id
case "$task_id" in
    1)
        echo "task_id=1, starting run_in_sim.launch..."
        cd ego-planner
        # Use process group
        setsid roslaunch ego_planner run_in_sim.launch &
        SIM_PID=$!
        PIDS+=($SIM_PID)
        
        # Get child processes
        sleep 2
        SIM_CHILD_PIDS=$(ps -o pid= --ppid $SIM_PID 2>/dev/null)
        for pid in $SIM_CHILD_PIDS; do
            PIDS+=($pid)
        done
        
        wait $SIM_PID
        SIM_EXIT_CODE=$?
        
        if [ $SIM_EXIT_CODE -ne 0 ]; then
            echo "Error: run_in_sim.launch failed to start!"
            cleanup
            exit 1
        fi
        
        echo "run_in_sim.launch successfully started"
        ;;
    
    2)
        echo "task_id=2, starting Elastic-Tracker related nodes..."
        
        cd ..
        cd Elastic-Tracker
        source devel/setup.sh
        
        # Start fake_target.launch
        echo "Starting fake_target.launch..."
        setsid roslaunch planning fake_target.launch &
        FAKE_PID=$!
        PIDS+=($FAKE_PID)
        sleep 3
        
        # Start simulation1.launch
        echo "Starting simulation1.launch..."
        setsid roslaunch planning simulation1.launch &
        SIM1_PID=$!
        PIDS+=($SIM1_PID)
        sleep 3
        
        echo "All Elastic-Tracker nodes started. Press Ctrl+C to terminate all programs."
        
        # Show all currently running processes
        echo "Currently running background process PIDs: ${PIDS[@]}"
        
        # Wait for all background processes
        wait
        ;;
    
    3)
        echo "task_id=3, starting Elastic-Tracker simulation2 related nodes..."
        
        cd ..
        cd Elastic-Tracker
        source devel/setup.sh
        
        echo "Starting fake_target.launch..."
        setsid roslaunch planning fake_target.launch &
        FAKE_PID=$!
        PIDS+=($FAKE_PID)
        sleep 3
        
        echo "Starting simulation2.launch..."
        setsid roslaunch planning simulation2.launch &
        SIM2_PID=$!
        PIDS+=($SIM2_PID)
        sleep 3
        
        echo "All Elastic-Tracker simulation2 nodes started. Press Ctrl+C to terminate all programs."
        echo "Currently running background process PIDs: ${PIDS[@]}"
        
        wait
        ;;
    
    4)
        echo "task_id=4, starting Elastic-Tracker landing related nodes..."
        
        cd ..
        cd Elastic-Tracker
        source devel/setup.sh
        
        echo "Starting fake_car_target.launch..."
        setsid roslaunch planning fake_car_target.launch &
        FAKE_CAR_PID=$!
        PIDS+=($FAKE_CAR_PID)
        sleep 3
        
        echo "Starting simulation_landing.launch..."
        setsid roslaunch planning simulation_landing.launch &
        LANDING_PID=$!
        PIDS+=($LANDING_PID)
        sleep 3
        
        echo "All Elastic-Tracker landing nodes started. Press Ctrl+C to terminate all programs."
        echo "Currently running background process PIDs: ${PIDS[@]}"
        
        wait
        ;;
    
    5)
        echo "task_id=5, starting Fast-Perching related nodes..."
        
        cd ..
        cd Fast-Perching
        source devel/setup.sh
        
        echo "Starting perching.launch..."
        setsid roslaunch planning perching.launch &
        PERCHING_PID=$!
        PIDS+=($PERCHING_PID)
        sleep 3

        # Start perching
        echo "Starting perching..."
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
        TRIGGER_PID=$!
        PIDS+=($TRIGGER_PID)
        
        echo "Fast-Perching nodes started. Press Ctrl+C to terminate all programs."
        echo "Currently running background process PIDs: ${PIDS[@]}"
       
        wait
        ;;
    
    *)
        echo "Error: Unknown task_id"
        cleanup
        exit 1
        ;;
esac

echo "Script execution completed"
