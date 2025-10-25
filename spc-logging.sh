#!/bin/bash
# Script with logging functions

# Default tag for syslog if not set by caller
: ${LOG_TAG:="SPC"}

function LOG_DEBUG {
    logger -t "$LOG_TAG" -p "user.debug" "[DEBUG]: $1"
    echo "[SPC::DEBUG]: $1" >&2
}

function LOG_INFO {
    logger -t "$LOG_TAG" -p "user.info" "[INFO]: $1"
}

function LOG_WARN {
    logger -t "$LOG_TAG" -p "user.warning" "[WARN]: $1"
}

function LOG_ERROR {
    logger -t "$LOG_TAG" -p "user.err" "[ERROR]: $1"
}

function LOG_FATAL {
    logger -t "$LOG_TAG" -p "user.crit" "[FATAL]: $1"
    exit 1
}