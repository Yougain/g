#!/bin/env bash

# test pull
# retest commit


PATH="./:$PATH"

if ! source bashlib_y;then
	echo -e "\033[41m\033[33mERROR    :\033[m \033[31m""bashlib_y not found.\033[m"
	exit 1
fi

function ssh_clone(){
 	if [ -e .git/.ssh_clone ]; then
		require ssh_do
		local url=`git config --get remote.origin.url`
		url=https://github.com/${url#*:}
		url=${url%%.git}
		local tdirb=`pwd`
		tdir="~/git_project/${tdirb##*/}"
		tdirb="~/${tdirb##*/}"
		local ret=0
		while read ln; do
			cyan ssh cloning to $ln
			deb $DEBUG
			deb $ln
			ssh_param $ln -x -q
			ssh_do <<-}
				if [ -d $tdirb/.git ];then
					td=$tdirb
				elif [ -d $tdir/.git ];then
					td=$tdir
				fi
				if [ -n "\$td" ];then
					pushd \$td > /dev/null
					green commit ...
					retry=
					while true; do
						git commit -a -m "commit from $USER@`hostname -s`" > $SCRIPT_TMP_DIR/res1 2>&1
						cat $SCRIPT_TMP_DIR/res1
						while read ln2; do
							if [[ "\$ln2" =~ Author\ identity\ unknown ]]; then
								green config user.name $G_USER ...
								git config --local user.name $G_USER
								green config user.name $G_EMAIL ...
								git config --local user.email $G_EMAIL
								git commit -a -m "commit from $USER@`hostname -s`"
								retry=1
							fi
						done < $SCRIPT_TMP_DIR/res1
						if [ -z "\$retry" ];then
							break
						fi
						retry=
					done
					unset ln
					stdbuf -oL echo
					green pull ...
					retry=
					while true; do
						git pull > $SCRIPT_TMP_DIR/res2 2>&1 
						cat $SCRIPT_TMP_DIR/res2
						while read ln2; do
							if [[ "\$ln2" =~ Pulling\ without\ specifying\ how\ to\ reconcile\ divergent\ branches ]]; then
								green config pull.rebase false ...
								git config pull.rebase false
								retry=1
							fi
							if [[ "\$ln2" =~ There\ is\ no\ tracking\ information\ for\ the\ current\ branch ]];then
								green git branch --set-upstream-to=origin/main main
								git branch --set-upstream-to=origin/main main
								retry=1
							fi
						done < $SCRIPT_TMP_DIR/res2
						if [ -z "\$retry" ];then
							break
						fi
						retry=
					done
					popd > /dev/null
				else
					green_n force-clone ...
					git-force-clone $url $tdir
					pushd $tdir > /dev/null
					green_n config user.name $G_USER ...
					git config --local user.name $G_USER
					green config user.name $G_EMAIL ...
					git config --local user.email $G_EMAIL
					git branch -u origin
					git remote set-url origin git@github.com:$G_USER/${url##*/}
					popd > /dev/null
				fi
			}
			if [ "$?" = 255 ];then
				err "Cannot connect: ssh $ln git-force-clone $url $tdir"
				ret=1
			fi
		done < .git/.ssh_clone
	fi
	return $ret
}

function v(){
	if [ -n "$1" ];then
		local grade="$1"
		local num=${vers[$grade]}
		if [ -z "$num" ];then
			echo -n 0
		else
			echo -n $num
		fi
	else
		local v
		local fst=1
		for v in "${vers[@]}";do
			if [ -n "$fst" ];then
				fst=
			else
				echo -n "."
			fi
			echo -n $v
		done
	fi
}


function do_git(){
	local retry
	local stat
	local ln2
	while true; do
		dbv "$@"
		green git "$@" ...
		git "$@" > $SCRIPT_TMP_DIR/res1 2>&1
		stat=$?
		cat $SCRIPT_TMP_DIR/res1
		dbv
		while read ln2; do
			dbv $ln2
			if [[ "$ln2" =~ Author\ identity\ unknown ]]; then
				green git config user.name $G_USER ...
				git config --local user.name $G_USER
				green git config user.name $G_EMAIL ...
				git config --local user.email $G_EMAIL
				git commit -a -m "commit from $USER@`hostname -s`"
				retry=1
			fi
			if [[ "$ln2" =~ Pulling\ without\ specifying\ how\ to\ reconcile\ divergent\ branches ]]; then
				green git config pull.rebase true ...
				git config pull.rebase true
				retry=1
			fi
			if [[ "$ln2" =~ There\ is\ no\ tracking\ information\ for\ the\ current\ branch ]];then
				green git branch --set-upstream-to=origin/main main
				git branch --set-upstream-to=origin/main main
				retry=1
			fi
		done < $SCRIPT_TMP_DIR/res1
		dbv $retry
		if [ -z "$retry" ];then
			break
		fi
		retry=
	done
	return $stat
}


function commit(){
	dbv $#
	dbv $@
	dbv $*
	if [ -z "$no_ver_mod" ];then

		echo -E "`v` `date` $*
`cat version`
" > version.new
		mv -f version version.bak
		mv version.new version
		if [ $# -gt 0 ];then
			echo -E "`date` `v` $*
`cat change_log`" > change_log.new
			mv -f change_log.new change_log
			local log_exist=$(echo "`git ls-files`" | grep -E "^change_log$")
			if [ -z "$log_exist" ];then
				do_git add change_log
			fi
		fi
		local version_exist=$(echo "`git ls-files`" | grep -E "^version$")
		if [ -z "$version_exist" ];then
			do_git add version
		fi

		do_git commit -a -m "`v` $* $USER@`hostname -s`"

		if ! do_git push; then
			exit 1
		fi

		local cid="`git log origin/main -1 | head -1 | awk '{print $2}'`"
		if [ -z "$cid" ];then
			exit 1
		fi

		
#		mv -f version version.prev
#		do_git checkout $cid version

	else
		echo "Only ssh clone."
	fi
	ssh_clone
}

require args


function main(){
	. args
	if opt -3; then
		exec g3 "$@"
	elif opt -2; then
		exec g2 "$@"
	elif opt -1; then
		exec g1 "$@"
	elif opt -0; then
		exec g0 "$@"
	elif ! opt --locked; then
		flock -E 255 -x ./ $0 --locked $@
		local ret=$?
		if [ $ret = 255 ];then
			die "Other g command is still running on this directory."
		fi
		exit $ret
	fi

	G_USER=`git config user.name`
	if [ -z "$G_USER" ];then
		die "Missing user for git. Please set user by executing 'git config user.name USER_NAME\ngit user.email EMAIL'"
	fi


	G_EMAIL=`git config user.email`
	if [ -z "$G_EMAIL" ];then
		die "Missing user email for git. Please set user by executing 'git config user.name USER_NAME\ngit user.email EMAIL'"
	fi

	dbv ${all_args[@]}
	if opt -f; then
		force=1
	else
		Emsg=" Exiting."
	fi
	if opt -F; then
		force_pre_post=1
		Emsg=" Exiting."
	fi

	if [ -e .git/.g-pre-commit ];then
		.git/.g-pre-commit
	fi
	
	dbv
	CM="`do_git commit -a --dry-run`"
	dbv $CM
	if ! [[ $CM =~ Changes\ to\ be\ committed: ]]; then
		if ! do_git pull --no-edit; then
			warn "Pull failed.$Emsg"
			exit 1
		fi
		warn "Not modified.$Emsg"
		if [ -n "$force_pre_post" ];then
			no_ver_mod=1
		elif [ -z "$force" ];then
			exit 1
		fi
	fi
	
	if [ ! -e ./version ];then
		warn "version not found. create version = 0"
		echo 0 > version
		git add version
	fi
	
	ver=`cat version|head -1|awk '{print $1}'`
	if [[ "`cat version|head -1|awk '{print $1}'`" =~ ^[0-9]+(\.[0-9]+)*$ ]];then
		vers=(`echo $ver |tr '.' ' '`)
	else
		die "The first word of file, 'version' cannot interpreted as version number ('$ver').
	Note that you cannot use non-numeric characters in it."
	fi


	if ! do_git fetch; then
		exit 1
	fi
	
	if [ "`git log -1 | head -1 | awk '{print $2}'`" != "`git log -1 origin/main | head -1 | awk '{print $2}'`" ]; then
	
		do_git commit -a -m "`v`.9999 before pull from $USER@`hostname -s`"
		if ! do_git pull origin main; then
			#do_git rebase --abort
			#do_git reset --merge
			#mv -f version version.failed
			#do_git reset --soft
			#mv -f version.prev version
			exit 1
		fi

	fi
	
	vers=($(cat version | head -1 |awk '{print $1}' | tr '.' ' '))

	cmd="$(__CMD_NAME__)"

	if [ "$cmd" = "g" ];then
		if [ -e .git/.g ];then
			cmd=`cat .git/.g`
		else
			cmd=g2
		fi
	fi

	case "$cmd" in
		"g0")
			whiteBgRed_n "You really need major version up ? "
			yellowBgRed_n  "[y/n]:"
			echo -n " "
			if ! ask_yes_no; then
				info "Terminated by user."
				exit 1
			fi
			vers=($((`v 0` + 1)) 0)
			echo -n g2 > .git/.g
			;;
		"g1")
			vers=($((`v 0`)) $((`v 1` + 1)))
			echo -n g2 > .git/.g
			;;
		"g2")
			vers=($((`v 0`)) $((`v 1`)) $((`v 2` + 1)))
			echo -n g2 > .git/.g
			;;
		"g3")
			vers=($((`v 0`)) $((`v 1`)) $((`v 2`)) $((`v 3` + 1)))
			echo -n g3 > .git/.g
			;;
		*)
			die "command name '$(__CMD_NAME__)', unsupported."
			;;
	esac

	commit ${all_args[@]}

}


main "$@"

