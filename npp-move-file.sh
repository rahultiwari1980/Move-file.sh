[root@psy6jumpux01 scrpt]# cat npp-move-file.sh
#!/bin/bash -x

###################################################################################################
#                                  move-file-when-stable.sh
# ---------------------------------------------------------------------------------------------
#
# Purpose: Check for any files in the watch list looping over each one for a maximum
#          of $WATCH_RETRY x $WATCH_TIME seconds waiting for it's ctime to stop changing
#          for 1 $WATCH_TIME interval. When all files are stable they are moved to $DESTDIR
#
#          Optionally the target file name can include $PREFIX or $SUFFIX
#          For PREFIX & SUFFIX #mm, #hh, #ss, #DD, #MM, #YY & #YYYY are reserved and
#          will be expanded to corresponding date format string
#
#          Optionally the ownership and group of the moved file can be set to OWNER
#          and GROUP
#
#          Optionally the permissions of the moved file can be set to PERMS
#
#          Logging is to STDOUT only - redirect at invocation and housekeep seperately
#
#          Locking is per configuration file invocation
#
#          Enhanced from $/Operations/Linux/DMZSFTP/bpay-in-watch.sh by Jim Liu

# Configuration:
# Compulsory Variables - WATCH_LIST, WATCH_RETRY, WATCH_TIME, DESTDIR
# Optional Variables - PREFIX, SUFFIX, MAIL_ENABLE, MAIL_MSG, MAIL_SUBJ, MAIL_TO
#
# Configuration file specified as $1 must provide valid values e.g:
#
# WATCH_LIST="/var/sftproot/sftpuser/a.dat
# /var/sftproot/sftpuser/b.dat
# /var/sftproot/sftpuser/c.dat
# "
#
# WATCH_LIST="*"
#
# DESTDIR="/app/incoming"


# WATCH_RETRY=25 # 25 retries
# WATCH_TIME=10  # 10 second steady state interval
#
# PREFIX="bak_"
# SUFFIX="#DD#MM#YYYY-#hh#mm#ss"
#
# OWNER="bob"
# GROUP="users"
#
# OWNER="DESTDIR_OWNER
# GROUP="DESTDIR_GROUP
#
# PERMS=754
#
# MAIL_ENABLE=1
# MAIL_MSG="$0 failed, please check log /var/log/wibs/pgp.log"
# MAIL_SUBJ="${HOSTNAME} cron job to move files from WIBS Status: <FAILURE> DO_NOT_REPLY "
# MAIL_TO="unixteam service.centre@ingdirect.com.au"
#
# TO DO:
#        Enhance WATCH_LIST to be an associative array of watched file key with desired destination value

# Version History: Daniel Leonard 28/07/2017 - v1.0 Initial
#
#
#######################################################################################################


WATCH_FILES () {
  if [ $MAIL_ENABLE = 1 ] ; then # Other mail vars should also be defined
    [ -z "$MAIL_MSG" ] && MAIL_MSG="$PGM failed! Custom mail message not defined in configurataion file ${CONFF}. Also check if recipients need updating"
    [ -z "$MAIL_SUBJ" ] && MAIL_SUBJ="$PGM failed!"
    [ -z "$MAIL_TO" ] && MAIL_TO="unixteam"
  fi
  TIMESTR0='null'
  OIFS="$IFS"
  IFS=$'\n'
  for FILE in $WATCH_LIST
  do
   [[ -f "$FILE" ]] && RWLIST=$(echo -e "${RWLIST}\n${FILE}")
  done

  if [[ $RWLIST ]]; then
    echo -e "\n==> $(date)"
    echo -e "INFO: Files found:\n $RWLIST"
  else
    #echo  "INFO: no file found"
    return 2
  fi

  for (( i=1; i<=$WATCH_RETRY; i++ ))
  do
    TIMESTR=""
    #combine all timestamp of files into a string
    for FILE in $RWLIST
    do
      TIMESTR=${TIMESTR}"-"$( ls  -l -t -Q --time=ctime --time-style=+%s "$FILE" | awk '{print $6}' | sed '/^$/d' | paste -s -d- )
      #timestamp in secs should be long than 10 digits
      [[ ${#TIMESTR} -lt 10 ]] && return 1
    done

    if [[ $TIMESTR == $TIMESTR0 ]]; then
      FILEOK=1
      break
    else
      TIMESTR0=$TIMESTR
    fi
    echo -e "INFO: monitoring file status of $RWLIST  [ Iteration $i ] \n"
    echo "INFO: sleeping for $WATCH_TIME seconds"
    sleep $WATCH_TIME
    done # for (( i=1; i<=$WATCH_RETRY; i++ ))

if [[ $FILEOK -eq 1 ]]; then
  echo "INFO: Found files are stable. No modification for at least $WATCH_TIME seconds"
  return 0
else
  ERROR="ERROR: Found files are not stable. Still being modified after $((WATCH_RETRY*WATCH_TIME)) seconds:\n\n$(ls -lath --full-time $RWLIST)"
  [ $MAIL_ENABLE = 1 ] && echo -e "${MAIL_MSG}\n\n${ERROR}" | mailx -s "$MAIL_SUBJ" "$MAIL_TO"
  echo -e "${ERROR}"
  return 1
fi
}


PGM=$0
PREFIX=
SUFFIX=
MAIL_ENABLE=0
CONFF="$1"
LOCKF="/var/lock/$(echo $CONFF | sed "s#/#_#g").lck"
if [ -f "$LOCKF" ] ; then
  INFO="Lock file for $PGM with $CONFF already exists. Exiting.."
  echo "$INFO"
  [ $MAIL_ENABLE = 1 ] && echo -e "${MAIL_MSG}\n\n${INFO}" | mailx -s "$MAIL_SUBJ" "$MAIL_TO"
  exit 0
else
  touch "$LOCKF"
fi
source "$CONFF"


WATCH_FILES ; RC=$?
if [[ $RC -eq 0 ]]; then
  for FILE in $RWLIST
  do
    FNAME=$(basename "$FILE")
    if [ ! -z "$PREFIX" -o ! -z "$SUFFIX" ] ; then
      HR=$(date +%H)
      MIN=$(date +%M)
      SEC=$(date +%S)
      YYYY=$(date +%Y)
      MON=$(date +%m)
      DAY=$(date +%d)

      if [ ! -z $PREFIX ] ; then
        FPREFIX=$(echo $PREFIX | sed -e "s/#DD/$DAY/g" -e "s/#MM/$MON/g" -e "s/#YYYY/$YYYY/g" -e "s/#hh/$HR/g" -e "s/#mm/$MIN/g" -e "s/#ss/$SEC/g")
        FNAME="${FPREFIX}${FNAME}"
      fi
      if [ ! -z $SUFFIX ] ; then
        FSUFFIX=$(echo $SUFFIX | sed -e "s/#DD/$DAY/g" -e "s/#MM/$MON/g" -e "s/#YYYY/$YYYY/g" -e "s/#hh/$HR/g" -e "s/#mm/$MIN/g" -e "s/#ss/$SEC/g")
        FNAME="${FNAME}${FSUFFIX}"
      fi
      fi
    echo "INFO:  mv $FILE ${DESTDIR}/${FNAME}"
    mv $FILE ${DESTDIR}/${FNAME} ; RC=$?
    if [ $RC -ne 0 ] ; then
      ERROR="ERROR: mv $FILE ${DESTDIR}/${FNAME} failed!"
      [ $MAIL_ENABLE = 1 ] && echo -e "${MAIL_MSG}\n\n${ERROR}" | mailx -s "$MAIL_SUBJ" "$MAIL_TO"
      echo -e "${ERROR}"
    fi
    if [ ! -z "$OWNER" -a ! -z "$GROUP" ] ; then
      if [ "$OWNER" = "DESTDIR_OWNER" -a "$GROUP" = "DESTDIR_GROUP" ] ; then
        FOWNER=$(stat -c '%U' ${DESTDIR})
        FGROUP=$(stat -c '%G' ${DESTDIR})
      else
        FOWNER="$OWNER"
        FGROUP="$GROUP"
      fi
      chown ${FOWNER}:${FGROUP} ${DESTDIR}/${FNAME} ; RC=$?
      if [ $RC -ne 0 ] ; then
        ERROR="ERROR: chown ${FOWNER}:${FGROUP} ${DESTDIR}/${FNAME} failed!"
        [ $MAIL_ENABLE = 1 ] && echo -e "${MAIL_MSG}\n\n${ERROR}" | mailx -s "$MAIL_SUBJ" "$MAIL_TO"
        echo -e "${ERROR}"
      fi
    fi
    if [ ! -z $PERMS ] ; then
      chmod ${PERMS} ${DESTDIR}/${FNAME} ; RC=$?
      if [ $RC -ne 0 ] ; then
        ERROR="ERROR: chmod ${PERMS} ${DESTDIR}/${FNAME} failed!"
        [ $MAIL_ENABLE = 1 ] && echo -e "${MAIL_MSG}\n\n${ERROR}" | mailx -s "$MAIL_SUBJ" "$MAIL_TO"
        echo -e "${ERROR}"
      fi
    fi

  done
fi

IFS="$OIFS"
rm "$LOCKF"

exit $RC
