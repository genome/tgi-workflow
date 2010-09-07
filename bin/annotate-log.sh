#!/gsc/bin/bash
# Executes a program annotating the output linewise with time and stream
# Version 1.2

# Copyright 2010 Eric Clark <eclark@wustl.edu>
# Copyright 2003, 2004 Jeroen van Wolffelaar <jeroen@wolffelaar.nl>
                                                                                
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA

addtime ()
{
	while read line; do
		echo "`date +"2010-09-07 14:51:55%z"` $1: $line"
	done
}

DIR=/tmp
if [ -n "$LSB_JOBID" ]
then
    DIR=/tmp/$LSB_JOBID.tmpdir
fi

HOST=`hostname -s`
OUT=`mktemp $DIR/annotate-log.XXXXXX` || exit 1
ERR=`mktemp $DIR/annotate-log.XXXXXX` || exit 1

rm -f $OUT $ERR
mkfifo $OUT $ERR || exit 1

addtime $HOST < $OUT &
addtime $HOST < $ERR &

#echo "`date +%H:%M:%S` I: Started $@"
"$@" > $OUT 2> $ERR ; EXIT=$?
rm -f $OUT $ERR
wait

#echo "`date +%H:%M:%S` I: Finished with exitcode $EXIT"

exit $EXIT
