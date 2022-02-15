#!/usr/bin/env bash

# default variables
DEFAULT_BC_ROOT='/Raft-Network'
DEFAULT_NODES=5
DEFAULT_NODE_IP=127.0.0.1
DEFAULT_AUTO_START=yes
DEFAULT_FORCE_CLEAN=no
DEFAULT_PASSWORD=''

# Override any value
ROOT_NODE="none"

# check to see if this file is being run or sourced from another script
_is_sourced() {
    # https://unix.stackexchange.com/a/215279
    [ "${#FUNCNAME[@]}" -ge 2 ] \
    && [ "${FUNCNAME[0]}" = '_is_sourced' ] \
    && [ "${FUNCNAME[1]}" = 'source' ]
}

# init BC_ROOT if unset
check_for_bc_root() {
    if [ -z "$BC_ROOT" ]
    then
        BC_ROOT=$DEFAULT_BC_ROOT
    fi
}

# init FORCE_CLEAN if unset
check_for_force_clean() {
    if [ -z "$FORCE_CLEAN" ]
    then
        FORCE_CLEAN=$DEFAULT_FORCE_CLEAN
    fi
}

# init NODE_IP if unset
check_for_node_ip() {
    if [ -z "$NODE_IP" ]
    then
        NODE_IP=$DEFAULT_NODE_IP
    fi
}

# init NODES if unset
check_for_nodes() {
    if [ -z "$NODES" ]
    then
        NODES=$DEFAULT_NODES
    fi
}

# init AUTO_START if unset
check_for_auto_start() {
    if [ -z "$AUTO_START" ]
    then
        AUTO_START=$DEFAULT_AUTO_START
    fi
}

# init PASSWORD if unset
check_for_password() {
    if [ -z "$PASSWORD" ]
    then
        PASSWORD=$DEFAULT_PASSWORD
    fi
}

# sleeper
sleeper() {
    if [ -z "$1" ]; then
        local TIME_OUT=30
    else
        local TIME_OUT=$1
    fi
    local TIME=0
    while [ $TIME -lt $TIME_OUT ]; 
    do
        echo -ne "Waitting $TIME"\\r
        sleep 1
        local TIME=$(($TIME+1))
    done
}

# check if server is root
is_server_root() {
    if [ ! -z "$(grep ROOT_ACCOUNT /docker-entrypoint-init/genesis.json)" ] \
    && [ ! -z "$(grep ROOT_ENODE /docker-entrypoint-init/genesis.json)" ];
    then
        ROOT_NODE="is_root"
    else
        ROOT_NODE="is_peer"
    fi
}

# init password file
init_password_file() {
    echo $PASSWORD > $BC_ROOT/password
}

# init genesis.json file
init_genesis_json_file() {
    cp /docker-entrypoint-init/genesis.json $BC_ROOT/genesis.json
    sed -i "s/ROOT_ACCOUNT/$1/g" $BC_ROOT/genesis.json
    sed -i "s/ROOT_ENODE/$2/g" $BC_ROOT/genesis.json
}

# init static_nodes.json file
# genesis.json must be initialized
init_static_nodes_json() {
    local NODE=0

    if [ "$ROOT_NODE" == "none" ]; then
        echo "NODE is not root or peer"
        exit 1
    fi

    if [ "$ROOT_NODE" == "is_root" ]; then
        echo "CLUSTER NODE IS ROOT"
        local NODE_DATA=$BC_ROOT/Node-$NODE/data
        local ROOT_ENODE=$(cat $NODE_DATA/enode)
        echo "[$ROOT_ENODE]" > $NODE_DATA/static-nodes.json
        local NODE=1
    fi

    if [ "$ROOT_NODE" == "is_peer" ]; then
        echo "CLUSTER NODE IS PEER"
        local ROOT_ENODE=$(cat $BC_ROOT/genesis.json | jq -r '.extraData' | xxd -r -c 256)
    fi

    while [ $NODE -lt $NODES ]; 
    do
        local NODE_DATA=$BC_ROOT/Node-$NODE/data
        local ENODE=$(cat $NODE_DATA/enode)
        echo "[$ROOT_ENODE, $ENODE]" > $NODE_DATA/static-nodes.json
        local NODE=$(($NODE+1))
    done
}

# init each node
# initialize genesis.json file
init_nodes() {
    local NODE=0
    while [ $NODE -lt $NODES ]; 
    do
        local NODE_DATA=$BC_ROOT/Node-$NODE/data
        mkdir -p $NODE_DATA
        bootnode --genkey=$BC_ROOT/Node-$NODE/data/nodekey
        local NODE_ID=$(bootnode --nodekey=$BC_ROOT/Node-$NODE/data/nodekey --writeaddress)
        local NODE_PORT=$(printf 210"%02d" $NODE)
        local NODE_RAFT_PORT=$(printf 500"%02d" $NODE)
        local ENODE="\"enode://$NODE_ID@$NODE_IP:$NODE_PORT?discport=0&raftport=$NODE_RAFT_PORT\""
        geth --datadir $BC_ROOT/Node-$NODE/data account new --password=$BC_ROOT/password
        local NODE_ACCOUNT=`ls $BC_ROOT/Node-$NODE/data/keystore | sed 's/^.*Z--//g' | sed 's/^/0x/'`
        
        if [ $NODE -eq 0 ]; then
            local ROOT_ACCOUNT=$NODE_ACCOUNT
            local ROOT_ENODE_HEX=0x$(echo $ENODE | xxd -p -c 1000000)
            init_genesis_json_file $ROOT_ACCOUNT $ROOT_ENODE_HEX
        fi

        echo "$ENODE" > $NODE_DATA/enode

        geth --datadir $NODE_DATA init $BC_ROOT/genesis.json
        local NODE=$(($NODE+1))
    done
}

# start root node
start_root_node() {
    local NODE=0
    local NODE_DATA=$BC_ROOT/Node-$NODE/data
    local NODE_PORT=$(printf 210"%02d" $NODE)
    local NODE_RPC_PORT=$(printf 220"%02d" $NODE)
    local NODE_RAFT_PORT=$(printf 500"%02d" $NODE)
    local NODE_LOG=$BC_ROOT/Node-$NODE/data/node.log
    nohup env PRIVATE_CONFIG=ignore geth --allow-insecure-unlock --datadir $NODE_DATA --nodiscover --verbosity 5 --networkid 31337 --raft --raftport $NODE_RAFT_PORT --rpc --rpccorsdomain="*" --rpcaddr 0.0.0.0 --rpcvhosts="*" --rpcport $NODE_RPC_PORT --rpcapi admin,db,eth,debug,miner,net,shh,txpool,personal,web3,quorum,raft --emitcheckpoints --port $NODE_PORT &> "$NODE_LOG" &
    sleeper 30
}

# start a single node node
start_node() {
    local NODE=$1
    local RAFT_ID=$(cat $BC_ROOT/Node-$NODE/data/raftId)
    local NODE_DATA=$BC_ROOT/Node-$NODE/data
    local NODE_PORT=$(printf 210"%02d" $NODE)
    local NODE_RPC_PORT=$(printf 220"%02d" $NODE)
    local NODE_RAFT_PORT=$(printf 500"%02d" $NODE)
    local NODE_LOG=$BC_ROOT/Node-$NODE/data/node.log
    nohup env PRIVATE_CONFIG=ignore geth --allow-insecure-unlock --datadir $NODE_DATA --nodiscover --verbosity 5 --networkid 31337 --raft --raftjoinexisting $RAFT_ID --raftport $NODE_RAFT_PORT --rpc --rpcaddr 0.0.0.0 --rpcvhosts="*" --rpcport $NODE_RPC_PORT --rpcapi admin,db,eth,debug,miner,net,shh,txpool,personal,web3,quorum,raft --emitcheckpoints --port $NODE_PORT &> "$NODE_LOG" &
    sleeper 5
}

init_raft_cluster_on_root() {
    local NODE=0
    local ROOT_NODE_DATA=$BC_ROOT/Node-$NODE/data
    echo "root" > $BC_ROOT/Node-$NODE/data/raftId
    local NODE=1
    while [ $NODE -lt $NODES ]; 
    do
        local NODE_DATA=$BC_ROOT/Node-$NODE/data
        local ENODE=$(cat $NODE_DATA/enode)
        local RAFT_ID=$(geth attach $ROOT_NODE_DATA/geth.ipc --exec "raft.addPeer($ENODE)")
        echo "NODE ($NODE) RAFT_ID_NODE: $RAFT_ID"
        echo $RAFT_ID > $BC_ROOT/Node-$NODE/data/raftId
        start_node $NODE
        local NODE=$(($NODE+1))
    done
}

init_raft_cluster_on_peer() {
    local NODE=0
    while [ $NODE -lt $NODES ]; 
    do
        local NODE_DATA=$BC_ROOT/Node-$NODE/data
        local ENODE=$(cat $NODE_DATA/enode)
        echo ""
        echo "For node ($NODE) - Run on root node:"
        echo ""
        echo "raft.addPeer($ENODE)"
        echo ""
        local RAFT_ID
        read -p "Enter [RaftId]:" RAFT_ID
        echo "NODE ($NODE) RAFT_ID_NODE ($RAFT_ID)"
        echo $RAFT_ID > $BC_ROOT/Node-$NODE/data/raftId
        start_node $NODE $RAFT_ID
        local NODE=$(($NODE+1))
    done
}

start_raft_cluster() {
    local NODE=0
    while [ $NODE -lt $NODES ]; 
    do
        local RAFT_ID=$(cat $BC_ROOT/Node-$NODE/data/raftId)
        if [ "$RAFT_ID" == "root" ]; then
            start_root_node
        else
            start_node $NODE
        fi
        local NODE=$(($NODE+1))
    done
}

# clean root
clean_data() {
    rm -rf $BC_ROOT/*
}

_main() {
    check_for_bc_root
    check_for_node_ip
    check_for_nodes
    check_for_auto_start
    check_for_force_clean
    is_server_root

    if [ "$FORCE_CLEAN" == "yes" ]; then
        clean_data
    fi

    local STAR_SCOPE="init"
    local GENESIS_FILE=$BC_ROOT/genesis.json
    if [ -f "$GENESIS_FILE" ]; then
        echo "$GENESIS_FILE exists."
        if [ "$AUTO_START" == "yes" ]; then
            start_raft_cluster
        fi
    else
        clean_data
        init_password_file
        init_nodes
        init_static_nodes_json
        if [ "$AUTO_START" == "yes" ] && [ "$ROOT_NODE" == "is_root" ]; then
            start_root_node
            init_raft_cluster_on_root
        fi

        if [ "$AUTO_START" == "yes" ] && [ "$ROOT_NODE" == "is_peer" ]; then
            init_raft_cluster_on_peer
        fi
    fi

    if [ "$AUTO_START" == "yes" ] && [ "$@" == "tail_main" ]; then
        tail -f $BC_ROOT/Node-0/data/node.log
    fi

    if [ "$@" == "tail_main" ]; then
        exec "bash"
    else
        exec "$@"
    fi
}

if ! _is_sourced; then
    _main "$@"
fi
