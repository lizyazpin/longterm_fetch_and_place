#!/bin/bash

rosrun ltfnp_executive scripts/kill_type.sh roslaunch
rosrun ltfnp_executive scripts/kill_type.sh mongodb_log
rosrun ltfnp_executive scripts/kill_type.sh semrec
rosrun ltfnp_executive scripts/kill_type.sh gzserver
rosrun ltfnp_executive scripts/kill_type.sh gazebo
rosrun ltfnp_executive scripts/kill_type.sh /opt/ros/
rosrun ltfnp_executive scripts/kill_type.sh nav_pcontroller

killall gzclient -q
killall gzserver -q
