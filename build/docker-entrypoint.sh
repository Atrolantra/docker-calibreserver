#!/bin/bash

##
# FUNCTIONS
## 

function log {
    echo "$(date) docker-entrypoint.sh - ${@}"
}

function _term {
    # check for given parameters - first parameter = exit value
    retval=${1}
    [ -z ${retval} ] && retval=0
    log "received sigterm. aborting."
    log "send sigterm to calibre ${CALIBRE_PID}"
    kill -TERM ${CALIBRE_PID} 2>/dev/null

    if [ -n "${WATCH_PID}" ]; then
        log "send sigterm to watch script ${WATCH_PID}"
        kill -TERM ${WATCH_PID} 2>/dev/null
    fi

    log "all prcoesses stopped. bye"
    exit ${retval}
}

##
# TRAP
##

trap _term SIGTERM

##
# VARIABLES
##

# set the default parameters
CLI_PARAM=" --port=80 --pidfile=/tmp/calibre.pid --daemonize --log=/dev/stdout"

# set path to userdb - have a look at:
# https://manual.calibre-ebook.com/server.html#managing-user-accounts-from-the-command-line-only
[ -n "${USERDB}" ] && CLI_PARAM="${CLI_PARAM} --enable-auth --userdb=${USERDB}"

# if the URL_PREFIX is set set it
[ -n "${PREFIX_URL}" ] && CLI_PARAM="${CLI_PARAM} --url-prefix=${PREFIX_URL}"

# if the watch path is set we need to add some config and run the watch.sh script
if [ -n "${WATCH_PATH}" ]; then
    log "watch directory is set. preparing for watch.sh run"

    # enable local write for the calibre server
    CLI_PARAM="${CLI_PARAM} --enable-local-write"
    
    # check if interval is set. if not set it to 60 sec
    [ -z "${INTERVAL}" ] && INTERVAL=60
    # check if the library id is set - if not set it to the basename of the library_path
    [ -z "${LIBRARY_ID}" ] && LIBRARY_ID=$(basename ${LIBRARY_PATH})

    log "execute watch.sh"
    ONEBOOKPERDIR=${ONEBOOKPERDIR} WATCH_PATH=${WATCH_PATH} LIBRARY_ID=${LIBRARY_ID} INTERVAL=${INTERVAL} /watch.sh &

    # get the pid of the watch.sh process
    WATCH_PID=$!
    log "watch.sh started with PID ${WATCH_PID}"
fi

# start the calibre server
log "Starting calibre server with these cli parameters: $CLI_PARAM"
/usr/bin/calibre-server $CLI_PARAM ${LIBRARY_PATH}

# get the calibre pid
if [ ! -f /tmp/calibre.pid ]; then
    log "calibre pid file not found. aborting"
    _term 1
fi
CALIBRE_PID=$(cat /tmp/calibre.pid)
log "calibre server running with pid ${CALIBRE_PID}"

DBFILE="${LIBRARY_PATH}/metadata.db"
db_updateable=false
while true
do
    # now we just wait until we receive a sigterm
    sleep 3 &    # This script is not really doing anything.
    wait $!
	current=`date +%s`
	last_modified=`stat -c "%Y" ${DBFILE}`
	log "${db_updateable} top of loop"
	# watch for changes to metadata.db and restart server if changes
	if [ $(($current-$last_modified)) -gt 30 ]; then 
		log "setting updateable true"
		db_updateable=true
	else 
		if [ "$db_updateable" = true ]; then
			db_updateable=false
			log "${db_updateable} after set false"
			log "Restarting due to db changes"
			
			# stop
			kill -TERM ${CALIBRE_PID} 2>/dev/null
			log "Killed server"
			sleep 10 &
			wait $!
			
			# start the calibre server
			log "Starting calibre server with these cli parameters: $CLI_PARAM"
			/usr/bin/calibre-server $CLI_PARAM ${LIBRARY_PATH}

			# get the calibre pid
			if [ ! -f /tmp/calibre.pid ]; then
				log "calibre pid file not found. aborting"
				_term 1
			fi
			CALIBRE_PID=$(cat /tmp/calibre.pid)
			log "calibre server running with pid ${CALIBRE_PID}"
		fi
	fi
done
