module main

import (
	os
	time
	net.urllib
)

// git credentials
const(
	git_username = ''
	git_password = ''
)
// github repo
const(
	github_repo_v  = 'v'
	github_repo_vc = 'vc'
	github_repo_user = 'vlang'
)
// errors
const(
	err_msg_build = 'error building'
	err_msg_make  = 'make failed'
	err_msg_gen_c = 'failed to generate .c file'
	err_msg_cmd_x = 'error running cmd'
)

const(
	// vcupdate working directory
	vcupdate_dir = '/home/user/dev/vcupdate'
	// create a .c file for these os's
	vc_build_oses = [
		'unix',
		'windows'
	]
)

fn main() {
	// check if vcupdate dir exists
	if !os.dir_exists(vcupdate_dir) {
		os.mkdir(vcupdate_dir)
		// try create
		if !os.dir_exists(vcupdate_dir) {
			println('error creating directory: $vcupdate_dir')
			exit(1)
		}
	}
	// cd to vcupdate dir
	os.chdir(vcupdate_dir)
	// once we use webhook we can get rid of this
	// instead of deleting and re-downloading the repo each time
	// it first checks to see it the existing one is behind master
	// if it isn't behind theres no point continuing
	if os.dir_exists(github_repo_v) {
		git_status := cmd_exec('git -C $github_repo_v status')
		if !git_status.contains('behind') {
			println('vc already up to date.')
			exit(0)
		}
	}

	// delete old repos
	cmd_exec('rm -rf $github_repo_v')
	cmd_exec('rm -rf $github_repo_vc')
	
	// clone repos
	cmd_exec('git clone --depth 1 https://github.com/$github_repo_user/$github_repo_v')
	cmd_exec('git clone --depth 1 https://github.com/$github_repo_user/$github_repo_vc')
	
	// get output of git log -1 (last commit)
	git_log_v := cmd_exec('git -C $github_repo_v log -1 --date=iso')
	git_log_vc := cmd_exec('git -C $github_repo_vc log -1 --date=iso')

	// date of last commit in each repo
	ts_v := git_log_v.find_between('Date:', '\n').trim_space()
	ts_vc := git_log_vc.find_between('Date:', '\n').trim_space()
	
	// parse dates
	last_commit_time_v  := time.parse(ts_v)
	last_commit_time_vc := time.parse(ts_vc)

	// last commit in id in v repo
	last_commit_id_v := git_log_v.find_between('commit', '\n').trim_space()

	// if vc repo already has newer commit v repo it's already up to date
	if last_commit_time_vc.uni >= last_commit_time_v.uni {
		println('vc already up to date.')
		exit(0)
	}
	
	// build v.c for each os
	for os_name in vc_build_oses {
		// try build v for unix
		if os_name == 'unix' {
			// try run make
			cmd_exec('make -C $github_repo_v')
			// check if make was successful
			if !os.file_exists('$github_repo_v/v') {
				println('$err_msg_build: ${err_msg_make}.')
				exit(1)
			}
		}
		// try generate v.c
		vc_suffix := if os_name == 'unix' { '' } else { '_${os_name.left(3)}' }
		v_os_arg := if os_name == 'unix' { '' } else { '-os $os_name' }
		c_file := 'v${vc_suffix}.c'
		cmd_exec('$github_repo_v/v $v_os_arg -o $c_file $github_repo_v/compiler')
		// check if v.c was generated
		if !os.file_exists(c_file) {
			println('$err_msg_build: ${err_msg_gen_c}.')
			exit(1)
		}
		// run clang-format
		cmd_exec('clang-format -i ')
		// move to vc repo
		cmd_exec('mv $c_file $github_repo_vc/$c_file')
	}

	// add new .c files to local vc repo
	cmd_exec('git -C $github_repo_vc add *.c')
	// check if the vc repo actually changed
	git_status := cmd_exec('git -C $github_repo_vc status') 
	if git_status.contains('nothing to commit') {
		println('no changes to vc repo: something went wrong.')
		exit(1)
	}
	// commit to changes local vc repo
	cmd_exec('git -C $github_repo_vc commit -m "update from master - $last_commit_id_v"')
	// push vc changes to remote
	cmd_exec('git -C $github_repo_vc push https://${urllib.query_escape(git_username)}:${urllib.query_escape(git_password)}@github.com/$github_repo_user/$github_repo_vc master')
	println('vc repo successfully updated.')
}

fn cmd_exec(cmd string) string {
	r := os.exec(cmd) or {
		println('$err_msg_cmd_x: $cmd')
		exit(1)
	}
	if r.exit_code != 0 {
		println('$err_msg_cmd_x: $cmd')
		exit(1)
	}
	return r.output
}
