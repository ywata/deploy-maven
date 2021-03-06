#!/usr/bin/env perl

use strict;
use strict "vars";
use strict "refs";
use strict "subs";
use warnings;

my @BINS = ("/bin", "/usr/bin");
my $TAR = "tar";
my $SVN = "svn";
my $RM  = "/bin/rm";
my $CURL = "curl";
my $INSTALL = "install";

my $BINDIR = "$ENV{HOME}/bin_";
my $JAVA_HOME = "java_home";
my $MAVEN_VER = "3.3.3";
my $BUILD_VERSION_FILE = ".build_version";
my $BUILD_CONFIG       = ".build_config";
my $CHROOT = "chroot";
my $CHROOTX = "$CHROOT" . "x";

my $root = "root.root";
my $tomcat = "root.root";

my @install_params;
my @replace_file;   # fileName -> ref of s/// commands array.

my $install_dir;
my $install_top;
my $tomcat_dir;

#my $prod = "prod";
my $prod;

$TAR = &findFile($TAR, @BINS);
$SVN = &findFile($SVN, @BINS);
$CURL = &findFile($CURL, @BINS);
$INSTALL = &findFile($INSTALL, @BINS);

chomp(my $build_started = `date "+%Y%m%d-%H%M"`);#chomp($build_started);
chomp(my $cwd = `pwd`); # /bin/pwd

# main function is command dispatcher
&dispatch_(@ARGV);

sub dispatch_{
    my(@argv) = @ARGV;
    my($command) = shift @argv; # 
    my($r);
    
#    print "ARGV:@ARGV \n";
    #    print "argv:@argv \n";
    if(!defined($ARGV[0])){
	$ARGV[0] = ""; # to suppress warnings.
    }

    if($ARGV[0] eq "setup"){
	&do_setup_(@argv);
    }elsif($ARGV[0] eq "fetch"){
	&do_fetch_(	   
	     "http://download.oracle.com/otn-pub/java/jdk/8u60-b27/jdk-8u60-linux-x64.tar.gz",
	     "http://ftp.tsukuba.wide.ad.jp/software/apache/maven/maven-3/3.3.3/binaries/pache-maven-3.3.3-bin.tar.gz");
    }elsif($ARGV[0] eq "prepare"){
	&do_prepare_(@argv);
    }elsif(($ARGV[0] eq "tag")){
	&do_tag_(@argv);
    }elsif(($ARGV[0] eq "checkout")){
	&writeVersion_($BUILD_VERSION_FILE, "", "");
	&do_checkout_("checkout", @argv);
    }elsif(($ARGV[0] eq "tag-checkout")){
	# tag URL
	
	if($ARGV[2] =~ m|tags/$ARGV[1]/|){ # We assume standard SVN layout.
	    
	}else{
	    die "tag name and URL does not match. $ARGV[1] $ARGV[2]"
	}
	
	&writeVersion_($BUILD_VERSION_FILE, "tag", $argv[0]);
	my($opt) = " checkout ";
	shift @argv;
	&do_checkout_($opt, @argv);
    }elsif(($ARGV[0] eq "rev-checkout")){
	&writeVersion_($BUILD_VERSION_FILE, "rev", $argv[0]);
	my($opt) = "checkout  -r " . shift @argv;
	&do_checkout_($opt, @argv);
    }elsif(($ARGV[0] eq "build")){
	&set_build_config();	
	my($t, $v) = &readVersion_($BUILD_VERSION_FILE);
	&do_build_($t, $v, @argv);
    }elsif(($ARGV[0] eq "archive")){
	&set_build_config();	
	my($t, $v) = &readVersion_($BUILD_VERSION_FILE);
	&do_archive_($t, $v, @argv);
    }elsif(($ARGV[0] eq "transfer")){
	&set_build_config();
	my($t, $v) = &readVersion_($BUILD_VERSION_FILE);
	&do_transfer_($t, $v, @argv);
    }elsif(($ARGV[0] eq "deploy")){
	&set_build_config();
	&do_deploy_(@argv);
    }elsif(($ARGV[0] eq "ssh")){
	&do_ssh_(@argv);
    }elsif(($ARGV[0] eq "get-license")){
	&do_get_license_(@argv);
    }elsif(($ARGV[0] eq "depend")){
	die "not implemented"
    }elsif($ARGV[0] eq "help"){
	print STDERR <<"HELP";

Running this program might need some settings:
- \$PATH environment variable should contain $BINDIR
- https_proxy environment variable should be set if necessary.(I.e, if you are behind firewall.)
- \$HOME/.m2/settings.xml should be setup if necessary.
- SSH authorization_key setting may reduce password input.


HELP
	&usage_($0);
    }elsif($ARGV[0] eq "purge"){
	&do_purge_checkout_(@argv);
    }elsif($ARGV[0] eq "test"){
	&do_test_(@argv);
    }else{
	&usage_($0);
    }
}

sub do_prepare_{
    my(@config) = @_;
    &usage_($0) if($#config != 1);

    &write_build_config("install_dir" => $config[0], "tomcat_dir" => $config[1]);
}

#
sub do_fetch_{
    my($jdk, $maven) = @_;
    &fetch($jdk,
	   "Cookie: oraclelicense=accept-securebackup-cookie");
    &fetch($maven, "");
}


sub do_setup_{
    my($jdk, $maven) = @_;
    if(! -d $BINDIR){
	mkdir $BINDIR or die "$BINDIR creation failed";
    }
        
    my $j = &untar_($BINDIR, $jdk);
    my $m = &untar_($BINDIR, $maven);

    
    my($mvn) =<< "END_OF_MVN";
#!/bin/sh

export JAVA_HOME=$BINDIR/$j
args=\$*

for opt in \$args; do
  case "\$opt" in
    "--show-mvn") echo "depgen.pl" ; exit 0;;
  esac
done

$BINDIR/$m/bin/mvn \$*
END_OF_MVN
    
    &create_script_($BINDIR, "mvn", $mvn);
}

sub do_checkout_{
    my($opt, @argv) = @_;
#    print "$SVN $opt @argv\n";
    `$SVN $opt @argv`;
    if($?){
	
    }
}


sub do_transfer_{
    my($tag, $ver, $archive, $staging_user, $staging_host) = @_;
    my(@path) = split /\//, $archive;
    
    if(-f $archive ){
#	print STDERR "scp $archive $staging_user\@$staging_host:";
	&run_("scp $archive $staging_user\@$staging_host:");
    }else{
	die "$archive not found.";
    }
    &ssh_("rm -rf $CHROOTX", " -t ", $staging_user, $staging_host);
    &ssh_("mkdir $CHROOTX",  " -t ", $staging_user, $staging_host);
    &ssh_("tar xvzf $path[-1] -C $CHROOTX", "", $staging_user, $staging_host);
}

sub do_ssh_{
    my($staging_user, $staging_host, @configs) = @_;
    if($#configs != 0){
	&usage_("$0 $#configs");
    }
    my($user, $host) = &read_config($configs[0]); #%rep_info ($op, $from, $to, $reps);
    &ssh2("ssh -t $user\@$host", $staging_user, $staging_host);
}


sub do_deploy_{
    my($print) = @_;
    my($just_print) = 0;
    my($staging_user, $staging_host, @configs);


    print "-----> $just_print\n";
    
    if($print eq "-print"){
	$just_print = 1;
	($print, $staging_user, $staging_host, @configs) = @_;
    }else{
	($staging_user, $staging_host, @configs) = @_;
    }
    
    if($#configs < 0){
	&usage_($0);
    }

    my($x)="x";
    foreach my $repfile (@configs){
	my($user, $host, $top, %rep_info) = &read_config($repfile); #%rep_info ($op, $from, $to, $reps);
	my $script = &create_replace_script_($host, %rep_info);

	print "\nscp $CHROOT/$script $staging_user\@$staging_host:$CHROOTX\n";
	if(!$just_print){
	    &run_("scp $CHROOT/$script $staging_user\@$staging_host:$CHROOTX");
	}
	print "run $CHROOTX/$prod/bin/deploy_one.sh $user $host $top $CHROOTX/$script\n";
	if(!$just_print){
	    &ssh_("$CHROOTX/$prod/bin/deploy_one.sh $user $host $top $script", " -t ", $staging_user, $staging_host);
	}
	
    }
    
}

sub do_build_{
    my($tag, $ver, @dirs) = @_; 

    print STDERR "do_build_:@dirs\n";
    if($#dirs < 0){
	&usage_($0);
    }

#    my($show_info) = `mvn --show-info`;
#    chomp($show_info);
    my($show_info) = "";

    $? = 0; # XXX
    if($?){
	die "mvn --show-info failed. This means we are not using mvn wrapper generated by $0 setup.";
    }
    
    if($0 =~ m|$show_info|){
    }else{
	die "Non mvn wrapper is used as psuedo mvn.";
    }
    &run_("rm -rf \$HOME/.m2/repository/com"); #XXXX


    foreach my $d (@dirs){
	chdir $d || die "cd $d failed";
	print "$d:  mvn -X clean install dependency:copy-dependencies -Dmaven.test.skip=true\n";
	&run_mvn("-X clean install dependency:copy-dependencies -Dmaven.test.skip=true");
	chdir $cwd || die "cd $cwd failed";
    }

}


sub do_archive_{
    my($tag, $ver, @dirs) = @_;
    
    my @dirs2 = &find_pom_dirs(@dirs);
    my %artifacts;
    foreach my $d (@dirs2){
	chdir $d || die "cd $d failed";	
    	my @triples = &get_deps_($d); #
	chdir $cwd || die "cd $cwd failed";
	foreach my $t (@triples){
	    my($dir, $target, $scope) = @$t;
	    my($c) = &l($dir);
	    $artifacts{"$target"} = $scope;
	}
    }
    my($lib, $bin, $archive);

    if($ver eq ""){
	$lib = "$prod/lib";
	$bin = "$prod/bin";
	$archive = "archive.tar.gz";
    }else{
	$lib = "$prod/lib.$ver";
	$bin = "$prod/bin";
	$archive = "archive.$ver.tar.gz";
    }
    &run_("$RM -rf $CHROOT");
    &mkdir_($CHROOT);
    &install_dir_($root, "0755", "$CHROOT/$bin", "$CHROOT/$lib");
    
    &create_deploy_self_($tag, $ver, $prod, $lib, $bin, $archive, "$CHROOT/$prod");
    &create_deploy_one_($tag, $ver, $prod, $lib, $bin, $archive, "$CHROOT/$prod");
    &create_archive($tag, $ver, $lib, $bin, $archive, "$CHROOT/$prod", \%artifacts, @dirs);
}


sub create_deploy_self_{
    my($tag, $ver, $prod, $lib, $bin, $archive, @dirs)  = @_;
    my($lib_) = (split /\//, $lib)[-1];
    my($sh) = "deploy_self.sh";

    my $content =  << "END_OF_DEPLOY";
# The script runs on target server.
user=\$1
top=\$2
rep_script=\$3

echo "\$user \$top \$rep_script"

if [ ! -d \$top ]; then
  mkdir \$top
fi

home="~\$user"

#(cd \$top; sudo tar xozf \$home/$CHROOT/$archive )
echo "deploy_self tar $archive"
sudotar="sudo tar xovzf \$home/$CHROOT/$archive -C \$top"
eval \$sudotar || exit 1  # be careful not to supply unnecessary thing

echo "deploy_self \$rep_script \$top"
sudo \$rep_script \$top || exit 1

echo "deploy_self ch.sh"
sudo $CHROOT/$bin/ch.sh \$top || exit 1
echo "deploy_self check \$top/$prod/lib"
if [ -L \$top/$prod/lib ]; then
  sudo rm -f \$top/$prod/lib || exit 1
fi

echo "deploy_self ln -s"
sudo ln -s $lib_ \$top/$prod/lib || exit 1

#echo "4"
#crons=`find $CHROOT -name "*.cron" `
#echo "5"
#tmp=`mktemp tmp.XXXX`
#echo "6"
#cat <<END>\$tmp
# Registering cron job needs much care, since crontab -r removes all
# the job registered for the user. It is recommended that you check
# current registration with crontab -l and decide what should be done
# If it is not registed, this shell script can help you a bit.
# crontab -l # to check the current jobs
# crontab crons
#END
#echo "7"
#cat \$crons >> \$tmp
#echo "8"
#mv \$tmp crons
#echo "9"
exit 0
END_OF_DEPLOY
    &create_script_("$CHROOT/$bin", $sh, $content);
}

sub do_tag_{
    my($old, $new);
    my($message) = <<"MESSAGE";
Creating tag is as follows.
svn copy url1 url2

MESSAGE
    die $message . "do_tag_ currently not implemented";
}

sub create_purge_{
    my $content = <<"END_OF_PURGE";
target_user=\$1
target_host=\$2
target_top=\$3

find $install_top -type f | sed -e 's/^/\$target_top\//' |ssh -t \$target_user\@\$target_host sudo xargs rm -f
END_OF_PURGE
}

sub create_deploy_one_{
    my($tag, $ver, $prod, $lib, $bin, $archive, @dirs)  = @_;
    chomp($lib);
    my($lib_) = (split /\//, $lib)[-1];
    my($sh) = "deploy_one.sh";

    # This script runs on staging server.
    my $content = <<"END_OF_DEPLOY";
target_user=\$1
target_host=\$2
target_top=\$3
rep_script=\$4

echo "deploy_one rm $CHROOT"
ssh \$target_user\@\$target_host rm -rf $CHROOT || exit 1

echo "deploy_one mkdir $CHROOT"
ssh \$target_user\@\$target_host mkdir $CHROOT || exit 1

echo "deploy_one scp $archive"
scp $archive \$target_user\@\$target_host:$CHROOT || exit 1

echo "deploy_one tar xvzf $archive"
ssh -t \$target_user\@\$target_host tar xvzf $CHROOT/$archive -C $CHROOT || exit 1

echo "deploy_one run \$rep_script"
scp $CHROOTX/\$rep_script \$target_user\@\$target_host:$CHROOT/$install_top || exit 1

echo "deploy_one running deploy_self"
ssh -t \$target_user\@\$target_host $CHROOT/$bin/deploy_self.sh \$target_user \$target_top $CHROOT/$install_top/\$rep_script

END_OF_DEPLOY
#    print "$content";
    &create_script_("$CHROOT/$bin", $sh, $content);
}

sub create_archive{
    my($tag, $ver, $lib, $bin, $archive, $prod, $arts, @dirs)  = @_;

    &collect_config(@dirs);
    &collect_jar($lib, $arts, @dirs);
    &create_change_owner_mode_script_($bin, "ch.sh", $archive);
    
    &archive_($CHROOT, $archive);
}

sub l{
    my($path) = @_;
    my(@path) = split(/\//, $path);

    return "$path[-1]";
}
sub collect_config{
    my(@dirs) = @_;
    foreach my $d (@dirs){
	print "$d\n";
	open(my $FIND, "find $d |") or die "find $d failed";
	while(my $path = <$FIND>){
	    chomp $path;
	    my($tag, $dir, $module, $from, $to, $mode) = ("", "", "", "", "", "");


	    $path =~ s|^\.\/||; # strip ./
	    if($path =~    m|(.+)/config/([^\/]+\.sh)$|){
		($tag, $dir, $module, $from, $mode) = ("config", $1, &l($1), "$2", "0755");
		$to = "$prod/$module/bin";
	    }elsif($path =~ m|(.+)/bin/([^\.\/]+)$|){     #startup script
		($tag, $dir, $module, $from, $mode) 
		    = ("startup",$1,  &l($1), "$2",  "0755");
		$to = "$prod/etc/init.d";
	    }elsif($path =~ m|(.+)/config/(logback\.xml)$|){
		($tag, $dir, $module, $from, $mode) 
		    = ("logback", $1, &l($1), "$2", "0644");
		$to = "$prod/$module/config";
	    }elsif($path =~ m|(.+)/config/([^\/]+\.properties)$|){
		($tag, $dir, $module, $from, $mode) = ("prop", $1, &l($1), "$2", "0644");
		$to = "$prod/$module/config";
	    }elsif($path =~ m|(.+)/config/([^\/]+\.cron)$|){
		($tag, $dir, $module, $from, $mode) = ("cron",$1, &l($1), "$2", "0644");
		$to = "$prod/$module/config";
	    }elsif($path =~ m|(.+)/database/([^\/]+\.sql)$|){
		# This is special treatment. This code will be removed after normalization.
		($tag, $dir, $module, $from, $mode) = ("sql", $1, &l($1), "$2", "0644");
		$to =  "$prod/$module/sql";
	    }elsif($path =~ m|(.+)/sql/([^\/]+\.sql)$|){
		($tag, $dir, $module, $from, $mode) = ("sql", $1, &l($1), "$2", "0644");
		$to =  "$prod/$module/sql";
	    }else{
		next;
	    }
	    if(-f "$dir/pom.xml" or -f "$dir/../pom.xml"){
#		print "2-1----->$tag <$dir> $module $from $to\n";
	    }else{
		next;
#		print "2-2----->$tag <$dir> $module $from $to\n";
	    }
	    $to =~ s|//|/|g;

	    if(! -d "$CHROOT/$to"){
#		print ">>>$CHROOT/$to\n";		
		&install_dir_($root, "0755", "$CHROOT/$to");
	    }

	    if( ! -d $path){
		&install_file_($root, $mode, $path, "$CHROOT/$to");
	    }else{
		print "install $path ignored\n";
	    }
	}
	close($FIND) || die "find error";
    }
}

sub collect_jar{
    my($lib, $art, @dirs) = @_;
    my %artifacts = %$art;

    foreach my $d (@dirs){
	print "$d\n";
	open(my $FIND, "find $d |") or die "find $d failed";
	while(<$FIND>){
	    if(m|jar$|){
#		print "$_";
	    }
	    chomp;

	    my($module, $dep, $name, $target, $pack);
	    if(m|(.+)/target/.+jar-with-dependencies\.jar|){
		next;
	    }elsif(m|(.+)/target/dependency/([^/]+\.jar)|){
		($module, $dep, $name, $target, $pack) = ($1, 1, $2, $_, "jar");
	    }elsif(m|(.+)/target/([^/]+\.jar)|){
		($module, $dep, $name, $target, $pack) = ($1, 0, $2, $_, "jar");
#	    }elsif(m|(.+)/target.+/([^/]+\.war)|){
	    }elsif(m|(.+)/target/([^/]+\.war)|){
		($module, $dep, $name, $target, $pack) = ($1, 0, $2, $_, "war");
	    }else{
		#		print "Warning $_\n";
		next;
	    }
	    $module = &l($module);
	    my($w) = "$CHROOT/$lib/$module";
	    $module =~ s/_/\-/;
	    my($store) = "$CHROOT/$install_dir/libs/";
	    
	    $target =~ m|([^/]+)$|;
	    my $base = $1;

	    my $combined_name = "$module:$base";
#	    foreach my $k (keys %artifacts){
#		print "$combined_name <--> $k\n";
#	    }


	    if($artifacts{"$combined_name"} eq "test"){
		print "####$target is used for test. Ignored. $base $artifacts{$combined_name}\n";
	    }else{
		if($pack eq "war"){
		    # War file will be
		    if(! -d "$CHROOT/$tomcat_dir"){
			&install_dir_($tomcat, "0755", "$CHROOT/$tomcat_dir");
		    }
		    &install_file_($tomcat, "0755", $target, "$CHROOT/$tomcat_dir");
		}else{
		    # Jar file !
		    if(! -d $w){
			&install_dir_($root, "0755", $w);
		    }
		    if(! -d $store){
			&install_dir_($root, "0755", $store);
		    }
		    &install_file_($root, "0644", $target, "$store");
		    &link_file("$w", "$name", "../../libs");
		}
	    }

	}
	close($FIND) || die "find error";
    }
}

sub link_file{
    my($link_from_dir, $name, $link_to_dir) = @_;

#    print "$link_from_dir, $name, $link_to_dir \n";
    chdir($link_from_dir) or die "cd $link_from_dir failed";

    if ( ! -l $name){
	`ln -s $link_to_dir/$name .`;
	die "symbolic link $link_to_dir/$name failed" if($?);
    }else{
	print STDERR "$name already exists. $link_from_dir $link_to_dir\n";
    }
    chdir($cwd) or die "cd $cwd failed";
}

sub do_test_{
    my @dirs = &find_pom_dirs(@_);
    print "@dirs\n";
}

sub get_deps_{
    my($d) = @_;
    my @r;
#    chdir $d or die "cd $d failed";
    if(! -f "pom.xml"){
	die "No pom.xml found. $d";
    }
    open(my $F, "mvn dependency:list |") or die "mvn failed";
	my($module);    
#    while(<$F>){
#	my($module);
#	chomp;
	while(<$F>){
	    chomp;	    

	    if(m|^\[INFO\] Building ([^ ]+) |){
		$module = $1;
		last;
	    }
	}
	while(<$F>){
	    chomp;	    
	    last if(m|^\[INFO\] The following files have been resolved:|);
	}
	while(<$F>){
	    chomp;
	    if(m|\[INFO\] +((.+):(.+):(.+):(.+):(.+))|){
		my($gId, $artId, $packType, $version, $scope) = split /:/, $_; #/
		my $target = "$d:$3-$5.$4";
		$module =~ s/_/\-/;
#		print "--------------$target  $scope\n";
		#		print "$target -> $6\n";
		my @x = ($d, $target, $scope);
		push @r, \@x;
	    }else{
		last;
	    }
	}
#    }
#    chdir $cwd or die "cd $cwd failed";    
    close($F) || die "mvn dependency:list error";

    return @r;
}

# supposed to be called after mvn compile is called
sub find_pom_dirs{
    my(@dir) = @_;
    my(@r);
    open(my $FIND, "find @dir -name pom.xml -type f|") or die "find failed";
    while(<$FIND>){
	chomp;
	s/\/+pom\.xml$//;
	push @r, $_;
	if( -d "$_/target/"){
	    push @r, $_;
	}
    }
    close($FIND) || die "find error";
    return @r;
}

sub run_mvn{
    my($opt) = @_;
    my($mvn) = "mvn $opt ";
#    print "$mvn\n";
    my $res = `$mvn`;
#    my @res = split(/\n/, $res);

    if($?){
	die "$res\n Sorry $mvn failed.";
    }
}

sub archive_{
    my($chroot, $archive)  = @_;
    chdir $chroot or die "cd $chroot failed";
    #    &run_("$TAR cvzf $archive $install_top 2>&1 ");
#    &run_("$TAR cvzf $archive . 2>&1 ");

    my(@dirs);
    open(my $LS, "ls |") or die "ls command failed";
    while(my $l = <$LS>){
	chomp $l;
	if( -d $l){
	    push @dirs, $l;
	}
    }
    if($#dirs < 0){
	die "no directries for archiving";
    }

    &run_("$TAR cvzf $archive @dirs");
    close($LS) || die "ls";
    chdir $cwd or die "cd $cwd";
}


sub install_opt{
    my($owner, $mode) = @_;
    my($o, $g) = split(/\:/, $owner);
    my(@opt);

    return @opt;
}

sub create_change_owner_mode_script_{
    my($dir_sh, $sh, $archive) = @_;
    chdir $CHROOT or die "cd $CHROOT failed";
    open(my $FIND, "find . -type d |") or die "find . | failed";
    my @dirs;
    while(<$FIND>){
	chomp;
	next if(m|^\.$|);
	s/^\.\///;
	push @dirs, $_;
    }
    close($FIND) || die "find";
    chdir $cwd or die "cd $cwd failed";

    my $in_chroot = &change_owner_mode_in_chroot_(@dirs);
    my $instaled = &change_owner_mode_with_install_();
    my $content = <<"END";
top=\$1

$in_chroot

$instaled
END


    &create_script_("$CHROOT/$dir_sh", $sh, $content);    
}

sub change_owner_mode_in_chroot_{
    my(@dirs) = @_;
    my($content);
    foreach my $d (@dirs){
	next if(not($d =~ m|^$install_dir|));
	$content .= <<"END_OF_CONTENT";
chown $root \$top/$d
chmod 0755 \$top/$d
END_OF_CONTENT
    }
    return $content;
}

sub change_owner_mode_with_install_{
    my($content);
    foreach my $p (@install_params){
	my($owner, $mode, $path) = @$p;
	$path =~ s|^$CHROOT||;
#	print "@$p \n";
	if($mode){
	    $content .= "chmod $mode \$top/$path\n";
	}
	if($owner){
	    $content .= "chown $owner \$top/$path\n";
	}
    }
    return $content;
}

sub install_{
    my($owner, $mode, $from, $to, @opt) = @_;
    $owner =~ s/\:/./;
    my(@r) = ($owner, $mode, $to);
#    print "#### @r\n";
    push @install_params, \@r;

    push @opt, &install_opt($owner, $mode);
    if($from eq ""){
	push @opt, " -d ";
    }
    my($inst) = "$INSTALL @opt $from $to";
#    print "<$inst> <$from> <$to>\n";
    &run_($inst);
}


sub install_dir_{
    my($owner, $mode, @dirs) = @_;
    foreach my $d (@dirs){
	&install_($owner, $mode, "", $d);
    }
}

sub install_file_{
    my($owner, $mode, $from, $to, @opt) = @_;
    my @from_ = split /\//, $from;
    my @to_ = split /\//, $to;
    if($from_[-1] eq $to_[-1]){ 
	&install_($owner, $mode, $from, $to, @opt);
    }else{
	&install_($owner, $mode, $from, "$to/$from_[-1]", @opt);
    }
}

sub install_files_{
    my($owner, $mode, $dir, @confs) = @_;
    foreach my $f (@confs){
	&install_file_($owner, $mode, $f, $dir);
    }
}


sub get_conf_{
    my($conf, $dir) = @_;
    my @confs;
    open(my $FIND, "find $dir -type d -name conf |") or die "find failed for open";
    while(my $l = <$FIND>){
	chomp $l;
	my $c = $l;
	$c =~ s/$conf$//;
	if( -f "$c/pom.xml"){
	    open(my $F, "find $l -type f |") or die "find failed for open";
	    while(my $f = <$F>){
		chomp $f;
		push @confs, $f;
	    }
	    close($F) || die "find";
	}
    }
    close($FIND) || die "find";
    return \@confs;
}

sub get_confs_{
    my($conf, @dirs) = @_;
    my @confs;
    foreach my $d (@dirs){
	my $confs = &get_conf($conf, $d);
	push @confs, @$confs;
    }
    return @confs;
}


sub ssh2{
    my($command, $user, $host) = @_;
#    print "ssh -t $user\@$host $command\n";
    exec "ssh -t $user\@$host $command";
}

sub ssh_{
    my($command, $opt, $user,  @hosts) = @_;
    print STDERR "ssh $user $command --> @hosts\n";
    foreach my $h (@hosts){
	&ssh__($user, $h, $command, $opt);
    }
}


sub ssh__{
    my($user, $host, $command, @opt) = @_;
    #    print "ssh $host $command @opt\n";
    print STDERR "ssh $user\@$host $command @opt\n";

    open(my $SSH, "ssh @opt $user\@$host $command |") or die "ssh $host $command failed";

    while(<$SSH>){
	print;
    }
    close($SSH) || die "ssh_ $command";
}

sub run_{
    my($command) = @_;
    `$command`;
    if($?){
	die "\n$command failed";
    }
}

sub untar_{
    my($dir, $tgz) = @_;

    chdir $dir || die "cd $dir failed";
    open(my $TAR, "$TAR xvzf $cwd/$tgz 2>&1 |") or die $!;
    my $top;
    while(<$TAR>){
	if(m/^(x )?([^\/]+)/){
	    $top = $2;
	}
    }
    close($TAR) || die "tar";

    if($top ne ""){
	chdir $cwd || die "cd $dir failed";
	return $top;
    }else{
	die "no contents found in $tgz";
    }
}

sub get_tag{
    my($a) = @_;
    my($tag, $ver) = split(/:/, $a);

    if($tag eq ""){

	return ("time", $build_started);
    }else{
	if($tag eq "tag" and $ver ne ""){
	    return ($tag, $ver);
	}elsif($tag eq "rev" and $ver =~ m|[1-9][0-9]*|){
	    return ($tag, $ver);
	}elsif($tag eq "time" and $ver ne ""){
	    return ($tag, $ver);
	}else{
	    return ("time", $build_started);
	}
    }
}



sub create_script_{
    my($d, $file, $script) = @_;
    &mkdir_($d);
    my($f) = "$d/$file";
    open(my $SCRIPT, ">$f") or die "cannot create $f";

    my $head = <<"BIN_SH";
#!/bin/sh

BIN_SH
    
    print $SCRIPT "$head$script";
    close($SCRIPT);

    my($mode) = 0755;
    chmod $mode, $f || die "chmod $f failed";
}

sub mkdir_{
    my($d) = @_;
    if( ! -d $d){
	mkdir($d) or die "Cannot mkdir $d";
    }
}

sub findFile{
    my($file, @dirs) = @_;
    foreach my $d (@dirs){
	my($f) = "$d/$file";
	if( -f $f){
	    return $f
	}
    }
    die "$file not found in @dirs";
}

sub fetch{
    my($url, $cookie) = @_;
    my(@url) = split /\//, $url;
    my($curl);
    my($file) = $url[-1];

    if($cookie eq ""){
	$curl = "$CURL -j -L ";
    }else{
	$curl = "$CURL -j -k -L -H \"$cookie\" ";
    }
    print STDERR "$url\n";
    $curl .= "$url > $file";
    if( ! -f $file){
	`$curl`;
	if($?){
	    die "$curl failed";
	}
    }
}

sub readVersion_{
    my($f) = @_;
    open(my $F, "$f") or &get_tag(":");
    my($l) = <$F>;
    chomp($l);
    close($F) || die "read version";
    my($R, $V) = &get_tag("$l");
    return($R, $V);
}
sub writeVersion_{
    my($f, $r, $v) = @_;

    my($R, $V) = &get_tag("$r:$v");
    open(my $F, ">$f") or die "cannot create $f";
    print $F "$R:$V";
    close($F) || die "write version";
}

sub install_setup{
    while(<DATA>){
	next if(m|^#|);
	next if(m|^(s*)$|);
	my($path, $o_g, $perm) = split /\s+/;
#	print "$path --> $o_g --> $perm\n";
    }
}

sub read_section{
    my($handle, $top) = @_;
    my($from, $to) = ("", "");
    my($op, @rest);
    while(<$handle>){
	# first, search [???] line.
	chomp;
	if(m|^\[(.+)\]|){
	    #	    $target = $1;
	    #	    ($from, $to) = ($1, "$top/$1");
	    my @direction = split qw(:), $1;
	    $op = shift @direction;
	    $from = shift @direction;
	    $to = "$top/" . shift @direction;

	    @rest = @direction;
	    last;
	}
    }
    if($from eq ""){
	return (); # almost end of file
    }
    
    my @list;
    while(<$handle>){
	chomp;
	next if(m|^#|);
	last if(m|^$|);
	push @list, $_;
    }
    return ($op, $from, $to, \@list, @rest);
}

sub read_config{
    my($file) = @_;
    my %reps;
    open(my $F, $file) or die "Cannot open $file.";
    my($user, $host, $top) = &read_global_settings($F);
    
    while(!eof($F)){
	my ($op, $from, $to, $reps, @rest) = &read_section($F, $top);
#	print "@$reps @rest\n";
	if(defined($reps{$from})){
	    die "file duplication in $file";
	}
	if($from ne ""){
	    my @a = ($op, $from, $to, $reps);
#	    print "#####$op $to @$reps\n";
	    $reps{$from} = \@a;
	}
    }
    close($F);
    return ($user, $host, $top, %reps);
}

sub read_global_settings{
    my($F) = @_;
    my(%global);
    while(<$F>){
	next if(m|^#|);
	last if(m|^$|);
	
	my($key, $val) = split qw(:), $_;
	chomp $val;
	$global{$key} = $val;
    }
    if($global{"User"} eq ""){
	die "User not defiend in config file";
    }
    if($global{"Host"} eq ""){
	die "Host not defiend in config file";
    }
    if($global{"Top"} eq ""){
	die "Top not defiend in config file";
    }
    
    return ($global{"User"}, $global{"Host"}, $global{"Top"});
}

sub replace_command_{
    my($file, $op, $from, $to, @rest) = @_;### Ugly hack!
#    print "<$op> $from $to\n";
    my($content);

    my $dir = $to;
    $dir =~ s|[^\/]+$||;
#    print ">>> $dir $to\n";
    
    foreach my $rep (@rest){
	my $printed = 0;
#	print "$rep ";
	my($left, $right) = split(/-->/, $rep);
	if($right eq ""){
	    die "config file format error $rep";
	}else{
	    if($left =~ m/\'/ or $right =~ m/\'/ and $printed == 0){
		print STDERR "Check replace_command_ since it contains single quote.";
		sleep 7;
		$printed  = 1;
	    }
	    $content .= "s|^$left\$|$right|;"
	}
    }
    if($op eq "CONF" or $op eq "SCRIPT"){
	return <<"END_OF_SCRIPT";
if [ -f $CHROOT/$file ]; then
top=\$1

f=\`mktemp tmp.XXXXX\`
sed -e \'$content \' $CHROOT/$file > \$f
install -d $dir
mv \$f $to
else
  echo "$CHROOT/$file not found."
  exit 1
fi
END_OF_SCRIPT
    }elsif($op eq "CRON"){
	return <<"END_OF_SCRIPT";
top=\$1

if [ -f $CHROOT/$file ]; then
f=\`mktemp tmp.XXXXX\`
sed -e \'$content \' $CHROOT/$file > \$f
install -d $dir
mv \$f $to
else
  echo "$CHROOT/$file not found."
  exit 1
fi
END_OF_SCRIPT
	    
    }else{
	die "unknown op <$op> found";
    }
}

# Needs some investigation for security.
sub create_replace_script_{
    my($host, %reps) = @_;
    my($content);
    foreach my $f (keys %reps){
	my($x) = $reps{$f};
	my($op, $from, $to, $rest) = @$x;

	if($from =~ m|$install_dir|){
	    print "### $f $op $from $to    -- @$rest";
	    $content .= &replace_command_($f, $op, $from, $to, @$rest);
	}else{
	    die "$from should be in $install_dir";
	}
    }

    &create_script_($CHROOT, "$host.sh", $content);
    return "$host.sh";
}

sub set_build_config{
    my %config = &read_build_config();
    if(!defined($config{"install_dir"})){
	die "No install_dir is defined in $BUILD_CONFIG $config{'install_dir'}";
    }
    if(!defined($config{"tomcat_dir"})){
	die "No tomcat_dir is defined in $BUILD_CONFIG $config{'install_dir'}";
    }
    
    $install_dir = $config{"install_dir"};
    $install_dir =~ s|^(\/*)||; # strip / to allow possible misoperation.
    my @path = split /\//, $install_dir;
    $install_top = $path[0];
    $prod = $install_dir;
    
    $tomcat_dir = $config{"tomcat_dir"};
    $tomcat_dir =~ s|^(\/*)||; # strip / to allow possible misoperation.
}

sub write_build_config{
    my(%c) = @_;
    open(my $F, ">$BUILD_CONFIG") or die "cannot create $BUILD_CONFIG .";
    foreach my $k (keys %c){
	print $F "$k:$c{$k}\n";
    }
    close($F);
}

sub read_build_config{
    my(%c) = @_;
    open(my $F, "$BUILD_CONFIG") or die "cannot open $BUILD_CONFIG .";
    while(my $l = <$F>){
	chomp $l;
	my ($k, $v) = split /:/, $l;
	if(defined($k) and defined($v)){
	    $c{$k} = $v;
	}
    }
    close($F);
    return %c;
}

sub usage_{
    my($prog) = @_;
    my @path = split /\//, $prog;
    $prog = $path[-1];
    print STDERR <<"END_OF_USAGE";
usage:$prog fetch                           # fetch jdk and apache-maven
      $prog setup jdk.tar.gz maven.tar.gz   # setup mvn script for our build environemnt
      $prog prepare top_dir tomcat_dir      # setup top directory and tomcat war file directory
      $prog checkout url                    # checkout latest source from url
      $prog tag-checkout tag url            # checkout latest source from url with tag
      $prog rev-checkout rev url            # checkout latest source from url with rev
      $prog build dir (dirs...)             # build files in local directory
      $prog archive dir (dirs...)           # build archive files in local directory
      $prog trasfer rchive-file staging-user staging-host     # transfer archived file to staging server
      $prog deploy staging-user staging-host config (config...)       # deploy files on hosts
      $prog deploy -print staging-user staging-host config (config...)       # print how to use deploy script by manual
      $prog ssh staing-user staging-host config                       # ssh to login host
      $prog clean  staging-user staging-host config (config...)       # currently not implemented
      $prog create-table staging-user staging-host [configs]          # currently not implemented
      $prog upload-table staging-user staging-host [configs]          # currently not implemented

      $prog help
END_OF_USAGE

    exit 1;
}



    

__END__
#config file
User:
Host:
Top:

[file1]
string--->replacement

[file2]
string--->replacement




