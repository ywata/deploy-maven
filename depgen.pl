#!/usr/bin/env perl

use strict;
use strict "vars";
use strict "refs";
use strict "subs";
use warnings;

my @Bins = ("/bin/", "/usr/bin/");
my $TAR = "tar";
my $SVN = "svn";
my $RM  = "/bin/rm";
my $CURL = "curl";
my $INSTALL = "install";

my $BINDIR = "$ENV{HOME}/bin_";
my $JAVA_HOME = "java_home";
my $MAVEN_VER = "3.3.3";
my $BUILD_VERSION_FILE = ".build_version";
my $CHROOT = "chroot";
my $root = "bitnami.bitnami";

my @install_params;
my @replace_file;   # fileName -> ref of s/// commands array.

$TAR = &findFile($TAR, @Bins);
$SVN = &findFile($SVN, @Bins);
$CURL = &findFile($CURL, @Bins);
$INSTALL = &findFile($INSTALL, @Bins);

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
	# XXX 
	&fetch("http://download.oracle.com/otn-pub/java/jdk/8u60-b27/jdk-8u60-linux-x64.tar.gz", 
	       "Cookie: oraclelicense=accept-securebackup-cookie");
	&fetch("http://ftp.yz.yamagata-u.ac.jp/pub/network/apache/maven/maven-3/3.3.3/binaries/apache-maven-3.3.3-bin.tar.gz")
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
	my($t, $v) = &readVersion_($BUILD_VERSION_FILE);
	&do_build_($t, $v, @argv);
    }elsif(($ARGV[0] eq "transfer")){
	my($t, $v) = &readVersion_($BUILD_VERSION_FILE);
	&do_transfer_($t, $v, @argv);
    }elsif(($ARGV[0] eq "deploy")){
	&do_deploy_(@argv);
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

    }else{
	&usage_($0);
    }
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
	&run_("scp $archive $staging_user\@$staging_host:");
    }else{
	die "$archive not found.";
    }
    &ssh_("rm -rf usr", "", $staging_user, $staging_host);
    &ssh_("tar xvzf $path[-1]", "", $staging_user, $staging_host);
}

sub do_deploy_{
    my($staging_user, $staging_host, @configs) = @_;

    foreach my $repfile (@configs){
	my($user, $host, $top, %rep_info) = &init_replace($repfile);

	my $script = &create_replace_script_($host, %rep_info);
	&run_("scp $CHROOT/$script $staging_user\@$staging_host:usr/");
	&ssh_("usr/local/prod/bin/deploy_one.sh $user $host $top usr/$script", " -t ", $staging_user, $staging_host);
    }
    
}

sub do_build_{
    my($tag, $ver, @dirs) = @_; 
    print STDERR "do_build_:@dirs\n";

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

    my %deps;

    foreach my $d (@dirs){
	chdir $d || die "cd $d failed";
	&run_mvn("clean dependency:copy-dependencies package");
	my @dp = &get_dependencies($d);
	if(!defined($deps{$d})){
	    $deps{$d} = \@dp;
	}else{
	    die "$d is already defined";
	}
	chdir $cwd || die "cd $cwd failed";
    }

#    print ">>>>>>>@dirs \n";
    my @confs = &get_confs("conf", @dirs);


    my($lib, $bin, $conf, $archive);
    my $prod = "usr/local/prod";

    if($ver eq ""){
	$lib = "$prod/lib";
	$bin = "$prod/bin";
	$conf = "$prod/conf";
	$archive = "archive.tar.gz";
    }else{
	$lib = "$prod/lib.$ver";
	$bin = "$prod/bin";
	$conf = "$prod/conf";
	$archive = "archive.$ver.tar.gz";
    }
    &run_("$RM -rf $CHROOT");
    &mkdir_($CHROOT);
    &install_dir_($root, "0755", "$CHROOT/$bin", "$CHROOT/$conf", "$CHROOT/$lib");
    &install_files_($root, "0644", "$CHROOT/$conf", @confs);
    
    &create_deploy_self_($tag, $ver, $prod, $lib, $bin, $conf, $archive, "$CHROOT/usr/local/prod");
    &create_deploy_one_($tag, $ver, $prod, $lib, $bin, $conf, $archive, "$CHROOT/usr/local/prod");
    &create_archive($tag, $ver, $lib, $bin, $conf, $archive, "$CHROOT/usr/local/prod", \%deps, @dirs);
}

# host: chroot/archive.???.tar.gz 
# step server: $HOME/archive.???.tar.gz
#                   usr/local/prod/bin
#                   usr/local/prod/conf
#                   usr/local/prod/lib.???
# target server : $HOME/archive.???.tar.gz
#                      usr/local/prod/bin
#                      usr/local/prod/conf
#                      usr/local/prod/lib.???
#                  /usr/local/prod/bin
#                  /usr/local/prod/conf
#                  /usr/local/prod/lib.???
#                  /usr/local/prod/lib

sub create_deploy_self_{
    my($tag, $ver, $prod, $lib, $bin, $conf, $archive, @dirs)  = @_;
    my($lib_) = (split /\//, $lib)[-1];
    my($sh) = "deploy_self.sh";

    my $content =  << "END_OF_DEPLOY";
# The script runs on target server.
user=\$1
top=\$2
rep_script=\$3

mkdir \$top
cd \$top

su - \$user

# This is very dangerous.
#sudo tar xvzf \$user/$archive #\$HOME?
#sudo \$user/\$rep_script
tar xvzf \$user/$archive #\$HOME?
\$user/\$rep_script

#sudo $bin/ch.sh \$top

if [ -L $prod/lib ]; then
#  sudo rm -f $prod/lib
  rm -f $prod/lib
fi

#sudo ln -s $lib $prod/lib
ln -s $lib $prod/lib

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

find usr -type f | sed -e 's/^/\$target_top\//' |ssh -t \$target_user\@\$target_host sudo xargs rm -f
END_OF_PURGE
}

sub create_deploy_one_{
    my($tag, $ver, $prod, $lib, $bin, $conf, $archive, @dirs)  = @_;
    my($lib_) = (split /\//, $lib)[-1];
    my($sh) = "deploy_one.sh";
    # This script runs on staging server.
    my $content = <<"END_OF_DEPLOY";
target_user=\$1
target_host=\$2
target_top=\$3
rep_script=\$4

scp $archive \$target_user\@\$target_host:$archive
ssh -t \$target_user\@\$target_host tar xvzf $archive
scp \$rep_script \$target_user\@\$target_host:usr
ssh -t \$target_user\@\$target_host $bin/deploy_self.sh \\~\$target_user \$target_top \$rep_script
END_OF_DEPLOY
#    print "$content";
    &create_script_("$CHROOT/$bin", $sh, $content);
}

sub create_archive{
    my($tag, $ver, $lib, $bin, $conf, $archive, $prod, $deps, @dirs)  = @_;
    my %deps = %$deps;

    foreach my $d (@dirs){
#	print "---> @$deps{$d} @$deps{$d}\n";
	my %artifacts = &pack_conv($d, @$deps{$d});
	
	
	open(my $FIND, "find $d |") or die "find $d failed";
	while(<$FIND>){
	    my($where, $dep, $name, $target);
	    chomp;
	    if(m|(.+)/target/.+jar-with-dependencies\.jar|){
		next;
	    }elsif(m|(.+)/target/dependency/([^/]+\.jar)|){
		($where, $dep, $name, $target) = ($1, 1, $2, $_);
	    }elsif(m|(.+)/target/([^/]+\.jar)|){
		($where, $dep, $name, $target) = ($1, 0, $2, $_);
	    }else{
#		print "Warning $_\n";
		next;
	    }
	    my($w) = "$CHROOT/$lib/$where";

	    $target =~ m|([^/]+)$|;
	    my $base = $1;
	    if($artifacts{$base} eq "test"){
#		print "$target is used for test. Ignored. $base $artifacts{$base}\n";
	    }else{
#		print "$target is OK $base $artifacts{$base}\n";
		if(! -d $w){
		    &install_dir_($root, "0755", $w);
		}
#		print "$w/$name --> $target\n";
		&install_file_($root, "0644", $target, "$w/$name");
	    }
	}
	close($FIND);
    }
    &create_change_mode_owner_($bin, "ch.sh");
    
    &archive_($CHROOT, $archive);
}

sub pack_conv{
    my($d, @rest) = @_;
    my(%r);
    
#    print "pack_conv\n";
    foreach my $s (@rest){
#	print @rest;
	foreach my $l (@$s){
	    my($gId, $artId, $packType, $version, $scope) = split /:/, $l; #/
#	    print "$scope\n";
	    my($target) = "$artId-$version.$packType";
	    $r{$target} = $scope;
#	    print "$target -> $scope\n";
	}
    }
    return %r;
}

sub run_mvn{
    my($opt) = @_;
    my($mvn) = "mvn $opt 2>&1 ";
    my $res = `$mvn`;
#    my @res = split(/\n/, $res);

    if($?){
	die "$res\n Sorry $mvn failed.";
    }
}

sub archive_{
    my($chroot, $archive)  = @_;
    chdir $chroot or die "cd $chroot failed";
    &run_("$TAR cvzf $archive usr 2>&1 ");
    
    chdir $cwd or die "cd $cwd";
}


sub install_opt{
    my($owner, $mode) = @_;
    my($o, $g) = split(/\:/, $owner);
    my(@opt);

    return @opt;
}

sub create_change_mode_owner_{
    my($dir_sh, $sh) = @_;
    my($content, $annotation);
    $content = <<"END";
top=\$1
END

    foreach my $p (@install_params){
	my($owner, $mode, $path) = @$p;
	$path =~ s|^$CHROOT||;
#	print "@$p \n";
	if($mode){
	    $content .= "chmod $mode ./$path\n";
	}
	if($owner){
	    $content .= "chown $owner ./$path\n";
	}
    }
    &create_script_("$CHROOT/$dir_sh", $sh, $content);
}

#install_() is a bit tricky for supporting dir and file installation.
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
#    print "$inst\n";
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


sub get_conf{
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
	    close($F);
	}
    }
    close($FIND);
    return \@confs;
}

sub get_confs{
    my($conf, @dirs) = @_;
    my @confs;
    foreach my $d (@dirs){
	my $confs = &get_conf($conf, $d);
	push @confs, @$confs;
    }
    return @confs;
}

sub get_dependencies{
    my(@deps);
    open(my $F, "mvn dependency:list |") or die "mvn failed";
    if(! -f "pom.xml"){
	die "No pom.xml found.";
    }
    while(<$F>){
	last if(m|^\[INFO\] The following files have been resolved:|);
    }
    while(<$F>){
	if(m|\[INFO\] +((.+):(.+):(.+):(.+):(.+))|){
	    push @deps, $1;
	}else{
	    last;
	}
    }
    close($F);

    return @deps;
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
    close($SSH);
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
    close($TAR);

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
    close($F);
    my($R, $V) = &get_tag("$l");
    return($R, $V);
}
sub writeVersion_{
    my($f, $r, $v) = @_;

    my($R, $V) = &get_tag("$r:$v");
    open(my $F, ">$f") or die "cannot create $f";
    print $F "$R:$V";
    close($F);
}



sub install_setup{
    while(<DATA>){
	next if(m|^#|);
	next if(m|^(s*)$|);
	my($path, $o_g, $perm) = split /\s+/;
#	print "$path --> $o_g --> $perm\n";
    }
}

sub read_replacements{
    my($handle) = @_;
    my $target = "";
    while(<$handle>){
	# first, search [???] line.
	if(m|^\[(.+)\]|){
	    $target = $1;
	    last;
	}
    }
    if($target eq ""){
	return (); # almost end of file
    }
    
    my @list;
    while(<$handle>){
	chomp;
	next if(m|^#|);
	last if(m|^$|);
	push @list, $_;

    }
    return ($target, \@list);
}

sub init_replace{
    my($file) = @_;
    my %reps;
    open(my $F, $file) or die "Cannot open $file.";
    my($user, $host, $top) = &read_remote($F);
    
    while(!eof($F)){
	my ($target, $reps) = &read_replacements($F);
	if(defined($reps{$target})){
	    die "file duplication in $file";
	}
	if($target ne ""){
	    $reps{$target} = $reps;
	}
    }
    close($F);
    return ($user, $host, $top, %reps);
}

sub read_remote{
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
    if($global{"Root"} eq ""){
	die "Root not defiend in config file";
    }
    
    return ($global{"User"}, $global{"Host"}, $global{"Root"});
}


sub replace_script_{
    my($file, @rest) = @_;

    my($content);
    foreach my $rep (@rest){
	my($left, $right) = split(/-->/, $rep);
	if($right eq ""){
	    die "config file format error $rep";
	}else{
	    $content .= "s|^$left\$|$right|;"
	}
    }
    return <<"END_OF_SCRIPT";
top=\$1

f=\`mktemp tmp.XXXXX\`
sed -e \'$content \' $file > \$f
mv \$f $file;
END_OF_SCRIPT
}

# Needs some investigation for security.
sub create_replace_script_{
    my($host, %reps) = @_;
    my($content);
    foreach my $f (keys %reps){
	my($x) = $reps{$f};
	$content .= &replace_script_($f, @$x);
    }

    &create_script_($CHROOT, "$host.sh", $content);
    return "$host.sh";
}


sub usage_{
    my($prog) = @_;
    print STDERR <<"END_OF_USAGE";
usage:$prog fetch                           # fetch jdk and apache-maven
      $prog setup jdk.tar.gz maven.tar.gz   # setup mvn script for our build environemnt
      $prog checkout url                    # checkout latest source from url
      $prog tag-checkout tag url            # checkout latest source from url with tag
      $prog rev-checkout rev url            # checkout latest source from url with rev
      $prog build [dirs]                    # build and archive files in local directory
      $prog trasfer rchive-file staging-user staging-host     # transfer archived file to staging server
      $prog deploy staging-user staging-host [configs]        # deploy files on hosts
      $prog create-table staging-user staging-host [configs]  # currently not implemented
      $prog upload-table staging-user staging-host [configs]  # currently not implemented
      $prog help
END_OF_USAGE

    exit 1;
}
    

__END__
#config file
User:
Host:
Root:

[file1]
string--->replacement

[file2]
string--->replacement




