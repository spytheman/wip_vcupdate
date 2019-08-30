module main

import (
	os
	time
	net.urllib
	log
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
	too_short_file_limit = 5000
	// vcupdate working directory
	vcupdate_dir = '/home/user/dev/vcupdate'
	// create a .c file for these os's
	vc_build_oses = [
		'unix',
		'windows'
	]
)

fn main() {
	log := log.Log{log.DEBUG, 'terminal'}
	
	// check if vcupdate dir exists
	if !os.dir_exists(vcupdate_dir) {
		os.mkdir(vcupdate_dir)
		// try create
		if !os.dir_exists(vcupdate_dir) {
			log.error('error creating directory: $vcupdate_dir')
			exit(1)
		}
	}
	// cd to vcupdate dir
	os.chdir(vcupdate_dir)
	// once we use webhook we can get rid of this
	// instead of deleting and re-downloading the repo each time
	// it first checks to see if the existing one is behind master
	// if it isn't behind theres no point continuing further
	if os.dir_exists(github_repo_v) {
		cmd_exec(log, 'git -C $github_repo_v checkout master')
		// fetch the remote repo just in case there are newer commits there:
		cmd_exec(log, 'git -C $github_repo_v fetch')
		git_status := cmd_exec(log, 'git -C $github_repo_v status')
		if !git_status.contains('behind') {
			log.warn('v repository is already up to date.')
			exit(0)
		}
	}

	// delete old repos (better to be fully explicit here, since these are destructive operations):
	cmd_exec(log, 'rm -rf $vcupdate_dir/$github_repo_v/')
	cmd_exec(log, 'rm -rf $vcupdate_dir/$github_repo_vc/')
	
	// clone repos
	cmd_exec(log, 'git clone --depth 1 https://github.com/$github_repo_user/$github_repo_v')
	cmd_exec(log, 'git clone --depth 1 https://github.com/$github_repo_user/$github_repo_vc')
	
	// get output of git log -1 (last commit)
	git_log_v := cmd_exec(log, 'git -C $github_repo_v log -1 --date=iso')
	git_log_vc := cmd_exec(log, 'git -C $github_repo_vc log -1 --date=iso')

	// date of last commit in each repo
	ts_v := git_log_v.find_between('Date:', '\n').trim_space()
	ts_vc := git_log_vc.find_between('Date:', '\n').trim_space()
	
	// parse dates
	last_commit_time_v  := time.parse(ts_v)
	last_commit_time_vc := time.parse(ts_vc)

	// last commit in id in v repo
	last_commit_id_v := git_log_v.find_between('commit', '\n').trim_space()
	last_commit_id_v_shortened := last_commit_id_v.left(6)

	log.debug('## ts_v: $ts_v')
	log.debug('## ts_vc: $ts_vc')
	log.debug('## last_commit_time_v: ' + last_commit_time_v.format_ss())
	log.debug('## last_commit_time_vc: ' + last_commit_time_vc.format_ss())
	log.debug('## last_commit_id_v: $last_commit_id_v')
	log.debug('## last_commit_id_v_shortened: $last_commit_id_v_shortened')
	
	// if vc repo already has newer commit v repo it's already up to date
	if last_commit_time_vc.uni >= last_commit_time_v.uni {
		log.warn('vc repository is already up to date.')
		exit(0)
	}

	// try run make to build v for unix	
	cmd_exec(log, 'make -C $github_repo_v')
	vexec := '$github_repo_v/v'
	// check if make was successful
	assert_file_exists_and_is_not_too_short( log, vexec, err_msg_make )
	
	// try build v for current os (linux in this case)
	cmd_exec('make -C $github_repo_v')
	// check if make was successful
	if !os.file_exists('$github_repo_v/v') {
		println('$err_msg_build: ${err_msg_make}.')
		exit(1)
	}
	
	// build v.c for each os
	for os_name in vc_build_oses {
		// try generate v.c
		vc_suffix := if os_name == 'unix' { '' } else { '_${os_name.left(3)}' }
		v_os_arg := if os_name == 'unix' { '' } else { '-os $os_name' }
		c_file := 'v${vc_suffix}.c'
		cmd_exec(log, '$vexec $v_os_arg -o $c_file $github_repo_v/compiler')
		// check if the c file seems ok
		assert_file_exists_and_is_not_too_short(log, c_file, err_msg_gen_c)
		
		// embed the latest v commit hash into the c file
		cmd_exec(log, 'sed -i \'s/#define V_VERSION "000000"/#define V_VERSION "$last_commit_id_v_shortened"/gm\' $c_file')
		
		// run clang-format to make the c file more readable
		cmd_exec(log, 'clang-format -i $c_file')
		
		// move to vc repo
		cmd_exec(log, 'mv $c_file $github_repo_vc/$c_file')
	}

	// add new .c files to local vc repo
	cmd_exec(log, 'git -C $github_repo_vc add *.c')
	
	// check if the vc repo actually changed
	git_status := cmd_exec(log, 'git -C $github_repo_vc status') 
	if git_status.contains('nothing to commit') {
		log.error('no changes to vc repo: something went wrong.')
		exit(1)
	}
	// commit to changes local vc repo
	cmd_exec(log, 'git -C $github_repo_vc commit -m "update from master - $last_commit_id_v"')
	// push changes to remote vc repo
	cmd_exec(log, 'git -C $github_repo_vc push https://${urllib.query_escape(git_username)}:${urllib.query_escape(git_password)}@github.com/$github_repo_user/$github_repo_vc master')
}

fn cmd_exec(log log.Log, cmd string) string {
	log.info('cmd: $cmd')
	r := os.exec(cmd) or {
		log.error('$err_msg_cmd_x: "$cmd" could not start.')
		log.error( err )
		exit(1)
	}
	if r.exit_code != 0 {
		log.error('$err_msg_cmd_x: "$cmd" failed.')
		log.error(r.output)
		exit(1)
	}
	return r.output
}

fn dry_cmd_exec(log log.Log, cmd string) string {
	log.info('### dry exec: "$cmd"')
	return ''
}

fn assert_file_exists_and_is_not_too_short(log log.Log, f string, emsg string){
	if !os.file_exists(f) {
		log.error('$err_msg_build: $emsg .')
		exit(1)
	}
	fsize := os.file_size(f)
	if fsize < too_short_file_limit {
		log.error('$err_msg_build: $f exists, but is too short: only $fsize bytes.')
		exit(1)
	}
}

