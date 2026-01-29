#!/bin/env bash
#
# test pull
# retest commit
#

PATH="./:$PATH"


if ! source bashlib_y;then
	echo -e "\033[41m\033[33mERROR    :\033[m \033[31m""bashlib_y not found.\033[m"
	exit 1
fi




function new_remote(){
	if ! type gh >/dev/null 2>&1;then
		yellow "'gsh' not found. "
		if ask_yes_no "Install it?";then
			if ! grep '\[gh-cli\]' -r /etc/yum.repos.d >/dev/null;then
				sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
			fi
			pkg_install gh
			if ! type gh >/dev/null 2>&1;then
				die "Installation failed."
			fi
		else
			die "Exiting."
		fi
	fi
	local rn=$(basename "$PWD")
	echo "Creating repository, '$rn' ..."	
	if ! gh auth status;then
		echo 100
		if ! gh auth login;then
			die "Cannot login."
		fi
	fi
	if ! gh repo create $rn --public; then
		die "Cannot create remote repository, '$rn'."
	else
		echo "Remote repository, '$rn' created."
	fi
}





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
				if true; then
					g --no-push
				else
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
							git pull origin $DRB > $SCRIPT_TMP_DIR/res2 2>&1 
							cat $SCRIPT_TMP_DIR/res2
							while read ln2; do
								if [[ "\$ln2" =~ Pulling\ without\ specifying\ how\ to\ reconcile\ divergent\ branches ]]; then
									green config pull.rebase false ...
									git config pull.rebase false
								fi
								if [[ "\$ln2" =~ There\ is\ no\ tracking\ information\ for\ the\ current\ branch ]];then
									if [ -n "$DRB" ];then
										green git branch --set-upstream-to=origin/$DRB main
										git branch --set-upstream-to=origin/$DRB main
									else
										die "Cannot detect default remote branch name."
									fi
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

function ggit(){
	green $@ ...
	git "$@"
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
				ggit config pull.rebase true
				retry=1
			fi
			if [[ "$ln2" =~ There\ is\ no\ tracking\ information\ for\ the\ current\ branch ]] ||
			   [[ "$ln2" =~ You\ asked\ to\ pull\ from\ the\ remote\ \'origin\'\,\ but\ did\ not\ specify ]]
			then
				do_git branch --set-upstream-to=origin/main main
				retry=1
			fi
			if [[ "$ln2" =~ fatal:\ no\ commit\ on\ branch\ \'main\'\ yet ]];then
				dbv
				ggit add '*'
				ggit commit -a -m "commit from $USER@`hostname -s`"
				ggit push --set-upstream origin main
				retry=1
			fi
			if [[ "$ln2" =~ fatal:\ the\ requested\ upstream\ branch\ \'origin\/main\'\ does\ not\ exist ]];then
				dbv
				ggit push --set-upstream origin main
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
		
		if [ -n "$DRB" ];then
			drb="origin HEAD:$DRB"
		else
			drb=
		fi

		if ! do_git push $drb ; then
			exit 1
		fi

#		local cid="`git log origin/main -1 | head -1 | awk '{print $2}'`"
#		if [ -z "$cid" ];then
#			exit 1
#		fi

		
#		mv -f version version.prev
#		do_git checkout $cid version

	else
		echo "Only ssh clone."
	fi
	ssh_clone
}

require args


function create_repo(){
	if ask_yes_no "Create repository?";then
		new_remote
	else
		die "Exiting."
	fi
}

function git_ls_reomote(){
	dbv
	if ! git ls-remote 2>/tmp/_g_.err > /tmp/_g_.res; then
		dbv
		if grep 'ERROR: Repository not found' /tmp/_g_.err; then
			yellow "Remote repository not found." >&2
			create_repo
			if ! git ls-remote 2>/tmp/_g_.err > /tmp/_g_.res; then
				die "Cannot find repository."
			fi
			lns="`cat /tmp/_g_.res`"
		else
			cat /tmp/_g_.err
			die "Cannot connect to remote repository."
		fi
	fi
}

function get_default_remote_branch(){
	local lns
	dbv
	git_ls_reomote 
	dbv
	local hid=`echo "$lns"|grep HEAD|awk '{print $1}'`
	if [ -z "$hid" ];then
		return
	fi
	local rmn=`echo "$lns"|grep $hid|awk '{print $2}'`
	local rmn="${rmn##*/}"
	local lmn="`git branch|grep -E '^\* '|awk '{print $2}'`"
	if [ "$rmn" != "$lmn" ];then
		DRB="$rmn"
	else
		DRB=""
	fi
}


function main(){
	rm -f ~/.g.cd
	. args
	local i
	local acnt=0
	local target
	local user
	for i in "$@";do
		if [ "${i:0:1}" = "-" ];then
			continue
		fi
		acnt=$((acnt + 1))
		if [ "$acnt" = 1 ];then
			target="$i"
		fi
	done
	if [ "$acnt" = 1 ];then
		if [ "${target%/*}" != "$target" ];then
			user="${target%%/*}"
			target="${target#*/}"
			if [ "${target%/*}" != "$target" ];then
				die "Repository name '$target' contains '/'."
			fi
		fi
		if [ -d "~/git_project/$target" ];then
			local user_exist="`cd ~/git_project/$target; git config user.name`"
			if [ -n "$user" ];then
				if [ -n "$user_exist" ];then
					if [ "$user" != "$user_exist" ];then
						die "Git project by another user, '$user_exist' already exists."
					else
						echo "Git project, '$target' found. Changing direcotry to '~/git_project/$target'."
						echo "$HOME/git_project/$target" > ~/.g.cd
						exit 0
					fi
				fi
			fi
		fi
		if [ -e "~/git_project/$target/.git" ];then
			echo "Git project, '$target' found. Changing direcotry to '~/git_project/$target'."
			echo "$HOME/git_project/$target" > ~/.g.cd
			exit 0
		fi
		if [ ! -z "$(ls -A "~/git_project/$target" 2>/dev/null)" ]; then
			die "Directory, '~/git_project/$target' is not empty."
		fi
		local user_list=()
		if [ -z "$user" ];then
			for i in ~/git_project/*; do
				local j="`cd $i; git config user.name`"
				if [ -z "$j" ];then
					continue
				fi
				local k
				local found=""
				for k in ${user_list[@]};do
					if [ "$k" = "$j" ];then
						found=1
						break
					fi
				done
				if [ -z "$found" ];then
					user_list+=("$j (used in $i)")
				fi
			done
			if [ ${#user_list[@]} -gt 1 ];then
				yellow "Multiple users found in '~/git_project'. Please select user name."
				j=1
				for i in "${user_list[@]}";do
					echo -e "  $j. $cyan$i$white"
					j=$((j + 1))
				done
				echo -e "  0. New user"
				echo -n "Select user number: "
				read j
				if [ "$j" = 0 ];then
					echo -n "Enter user name: "
					read user
				else
					user="${user_list[$((j - 1))]}"
					user="${user%% (*}"
				fi
			elif [ ${#user_list[@]} -eq 1 ];then
				user="${user_list[0]}"
				user="${user%% (*}"
				local d="${user_list[0]##* (used in }"
				d="${d%%)}"
				if ! ask_yes_no "User, '$user' found in '$d'. Use it?";then
					echo -n "Enter user name: "
					read user
				fi
			else
				echo -n "Enter user name: "
				read user
			fi
		fi
		if [ -z "$user" ]; then
			die "User name not specified."
		fi
		if ! [[ "$user" =~ ^[a-zA-Z0-9_]+$ ]]; then
			die "Invalid user name, '$user'."
		fi
		if git-force-clone "https://github.com/$user/$target.git" "$HOME/git_project/$target"; then
			echo "$HOME/git_project/$target" > ~/.g.cd
			exit 0
		else
			die "Cannot clone github repository, '$user/$target'."
		fi
	elif [ "$acnt" != 0 ];then
		die "Too many arguments."
		exit 1
	fi
	if [ ! -e .git ];then
		if ! ginit; then
			exit 1
		fi
	fi
	if opt -3; then
		exec g3 "$@"
	elif opt -2; then
		exec g2 "$@"
	elif opt -1; then
		exec g1 "$@"
	elif opt -0; then
		exec g0 "$@"
	elif opt --no-push; then
		NO_PUSH=1
	elif ! opt --locked; then
		flock -E 255 -x ./ $0 --locked $@
		local ret=$?
		if [ $ret = 255 ];then
			die "Other g command is still running on this directory."
		fi
		exit $ret
	fi

	G_USER=`git config user.name`
	G_EMAIL=`git config user.email`
	ask_yes_no_color yellow magenta
	local g
	if [ -z "$G_USER" -o -z "$G_EMAIL" ];then
		yellow "Missing user and/or email for git."
		local g_user
		local g_email
		for g in ~/git_project/*; do
			if [ -e $g/.git/config ];then
				if [ -z "$G_USER" ];then
					g_user=$( (cd $g; git config user.name) )
					if [ -n "$g_user" ];then
						dbv $g_user
						if [ -z "$G_EMAIL" ];then
							g_email=$( (cd $g; git config user.email) )
							if [ -n "$g_email" ] ;then
								echo -e "Found '$cyan$g_user$white' and '$cyan$g_email$white' in '$cyan$g/config'$white."
								if ask_yes_no "Use them?"; then
									G_USER=$g_user
									G_EMAIL=$g_email
									git config user.name $g_user
									git config user.email $g_email
									break
								fi
							fi
						else
							echo -e "Found '$cyan$g_user$white' in '$cyan$g/config'$white."
							if ask_yes_no "Use '$g_user' ?"; then
								G_USER=$g_user
								git config user.name $g_user
								break
							fi
						fi
					fi
				elif [ -z "$G_EMAIL" ];then
					g_email=$( (cd $g/..; git config user.email) )
					if [ -n "$g_email" ] ;then
						echo -e "Found '$cyan$g_email$white' in '$cyan$g/config'$white."
						if ask_yes_no "Use $g_email ?"; then
							G_EMAIL=$g_email
							git config user.email $g_email
							break
						fi
					fi
				fi
			fi
		done
		if [ -z "$G_USER" -o -z "$G_EMAIL" ];then
			die "Missing user and/or email for git. Please set user by executing 'git config user.name USER_NAME\ngit user.email EMAIL'"
		fi
	fi

	if [[ `git remote -v` =~ https ]]; then
		git remote set-url origin git@github.com:${G_USER}/`basename $(git rev-parse --show-toplevel)`.git
		if ! [[ `ssh git@github.com 2>&1` =~ successfully ]]; then
			die "Cannot connect to github by ssh. Please set up ssh keys."
		fi
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
	if [ -z "$DRB" ];then
		dbv
		get_default_remote_branch
	fi
	dbv
	CM="`do_git commit -a --dry-run`"
	dbv $CM
	if ! [[ $CM =~ Changes\ to\ be\ committed: ]]; then
		
		if ! do_git pull origin $DRB; then
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
	
	
	if [ "`git log -1 | head -1 | awk '{print $2}'`" != "`git ls-remote | grep HEAD | awk '{print $1}'`" ]; then
	
		do_git commit -a -m "`v`.9999 before pull from $USER@`hostname -s`"
		if ! do_git pull origin $DRB; then
			#do_git rebase --abort
			#do_git reset --merge
			#mv -f version version.failed
			#do_git reset --soft
			#mv -f version.prev version
			exit 1
		fi

	fi
	
	if [ -n "$NO_PUSH" ];then
		exit 0
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

