#!/usr/bin/env bash

echo "#######################################################"
echo "#"
echo "# Integration test including multiple authorized nodes"
echo "#"
echo "#######################################################"

fatal()
{
  echo "fatal: $1" 1>&2
  exit 1
}

function start_build_pipeline() {
    echo "Starting pyrsia build pipeline process"
    cd $PYRSIA_BUILD_PIPELINE_HOME
    local pid_file="$TEST_DIR/build_pipeline.pid"
    (./target/debug/pyrsia_build) &
    local pid=$!
    echo $pid >$pid_file
}

function start_nodeA() {
    local pipeline_service_endpoint=$1
    local port=$2

    local node=nodeA

    echo "Starting authorizing node ${node}"
    local pid_file="$TEST_DIR/${node}.pid"
    local output_log="$TEST_DIR/${node}.log"
    cd $TEST_DIR/${node}
    (RUST_LOG=pyrsia=debug DEV_MODE=on ./pyrsia_node --pipeline-service-endpoint ${pipeline_service_endpoint}  --listen-only -H 0.0.0.0 -p ${port} --init-blockchain &>${output_log}) &
    local pid=$!
    echo $pid >$pid_file
}

function start_nodeB() {
    local bootstrap_url=$1
    local pipeline_service_endpoint=$2
    local port=$3

    local node=nodeB

    echo "Starting authorizing node ${node}"
    local pid_file="$TEST_DIR/${node}.pid"
    local output_log="$TEST_DIR/${node}.log"
    cd $TEST_DIR/${node}
    (RUST_LOG=debug ./pyrsia_node --bootstrap-url ${bootstrap_url} --pipeline-service-endpoint ${pipeline_service_endpoint} -p ${port} &>${output_log}) &
    local pid=$!
    echo $pid >$pid_file
}

function start_regular_node() {
    local node=$1
    local bootstrap_url=$2
    local port=$3

    echo "Starting regular ${node}"
    local pid_file="$TEST_DIR/${node}.pid"
    local output_log="$TEST_DIR/${node}.log"
    cd $TEST_DIR/${node}
    (RUST_LOG=debug ./pyrsia_node --bootstrap-url ${bootstrap_url} -p ${port} &>${output_log}) &
    local pid=$!
    echo $pid >$pid_file
}

function clear() {
    for pidfile in $TEST_DIR/*.pid; do
        read pid <$pidfile
        kill $pid
    done
}

function list_started_processes() {
    local pidlist=""
    for pidfile in $TEST_DIR/*.pid; do
        read pid <$pidfile
        if [ ! -z "$pidlist" ] ; then 
            pidlist="$pidlist,"; 
        fi
        pidlist="$pidlist$pid";
    done
    echo -e "\nPyrsia processes:"
    ps -u -q $pidlist
}

function wait_status_ok() {
    local PORT=$1
    local MAX_WAITING_TIME=2
    
    while [ $MAX_WAITING_TIME -ne 0 ]
    do
        local PEER_ID=`curl -s http://localhost:${PORT}/status | jq -r .peer_id`
        if [ -z "$PEER_ID" ]
        then
            sleep 1
            ((MAX_WAITING_TIME-=1))
        else
            echo "PEER_ID=$PEER_ID"
            break
        fi
    done

    if [ $MAX_WAITING_TIME -eq 0 ]
    then
        fatal "Port ${PORT} is not reachable"
    fi
}

function setup_environment {
    echo "Build pyrsia workspace"
    cd ${PYRSIA_HOME}
    cargo build --workspace

    echo "Build pyrsia pipeline"
    cd ${PYRSIA_BUILD_PIPELINE_HOME}
    cargo build

    if [[ -d $TEST_DIR ]]
    then
        rm -rf $TEST_DIR
    fi
    for node in nodeA nodeB nodeC nodeD
    do
        local dir=${TEST_DIR}/${node}
        mkdir -p $dir || fatal "Could not create directory: \"${dir}\""
        cp ${PYRSIA_HOME}/target/debug/pyrsia_node ${TEST_DIR}/${node}
    done

    start_build_pipeline
    sleep 5

    start_nodeA "http://localhost:8080" 7881
    wait_status_ok 7881

    start_nodeB "http://localhost:7881/status" "http://localhost:8080" 7882
    wait_status_ok 7882    

    start_regular_node nodeC "http://localhost:7881/status" 7883
    wait_status_ok 7883

    start_regular_node nodeD "http://localhost:7882/status" 7884
    wait_status_ok 7884

    list_started_processes
}

#set -x
set -e

PYRSIA_HOME=${1}
PYRSIA_BUILD_PIPELINE_HOME=${2}
TEST_DIR=/tmp/pyrsia-manual-tests

setup_environment

# clear
# exit 0
# set up the authorized nodes:
cd $PYRSIA_HOME
NODE_A_PEER_ID=`curl -s http://localhost:7881/status | jq -r .peer_id`
NODE_B_PEER_ID=`curl -s http://localhost:7882/status | jq -r .peer_id`
echo "NODE_A_PEER_ID=$NODE_A_PEER_ID"
echo "NODE_B_PEER_ID=$NODE_B_PEER_ID"
./target/debug/pyrsia config -e --port 7881
sleep 3
./target/debug/pyrsia authorize --peer $NODE_A_PEER_ID
sleep 3
./target/debug/pyrsia authorize --peer $NODE_B_PEER_ID
sleep 3

clear