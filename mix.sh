#!/bin/bash
# Main control script: Start map generator and call corresponding scripts based on /task_id messages

echo "=== Main Control Script Starting ==="
echo ""

# PID file paths
MAP_GENERATOR_PID_FILE="/tmp/map_generator.pid"
STOP_SCRIPT_PID_FILE="/tmp/stop_script.pid"

# Startup script PID files
START_EGO_PID_FILE="/tmp/start_ego.pid"
START_TRACK_PID_FILE="/tmp/start_track.pid"
START_TRACK_CAR_PID_FILE="/tmp/start_track_car.pid"
START_PERCH_PID_FILE="/tmp/start_perch.pid"

# Status marker files
LAST_TASK_ID_FILE="/tmp/last_task_id.txt"
FIRST_EXECUTION_FLAG="/tmp/first_execution.flag"

# Message deduplication variables
last_message_hash=""
last_processed_time=0
MIN_PROCESS_INTERVAL=0.5  # Minimum processing interval (seconds)

# Cleanup function
cleanup() {
    echo ""
    echo "=== Received interrupt signal, starting cleanup... ==="
    
    # Cleanup startup script processes
    if [ -f "$START_EGO_PID_FILE" ]; then
        START_EGO_PID=$(cat "$START_EGO_PID_FILE" 2>/dev/null)
        if [ ! -z "$START_EGO_PID" ] && kill -0 "$START_EGO_PID" 2>/dev/null; then
            echo "  Terminating start_ego.sh process (PID: $START_EGO_PID)"
            kill -TERM "$START_EGO_PID" 2>/dev/null
            sleep 0.5
            kill -KILL "$START_EGO_PID" 2>/dev/null 2>/dev/null
        fi
        rm -f "$START_EGO_PID_FILE"
    fi
    
    if [ -f "$START_TRACK_PID_FILE" ]; then
        START_TRACK_PID=$(cat "$START_TRACK_PID_FILE" 2>/dev/null)
        if [ ! -z "$START_TRACK_PID" ] && kill -0 "$START_TRACK_PID" 2>/dev/null; then
            echo "  Terminating start_track.sh process (PID: $START_TRACK_PID)"
            kill -TERM "$START_TRACK_PID" 2>/dev/null
            sleep 0.5
            kill -KILL "$START_TRACK_PID" 2>/dev/null 2>/dev/null
        fi
        rm -f "$START_TRACK_PID_FILE"
    fi
    
    if [ -f "$START_TRACK_CAR_PID_FILE" ]; then
        START_TRACK_CAR_PID=$(cat "$START_TRACK_CAR_PID_FILE" 2>/dev/null)
        if [ ! -z "$START_TRACK_CAR_PID" ] && kill -0 "$START_TRACK_CAR_PID" 2>/dev/null; then
            echo "  Terminating track_car.sh process (PID: $START_TRACK_CAR_PID)"
            kill -TERM "$START_TRACK_CAR_PID" 2>/dev/null
            sleep 0.5
            kill -KILL "$START_TRACK_CAR_PID" 2>/dev/null 2>/dev/null
        fi
        rm -f "$START_TRACK_CAR_PID_FILE"
    fi
    
    # Cleanup start_perch.sh process
    if [ -f "$START_PERCH_PID_FILE" ]; then
        START_PERCH_PID=$(cat "$START_PERCH_PID_FILE" 2>/dev/null)
        if [ ! -z "$START_PERCH_PID" ] && kill -0 "$START_PERCH_PID" 2>/dev/null; then
            echo "  Terminating start_perch.sh process (PID: $START_PERCH_PID)"
            kill -TERM "$START_PERCH_PID" 2>/dev/null
            sleep 0.5
            kill -KILL "$START_PERCH_PID" 2>/dev/null 2>/dev/null
        fi
        rm -f "$START_PERCH_PID_FILE"
    fi
    
    # Cleanup child script processes
    if [ -f "$STOP_SCRIPT_PID_FILE" ]; then
        STOP_SCRIPT_PID=$(cat "$STOP_SCRIPT_PID_FILE" 2>/dev/null)
        if [ ! -z "$STOP_SCRIPT_PID" ] && kill -0 "$STOP_SCRIPT_PID" 2>/dev/null 2>/dev/null; then
            echo "  Terminating child script process (PID: $STOP_SCRIPT_PID)"
            kill -TERM "$STOP_SCRIPT_PID" 2>/dev/null
            sleep 0.5
            kill -KILL "$STOP_SCRIPT_PID" 2>/dev/null 2>/dev/null
        fi
        rm -f "$STOP_SCRIPT_PID_FILE"
    fi
    
    # Cleanup map generator process
    if [ -f "$MAP_GENERATOR_PID_FILE" ]; then
        MAP_PID=$(cat "$MAP_GENERATOR_PID_FILE" 2>/dev/null)
        if [ ! -z "$MAP_PID" ] && kill -0 "$MAP_PID" 2>/dev/null 2>/dev/null; then
            echo "  Terminating map_generator.launch (PID: $MAP_PID)"
            kill -TERM "$MAP_PID" 2>/dev/null
            sleep 0.5
            kill -KILL "$MAP_PID" 2>/dev/null 2>/dev/null
        fi
        rm -f "$MAP_GENERATOR_PID_FILE"
    fi
    
    # Cleanup perching related processes
    if [ -f "/tmp/perching.pid" ]; then
        PERCH_PID=$(cat "/tmp/perching.pid" 2>/dev/null)
        if [ ! -z "$PERCH_PID" ] && kill -0 "$PERCH_PID" 2>/dev/null; then
            echo "  Terminating perching.launch (PID: $PERCH_PID)"
            kill -TERM "$PERCH_PID" 2>/dev/null
            sleep 0.5
            kill -KILL "$PERCH_PID" 2>/dev/null 2>/dev/null
        fi
        rm -f "/tmp/perching.pid"
    fi
    
    # Cleanup possible related processes
    pkill -f "map_generator.launch" 2>/dev/null
    pkill -f "rostopic echo /task_id" 2>/dev/null
    pkill -f "perching.launch" 2>/dev/null
    
    # Cleanup processes started by stop_ego.sh and stop_tracker.sh
    if [ -f "/tmp/fake_target.pid" ]; then
        FAKE_PID=$(cat "/tmp/fake_target.pid" 2>/dev/null)
        if [ ! -z "$FAKE_PID" ] && kill -0 "$FAKE_PID" 2>/dev/null 2>/dev/null; then
            echo "  Terminating fake_target.launch (PID: $FAKE_PID)"
            kill -TERM "$FAKE_PID" 2>/dev/null
        fi
        rm -f "/tmp/fake_target.pid"
    fi
    
    if [ -f "/tmp/simulation1.pid" ]; then
        SIM_PID=$(cat "/tmp/simulation1.pid" 2>/dev/null)
        if [ ! -z "$SIM_PID" ] && kill -0 "$SIM_PID" 2>/dev/null 2>/dev/null; then
            echo "  Terminating simulation1.launch (PID: $SIM_PID)"
            kill -TERM "$SIM_PID" 2>/dev/null
        fi
        rm -f "/tmp/simulation1.pid"
    fi
    
    if [ -f "/tmp/run_in_sim.pid" ]; then
        RUN_PID=$(cat "/tmp/run_in_sim.pid" 2>/dev/null)
        if [ ! -z "$RUN_PID" ] && kill -0 "$RUN_PID" 2>/dev/null 2>/dev/null; then
            echo "  Terminating run_in_sim.launch (PID: $RUN_PID)"
            kill -TERM "$RUN_PID" 2>/dev/null
        fi
        rm -f "/tmp/run_in_sim.pid"
    fi
    
    # Cleanup status files
    rm -f "$FIRST_EXECUTION_FLAG"
    
    # Clear last_task_id file (newly added)
    echo "Clearing last_task_id file..."
    rm -f "$LAST_TASK_ID_FILE"
    
    echo "=== Cleanup completed, script exiting ==="
    exit 0
}

# Register signal handlers
trap cleanup SIGINT SIGTERM SIGQUIT

# Startup helper functions
start_ego_plan() {
    echo "Starting ego-plan..."
    
    cd ego-planner
    source devel/setup.sh
    
    # Cleanup previous PID file
    RUN_IN_SIM_PID_FILE="/tmp/run_in_sim.pid"
    rm -f "$RUN_IN_SIM_PID_FILE"
    
    # Launch with default parameters
    echo "Launching run_in_sim.launch..."
    roslaunch ego_planner run_in_sim.launch &
    RUN_IN_SIM_PID=$!
    echo $RUN_IN_SIM_PID > "$RUN_IN_SIM_PID_FILE"
    echo "  run_in_sim.launch started (PID: $RUN_IN_SIM_PID)"
    
    cd ..
}

start_track() {
    echo "Starting track..."
    
    cd Elastic-Tracker
    source devel/setup.sh
    
    # Cleanup previous PID files
    FAKE_TARGET_PID_FILE="/tmp/fake_target.pid"
    SIMULATION_PID_FILE="/tmp/simulation1.pid"
    rm -f "$FAKE_TARGET_PID_FILE" "$SIMULATION_PID_FILE"
    
    # Launch fake_target.launch
    echo "Launching fake_target.launch..."
    roslaunch planning fake_target.launch &
    FAKE_TARGET_PID=$!
    echo $FAKE_TARGET_PID > "$FAKE_TARGET_PID_FILE"
    echo "  fake_target.launch started (PID: $FAKE_TARGET_PID)"
    
    # Launch simulation1.launch (with default parameters)
    echo "Launching simulation1.launch..."
    roslaunch planning simulation1.launch &
    SIMULATION_PID=$!
    echo $SIMULATION_PID > "$SIMULATION_PID_FILE"
    echo "  simulation1.launch started (PID: $SIMULATION_PID)"
    
    # Publish trigger message
    echo "Publishing trigger message..."
    rostopic pub -1 /triger geometry_msgs/PoseStamped "{
  header: {
    seq: 0,
    stamp: {
      secs: 0,
      nsecs: 0
    },
    frame_id: ''
  },
  pose: {
    position: {
      x: 0.0,
      y: 0.0,
      z: 0.0
    },
    orientation: {
      x: 0.0,
      y: 0.0,
      z: 0.0,
      w: 0.0
    }
  }
}" >/dev/null 2>&1 
    
    echo "  Trigger message published"
    cd ..
}

start_track_car() {
    echo "Starting track-car..."
    
    cd Elastic-Tracker
    source devel/setup.sh
    
    # Cleanup previous PID files
    FAKE_TARGET_PID_FILE="/tmp/fake_target.pid"
    SIMULATION_PID_FILE="/tmp/simulation1.pid"
    rm -f "$FAKE_TARGET_PID_FILE" "$SIMULATION_PID_FILE"
    
    # Launch fake_car_target.launch
    echo "Launching fake_car_target.launch..."
    roslaunch planning fake_car_target.launch &
    FAKE_TARGET_PID=$!
    echo $FAKE_TARGET_PID > "$FAKE_TARGET_PID_FILE"
    echo "  fake_car_target.launch started (PID: $FAKE_TARGET_PID)"
    
    # Launch simulation1.launch (with default parameters)
    echo "Launching simulation1.launch..."
    roslaunch planning simulation1.launch &
    SIMULATION_PID=$!
    echo $SIMULATION_PID > "$SIMULATION_PID_FILE"
    echo "  simulation1.launch started (PID: $SIMULATION_PID)"
    
    # Publish trigger message
    echo "Publishing trigger message..."
    rostopic pub -1 /triger geometry_msgs/PoseStamped "{
  header: {
    seq: 0,
    stamp: {
      secs: 0,
      nsecs: 0
    },
    frame_id: ''
  },
  pose: {
    position: {
      x: 0.0,
      y: 0.0,
      z: 0.0
    },
    orientation: {
      x: 0.0,
      y: 0.0,
      z: 0.0,
      w: 0.0
    }
  }
}" >/dev/null 2>&1 
    
    echo "  Trigger message published"
    cd ..
}

# New: Start perch function
start_perch() {
    echo "Starting perch..."
    
    cd Fast-Perching
    source devel/setup.sh
    
    # Cleanup previous PID file
    PERCHING_PID_FILE="/tmp/perching.pid"
    rm -f "$PERCHING_PID_FILE"
    
    # Launch with default parameters
    echo "Launching perching.launch..."
    roslaunch planning perching.launch &
    PERCHING_PID=$!
    echo $PERCHING_PID > "$PERCHING_PID_FILE"
    echo "  perching.launch started (PID: $PERCHING_PID)"
    
    cd ..
}

send_land_command() {
    echo "Sending land command..."
    
    echo "Executing: rostopic pub /land_triger geometry_msgs/PoseStamped ..."
    
    rostopic pub -1 /land_triger geometry_msgs/PoseStamped "header:
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
    w: 1.0" >/dev/null 2>&1
    
    echo "  Land command sent"
}

# 1. Start map generator
echo "1. Starting map generator..."
cd ego-planner
source devel/setup.sh

# Cleanup previous PID files
rm -f "$MAP_GENERATOR_PID_FILE"
rm -f "$START_EGO_PID_FILE"
rm -f "$START_TRACK_PID_FILE"
rm -f "$START_TRACK_CAR_PID_FILE"
rm -f "$START_PERCH_PID_FILE"

roslaunch ego_planner map_generator.launch &
MAP_GENERATOR_PID=$!
echo $MAP_GENERATOR_PID > "$MAP_GENERATOR_PID_FILE"
echo "  map_generator.launch started (PID: $MAP_GENERATOR_PID)"

cd ..
sleep 3

echo ""
echo "2. Starting to listen to /task_id messages..."
echo "   Waiting for task commands:"
echo "   Press Ctrl+C to exit script"
echo ""

# Initialize last task ID
last_task_id=""
if [ -f "$LAST_TASK_ID_FILE" ]; then
    last_task_id=$(cat "$LAST_TASK_ID_FILE" 2>/dev/null)
fi

# Set initial state to first execution
rm -f "$FIRST_EXECUTION_FLAG"
touch "$FIRST_EXECUTION_FLAG"
first_execution=true

# Loop to listen to /task_id messages
while true; do
    # Listen to /task_id topic, wait for new messages
    echo "Listening to /task_id messages..."
    
    # Use rostopic echo to get latest message (10 second timeout)
    task_msg=$(timeout 10 rostopic echo -n 1 /task_id 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$task_msg" ]; then
        # Calculate message hash
        current_hash=$(echo "$task_msg" | md5sum | cut -d' ' -f1)
        
        # Check processing interval
        current_time=$(date +%s.%N)
        time_diff=$(echo "$current_time - $last_processed_time" | bc)
        
        # Check if duplicate message (same hash) and processing interval too short
        if [ "$current_hash" != "$last_message_hash" ] || \
           [ $(echo "$time_diff >= $MIN_PROCESS_INTERVAL" | bc -l) -eq 1 ]; then
            last_message_hash="$current_hash"
            last_processed_time=$current_time
            
            # Extract task_id value
            current_task_id=$(echo "$task_msg" | grep "data:" | awk '{print $2}' | tr -d '\n\r')
            
            if [ ! -z "$current_task_id" ]; then
                echo ""
                echo "=== Received new task command: task_id=$current_task_id ==="
                echo "Last task ID: $last_task_id"
                
                # Check if task switching is needed
                if [ ! -z "$last_task_id" ] && [ "$last_task_id" != "$current_task_id" ]; then
                    echo "Detected task switch: $last_task_id -> $current_task_id"
                    
                    # Only execute stop script when not switching from 3 to 4
                    if [ "$last_task_id" = "3" ] && [ "$current_task_id" = "4" ]; then
                        echo "Switching from track-car to land command, skipping stop script"
                    else
                        # Execute stop script based on last task ID
                        if [ "$last_task_id" = "1" ]; then
                            # Cleanup old stop script PID file
                            rm -f "$STOP_SCRIPT_PID_FILE"
                            
                            echo "Executing stop_ego.sh..."
                            if [ -f "./stop_ego.sh" ]; then
                                ./stop_ego.sh &
                                STOP_SCRIPT_PID=$!
                                echo $STOP_SCRIPT_PID > "$STOP_SCRIPT_PID_FILE"
                                echo "  stop_ego.sh started (PID: $STOP_SCRIPT_PID)"
                                
                                # Wait for stop script to complete
                                wait $STOP_SCRIPT_PID 2>/dev/null
                                echo "stop_ego.sh execution completed"
                            else
                                echo "Warning: stop_ego.sh script not found"
                            fi
                            
                        elif [ "$last_task_id" = "2" ]; then
                            # Cleanup old stop script PID file
                            rm -f "$STOP_SCRIPT_PID_FILE"
                            
                            echo "Executing stop_track.sh..."
                            if [ -f "./stop_track.sh" ]; then
                                ./stop_track.sh &
                                STOP_SCRIPT_PID=$!
                                echo $STOP_SCRIPT_PID > "$STOP_SCRIPT_PID_FILE"
                                echo "  stop_track.sh started (PID: $STOP_SCRIPT_PID)"
                                
                                # Wait for stop script to complete
                                wait $STOP_SCRIPT_PID 2>/dev/null
                                echo "stop_track.sh execution completed"
                            else
                                echo "Warning: stop_track.sh script not found"
                            fi
                            
                        elif [ "$last_task_id" = "3" ]; then
                            # Cleanup old stop script PID file
                            rm -f "$STOP_SCRIPT_PID_FILE"
                            
                            echo "Executing stop_track.sh ..."
                            if [ -f "./stop_track.sh" ]; then
                                ./stop_track.sh &
                                STOP_SCRIPT_PID=$!
                                echo $STOP_SCRIPT_PID > "$STOP_SCRIPT_PID_FILE"
                                echo "  stop_track.sh started (PID: $STOP_SCRIPT_PID)"
                                
                                # Wait for stop script to complete
                                wait $STOP_SCRIPT_PID 2>/dev/null
                                echo "stop_track.sh execution completed"
                            else
                                echo "Warning: stop_track.sh script not found"
                            fi
                        elif [ "$last_task_id" = "5" ]; then
                            # Cleanup old stop script PID file
                            rm -f "$STOP_SCRIPT_PID_FILE"
                            
                            echo "Executing stop_perch.sh..."
                            if [ -f "./stop_perch.sh" ]; then
                                ./stop_perch.sh &
                                STOP_SCRIPT_PID=$!
                                echo $STOP_SCRIPT_PID > "$STOP_SCRIPT_PID_FILE"
                                echo "  stop_perch.sh started (PID: $STOP_SCRIPT_PID)"
                                
                                # Wait for stop script to complete
                                wait $STOP_SCRIPT_PID 2>/dev/null
                                echo "stop_perch.sh execution completed"
                            else
                                echo "Warning: stop_perch.sh script not found"
                            fi
                        fi
                        
                        # Cleanup stop script PID file
                        rm -f "$STOP_SCRIPT_PID_FILE"
                    fi
                fi
                
                # Start corresponding system or execute land command based on current task ID
                if [ "$current_task_id" = "1" ]; then
                    echo "Executing task: Start ego-plan"
                    
                    if [ "$first_execution" = true ]; then
                        echo "First execution, directly starting ego-plan..."
                        start_ego_plan
                        first_execution=false
                        rm -f "$FIRST_EXECUTION_FLAG"
                    else
                        echo "Not first execution, checking if startup needed..."
                        if [ "$last_task_id" != "1" ]; then
                            echo "Switching from other task, starting ego-plan..."
                            # Start start_ego.sh and record PID
                            rm -f "$START_EGO_PID_FILE"
                            ./start_ego.sh &
                            START_EGO_PID=$!
                            echo $START_EGO_PID > "$START_EGO_PID_FILE"
                            echo "  start_ego.sh started (PID: $START_EGO_PID)"
                        else
                            echo "Already in ego-plan task, skipping startup"
                        fi
                    fi
                    
                    # Save current task ID
                    echo "$current_task_id" > "$LAST_TASK_ID_FILE"
                    last_task_id="$current_task_id"
                    
                elif [ "$current_task_id" = "2" ]; then
                    echo "Executing task: Start track"
                    
                    if [ "$first_execution" = true ]; then
                        echo "First execution, directly starting track..."
                        start_track
                        first_execution=false
                        rm -f "$FIRST_EXECUTION_FLAG"
                    else
                        echo "Not first execution, checking if startup needed..."
                        if [ "$last_task_id" != "2" ]; then
                            echo "Switching from other task, starting track..."
                            # Start start_track.sh and record PID
                            rm -f "$START_TRACK_PID_FILE"
                            ./start_track.sh &
                            START_TRACK_PID=$!
                            echo $START_TRACK_PID > "$START_TRACK_PID_FILE"
                            echo "  start_track.sh started (PID: $START_TRACK_PID)"
                        else
                            echo "Already in track task, skipping startup"
                        fi
                    fi
                    
                    # Save current task ID
                    echo "$current_task_id" > "$LAST_TASK_ID_FILE"
                    last_task_id="$current_task_id"
                    
                elif [ "$current_task_id" = "3" ]; then
                    echo "Executing task: Start track-car"
                    
                    if [ "$first_execution" = true ]; then
                        echo "First execution, directly starting track-car..."
                        start_track_car
                        first_execution=false
                        rm -f "$FIRST_EXECUTION_FLAG"
                    else
                        echo "Not first execution, checking if startup needed..."
                        if [ "$last_task_id" != "3" ]; then
                            echo "Switching from other task, starting track-car..."
                            # Start start_track_car.sh and record PID
                            rm -f "$START_TRACK_CAR_PID_FILE"
                            ./start_track_car.sh &
                            START_TRACK_CAR_PID=$!
                            echo $START_TRACK_CAR_PID > "$START_TRACK_CAR_PID_FILE"
                            echo "  start_track_car.sh started (PID: $START_TRACK_CAR_PID)"
                        else
                            echo "Already in start_track-car task, skipping startup"
                        fi
                    fi
                    
                    # Save current task ID
                    echo "$current_task_id" > "$LAST_TASK_ID_FILE"
                    last_task_id="$current_task_id"
                    
                elif [ "$current_task_id" = "4" ]; then
                    echo "Executing task: Send land command"
                    
                    # Execute land command
                    send_land_command
                    
                    # Don't update last_task_id, maintain original task state
                    echo "Note: Land command sent, task status remains unchanged"
                    echo "Currently still in task: $last_task_id"
                    
                elif [ "$current_task_id" = "5" ]; then
                    echo "Executing task: Start perch"
                    
                    if [ "$first_execution" = true ]; then
                        echo "First execution, directly starting perch..."
                        start_perch
                        first_execution=false
                        rm -f "$FIRST_EXECUTION_FLAG"
                    else
                        echo "Not first execution, checking if startup needed..."
                        if [ "$last_task_id" != "5" ]; then
                            echo "Switching from other task, starting perch..."
                            # Start start_perch.sh and record PID
                            rm -f "$START_PERCH_PID_FILE"
                            ./start_perch.sh &
                            START_PERCH_PID=$!
                            echo $START_PERCH_PID > "$START_PERCH_PID_FILE"
                            echo "  start_perch.sh started (PID: $START_PERCH_PID)"
                        else
                            echo "Already in perch task, skipping startup"
                        fi
                    fi
                    
                    # Save current task ID
                    echo "$current_task_id" > "$LAST_TASK_ID_FILE"
                    last_task_id="$current_task_id"
                    
                else
                    echo "Unknown task_id: $current_task_id, ignoring this message"
                fi
                
                echo "=== Task execution completed, continuing to listen... ==="
                echo ""
            fi
        else
            echo "Ignoring duplicate or high-frequency message (hash: $current_hash)"
            # Short delay to avoid high CPU usage
            sleep 0.1
        fi
    else
        # Timeout or no message, continue listening
        sleep 0.5
    fi
done

# Script normally won't reach here
cleanup
