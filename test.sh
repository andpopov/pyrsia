#!/usr/bin/env bash

echo "#######################################################"
echo "#"
echo "# Integration test including multiple authorized nodes"
echo "#"
echo "#######################################################"

PYRSIA_HOME=${1}
PYRSIA_BUILD_PIPELINE_HOME=${2}
TEST_DIR=/tmp/pyrsia-manual-tests

fatal()
{
  echo "fatal: $1" 1>&2
  exit 1
}

function build_pyrsia() {
    echo "Build PYRSIA"
    cd ${PYRSIA_HOME}
    cargo build --workspace
}

function build_pipeline() {
    echo "Build pyrsia build pipeline"
    cd ${PYRSIA_BUILD_PIPELINE_HOME}
    cargo build
}


function setup {
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

cd $PYRSIA_HOME

#set -x
#set -e

#start up pyrsia nodes
build_pipeline
build_pyrsia
setup
start_build_pipeline
start_nodeA "http://localhost:8080" 7881
start_nodeB "http://localhost:7881/status" "http://localhost:8080" 7882
start_regular_node nodeC "http://localhost:7881/status" 7883
start_regular_node nodeD "http://localhost:7882/status" 7884

list_started_processes
clear