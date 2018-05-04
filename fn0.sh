#!/bin/bash
if [[ $* == '--help' ]]; then
echo 'Usage: fn0 {-c|-x|-l} [-f RECORD_FILE] [-zp] [-r RECIPIENT] [-FR] [DIR]...
Rename files to [1, N] and save the filenames to file 0.

Mode:
  -c	create record file to storage filenames
  -x	extract filenames in record file and remove it
  -l	watch record file

Options:
  -f	set the record file. will not remove that file. - for stdin/stdout
  -z	enable gzip support, ignored when using gpg to create record file
  -p	enable gpg decryption
  -r	enable gpg encryption and set recipient
  -F	force
    	with -c: works even if the record file exists, just rename it as usual
    	with -x: works even if not all the files exist
  -R	recursive

Links:
  GitHub <https://github.com/chinory/fn0>'
exit
fi
IFS=$'\n'
TMPDIR='/tmp'
exit_1(){ echo "Try 'fn0 --help' for more information.">&2; exit 1; }

MODE=''
RECORD='0'
RECORD_REMOVE=1
GZIP_ENABLE=0
GPG_DECRYPT=0
GPG_ENCRYPT=0
GPG_RECIPIENT=''
NO_FORCE=1
RECURSIVE=0
while getopts ':cxlf:zpr:FR' OPTNAME; do  
case $OPTNAME in
c|x|l)
	[ -n "$MODE" ] && { echo "fn0: Specify too much mode">&2; exit_1; }
	MODE=$OPTNAME
	;;
f)
	RECORD_REMOVE=0
	RECORD=$OPTARG
	;;
z)
	GZIP_ENABLE=1
	;;
p)
	GPG_DECRYPT=1
	;;
r)
	GPG_ENCRYPT=1
	GPG_RECIPIENT=$OPTARG
	;;
F)
	NO_FORCE=0
	;;
R)
	RECURSIVE=1
	;;
:)
	echo "fn0: missing option argument: -$OPTARG">&2; exit_1
	;;	
\?)
	echo "fn0: invalid option: -$OPTARG">&2; exit_1
	;;
esac
done
[ -z "$MODE" ] && { echo "fn0: Must specify one mode">&2; exit_1; }
shift $((OPTIND-1))

case $MODE in c|x) 
undo(){
	local src line
	for line in $(tac -- "$1" 2>/dev/null); do
		if [ -z "$src" ];then
			src=$line
		else
			mv -f -- "$src" "$line"
			src=''
		fi
	done
}
esac

case $MODE in x|l) 
rereadable(){
	if [[ $RECORD == '-' ]]; then
		record=$recp
		record_private=1
		cat >"$record"
	elif [ -e "$RECORD" ]; then
		if [ -p "$RECORD" ]; then
			record=$recp
			record_private=1
			cat -- "$RECORD" >"$record"
		else
			record=$RECORD
			record_private=0
		fi
	else
		return 1
	fi
}
autoconv(){
	record_type=$(file -b --mime-type -- "$record")
	if ((GZIP_ENABLE)) && [[ $record_type == 'application/gzip' || $record_type == 'application/x-gzip' ]]; then
		if ((record_private)); then
			record_packed=$recp_e
			mv -f -- "$record" "$record_packed"
		else
			record_packed=$record
			record=$recp
			record_private=1
		fi
		if ! gzip -dc -- "$record_packed" >"$record"; then
			echo "fn0: cant decompress record: \"$RECORD\" at $PWD">&2
			return 1
		fi
		record_type=$(file -b --mime-type -- "$record")
	elif ((GPG_DECRYPT)) && [[ $record_type != 'text/plain' ]]; then
		if ((record_private)); then
			record_packed=$recp_e
			mv -f -- "$record" "$record_packed"
		else
			record_packed=$record
			record=$recp
			record_private=1
		fi
		if ! gpg -q -o - -d "$record_packed">"$record"; then
			echo "fn0: cant decrypt record: \"$RECORD\" at $PWD">&2
			return 1
		fi
		record_type=$(file -b --mime-type -- "$record")
	fi
	if [[ $record_type != 'text/plain' ]] || [ -n "$(grep -o / -- "$record" | head -c 1)" ] ; then
		echo "fn0: record is invaild: \"$RECORD\" at $PWD">&2
		return 1
	fi
}
esac

case $MODE in
c)
proc(){
	local n=0 line src mid dst
	# safe check: if record file already exists (apply FORCE)
	if ((NO_FORCE)) && [[ $RECORD != '-' ]] && [ -e "$RECORD" ]; then
		echo "fn0: record file already exists: \"$RECORD\" at $PWD">&2
		return 1
	fi
	# first rename: src->dst/mid ($line->$n)
	exec 3>"$succ"; exec 4>"$plus"; exec 5>"$recp"
	for line in $(ls -A); do let n++
		src=$line; dst=$n
		printf '%s\n' "$src" >&5
		if [ -e "$dst" ]; then
			mid=$(mktemp -u -- "$dst.XXXXX")
			printf '%s\n' "$mid" "$dst" >&4
			dst=$mid
		fi
		if mv -- "$src" "$dst"; then
			printf '%s\n' "$src" "$dst" >&3
		else
			echo "fn0: failed to rename: \"$src\" > \"$dst\" at $PWD">&2
			exec 3>&-; undo "$succ"
			return 1
		fi
	done
	# second rename: mid->dst (ignore FORCE)
	exec 4<"$plus";
	src=''; for line in $(cat <&4 2>/dev/null); do
		if [ -z "$src" ]; then
			src=$line
		else
			dst=$line
			if mv -- "$src" "$dst"; then
				printf '%s\n' "$src" "$dst" >&3
			else
				echo "fn0: failed to rename: \"$src\" > \"$dst\" at $PWD">&2
				exec 3>&-; undo "$succ"
				return 1
			fi
			src=''
		fi
	done
	# output RECORD
	exec 5<"$recp"; 
	if ((n)); then
		if ((GPG_ENCRYPT)); then
			if ! gpg -o "$RECORD" -r "$GPG_RECIPIENT" -e <&5; then
				echo "fn0: failed to make record: \"$RECORD\" at $PWD">&2
				exec 3>&-; undo "$succ"
				return 1
			fi
		else
			if [[ $RECORD == '-' ]]; then 
				if ((GZIP_ENABLE)); then gzip -n <&5; else cat <&5; fi
			else
				if ((GZIP_ENABLE)); then gzip -n <&5 >"$RECORD"; else cat <&5 >"$RECORD"; fi
			fi
		fi
	fi
}
;;
x)
proc(){ # var: record record_private record_type record_packed RECORD_backup
	local n=0 line src mid dst
	# input record: insure record rereadable
	rereadable || return
	# record check: auto decrypt/decompress, get vaild text
	autoconv || return 1
	# safe check: if all the files exist
	if ((NO_FORCE)); then
		for line in $(seq $(wc -l <"$record")); do
			if [ ! -e "$line" ]; then
				echo "fn0: file in record not exist: \"$line\" at $PWD">&2
				return 1
			fi
		done
	fi 
	# input record: backup original RECORD, complete record privatization
	if ((RECORD_REMOVE)) && [[ $RECORD != '-' ]]; then
		RECORD_backup=$backupp
		if ! mv -- "$RECORD" "$RECORD_backup"; then
			echo "fn0: failed to remove the record file: \"$RECORD\" at $PWD">&2
			return 1
		fi
		if ((!record_private)); then
			record=$RECORD_backup
			record_private=1
		fi
	else
		RECORD_backup=''
		if ((!record_private)); then
			record=$recp
			record_private=1
			cat -- "$RECORD" >"$record"
		fi
	fi
	# first rename: src->dst/mid ($n->$line)
	exec 3>"$succ"; exec 4>"$plus";
	for line in $(cat -- "$record"); do let n++
		src=$n; dst=$line
		if [ -e "$dst" ]; then
			mid=$(mktemp -u -- "$dst.XXXXX")
			printf '%s\n' "$mid" "$dst" >&4
			dst=$mid
		fi
		if mv -- "$src" "$dst"; then
			printf '%s\n' "$src" "$dst" >&3
		else
			echo "fn0: failed to rename: \"$src\" > \"$dst\" at $PWD">&2
			if ((NO_FORCE)) || [ -e "$src" ]; then
				exec 3>&-; undo "$succ"
				[ -n "$RECORD_backup" ] && mv -f -- "$RECORD_backup" "$RECORD"
				return 1
			fi
		fi
	done
	# second rename: mid->dst (apply FORCE: may cause losing filename)
	exec 4<"$plus";
	src=''; for line in $(cat <&4 2>/dev/null); do
		if [ -z "$src" ]; then
			src=$line
		else
			dst=$line
			if mv -- "$src" "$dst"; then
				printf '%s\n' "$src" "$dst" >&3
			else
				echo "fn0: failed to rename: \"$src\" > \"$dst\" at $PWD">&2
				if ((NO_FORCE)) || [ -e "$src" ]; then
					exec 3>&-; undo "$succ"
					[ -n "$RECORD_backup" ] && mv -f -- "$RECORD_backup" "$RECORD"
				return 1
			fi
			fi
			src=''
		fi
	done
}
;;
l)
proc(){ # var: record record_private record_type record_packed
	# input record: insure record rereadable
	rereadable || return
	# record check: auto decrypt/decompress, get vaild text
	autoconv || return 1
	# print record
	cat -- "$record"
}
;;
esac

case $MODE in
c|x)
	if ((RECURSIVE)); then
		main(){
			proc
			for fn in $(ls -A); do
				[ -d "$fn" ] && \
				cd -- "$fn" && \
				{ main; cd .. || break; }
			done
		}
	else
		main(){
			proc
		}
	fi
	;;
l)
	if ((RECURSIVE)); then
		recurse(){
			printf '%s\n' "$1/"
			proc
			echo
			for fn in $(ls -A); do
				[ -d "$fn" ] && \
				cd -- "$fn" && \
				{ recurse "$1/$fn"; cd .. || break; }
			done
		}
		main(){
			recurse "$DIR"
		}
	elif [ $# -gt 1 ]; then
		main(){
			printf '%s\n' "$DIR/"
			proc
			echo
		}
	else
		main(){
			proc
		}
	fi
	;;
esac

succ="$TMPDIR/fn0.$$.succ" 
plus="$TMPDIR/fn0.$$.plus"
recp="$TMPDIR/fn0.$$.recp"
recp_e="$TMPDIR/fn0.$$.recp.enc"
backupp="$TMPDIR/fn0.$$.backup"

trap '[ -n "$RECORD_backup" ] && echo; echo "mv -- \"$RECORD_backup\" \"$PWD/$RECORD\"">&2; exit 1' 1 2 3 15

case $# in
0)
	DIR='.'
	main
	;;
1)
	DIR=$(dirname -- "$1/..")
	cd -- "$DIR" && main
	;;
*)
	OWD=$PWD
	for DIR in "$@"; do
		DIR=$(dirname -- "$DIR/..")
		cd -- "$DIR" && { main; cd -- "$OWD" || break; }
	done
	;;
esac

rm -f -- "$succ" "$plus" "$recp" "$recp_e" "$backupp"
