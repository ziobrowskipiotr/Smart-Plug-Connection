#!/bin/bash
# Script with logging functions

function LOG_DEBUG {
    echo "[SPC::DEBUG::$(date +'%Y-%m-%d %H:%M:%S')]: $1" >&2
}
function LOG_INFO {
    echo "[SPC::INFO::$(date +'%Y-%m-%d %H:%M:%S')]: $1" >&2
}

function LOG_WARN {
    echo "[SPC::WARN::$(date +'%Y-%m-%d %H:%M:%S')]: $1" >&2
}

function LOG_ERROR {
    echo "[SPC::ERROR::$(date +'%Y-%m-%d %H:%M:%S')]: $1" >&2
}

function LOG_FATAL {
    echo "[SPC::FATAL::$(date +'%Y-%m-%d %H:%M:%S')]: $1" >&2
    exit 1
}