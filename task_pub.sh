#!/bin/bash
# task_pub.sh - ROS1 Task Publisher Script (task_id: 1-5)

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if roscore is running
check_ros() {
    if ! rostopic list > /dev/null 2>&1; then
        echo -e "${RED}Error: roscore is not running!${NC}"
        echo "Please run: roscore"
        exit 1
    fi
    echo -e "${GREEN}✓ ROS core is running${NC}"
}

# Ask for confirmation
ask_confirmation() {
    local prompt=$1
    while true; do
        read -p "$prompt [Y/N]: " answer
        case $answer in
            [Yy]* ) return 0;;  # Yes
            [Nn]* ) return 1;;  # No
            * ) echo -e "${YELLOW}Please answer Y or N.${NC}";;
        esac
    done
}

# Publish trigger message (single message with -1 flag)
publish_trigger() {
    echo -e "${CYAN}Publishing trigger message to /triger...${NC}"
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
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Trigger published successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to publish trigger${NC}"
        return 1
    fi
}

# Publish land trigger message (single message with -1 flag)
publish_land_trigger() {
    echo -e "${PURPLE}Publishing land trigger to /land_triger...${NC}"
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
    w: 1.0"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Land trigger published successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to publish land trigger${NC}"
        return 1
    fi
}

# Handle task_id 2
handle_task_2() {
    echo -e "${YELLOW}Task 2: Elastic-Tracker (one_drone)${NC}"
    if ask_confirmation "Start tracking?"; then
        publish_trigger
    else
        echo -e "${BLUE}Tracking cancelled for task 2${NC}"
    fi
}

# Handle task_id 3
handle_task_3() {
    echo -e "${YELLOW}Task 3: Elastic-Tracker (two_drones)${NC}"
    if ask_confirmation "Start tracking?"; then
        publish_trigger
    else
        echo -e "${BLUE}Tracking cancelled for task 3${NC}"
    fi
}

# Handle task_id 4
handle_task_4() {
    echo -e "${YELLOW}Task 4: Elastic-Tracker (drone+car)${NC}"
    
    # First step: tracking
    if ask_confirmation "Start tracking?"; then
        if publish_trigger; then
            # Immediately ask about landing after successful trigger publish
            if ask_confirmation "Start landing?"; then
                publish_land_trigger
            else
                echo -e "${BLUE}Landing cancelled${NC}"
            fi
        fi
    else
        echo -e "${BLUE}Tracking cancelled for task 4${NC}"
    fi
}

# Publish basic task_id
publish_basic_task() {
    local task_id=$1
    local task_name=""
    
    case $task_id in
        1) task_name="Ego-Planner";;
        2) task_name="Elastic-Tracker: one_drone";;
        3) task_name="Elastic-Tracker: two_drones";;
        4) task_name="Elastic-Tracker: drone+car";;
        5) task_name="Fast-Perching";;
    esac
    
    echo -e "${YELLOW}Publishing task_id=$task_id [$task_name]...${NC}"
    
    rostopic pub -1 /task_id std_msgs/Int32 "data: $task_id"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Successfully published task_id=$task_id${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to publish${NC}"
        return 1
    fi
}

# Display menu
show_menu() {
    clear
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${YELLOW}           ROS Task Publisher${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo -e "Select task_id to publish:"
    echo -e "  ${GREEN}1${NC} - Publish task_id=1 ${YELLOW}[Ego-Planner]${NC}"
    echo -e "  ${GREEN}2${NC} - Publish task_id=2 ${YELLOW}[Elastic-Tracker: one_drone]${NC}"
    echo -e "  ${GREEN}3${NC} - Publish task_id=3 ${YELLOW}[Elastic-Tracker: two_drones]${NC}"
    echo -e "  ${GREEN}4${NC} - Publish task_id=4 ${YELLOW}[Elastic-Tracker: drone+car]${NC}"
    echo -e "  ${GREEN}5${NC} - Publish task_id=5 ${YELLOW}[Fast-Perching]${NC}"
    echo -e "  ${RED}q${NC} - Quit program"
    echo -e "${BLUE}==========================================${NC}"
}

# Main function
main() {
    # Check ROS environment
    check_ros
    
    while true; do
        show_menu
        
        # Read user input
        read -p "Select [1-5/q]: " choice
        
        case $choice in
            1)
                if publish_basic_task 1; then
                    echo -e "${GREEN}✓ Ego-Planner task initiated${NC}"
                fi
                ;;
            2)
                if publish_basic_task 2; then
                    handle_task_2
                fi
                ;;
            3)
                if publish_basic_task 3; then
                    handle_task_3
                fi
                ;;
            4)
                if publish_basic_task 4; then
                    handle_task_4
                fi
                ;;
            5)
                if publish_basic_task 5; then
                    echo -e "${GREEN}✓ Fast-Perching task initiated${NC}"
                fi
                ;;
            q|Q)
                echo -e "${BLUE}Exiting program...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid selection, please try again!${NC}"
                ;;
        esac
        
        # Wait for key press to continue
        echo ""
        echo -e "${BLUE}------------------------------------------${NC}"
        read -n 1 -s -p "Press any key to return to menu..."
    done
}

# Start main function
main
