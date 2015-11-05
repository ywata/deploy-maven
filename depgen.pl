#!/usr/bin/env perl

@Bins = ("/bin/", "/usr/bin/");
$TAR = "tar";
$SVN = "svn";
$RM  = "/bin/rm";
$CURL = "curl";

$BINDIR = "$ENV{HOME}/bin_";
$JAVA_HOME = "java_home";
$MAVEN_VER = "3.3.3";

$BUILD_VERSION_FILE = ".build_version";

$TAR = &findFile($TAR, @Bins);
$SVN = &findFile($SVN, @Bins);
$CURL = &findFile($CURL, @Bins);

$REMOTE = "remotehost:/home/users/";
    
$build_started = `date "+%Y%m%d-%H%M"`;
chomp($build_started);

    
chomp($cwd = `pwd`); # /bin/pwd

# main function is command dispatcher
&dispatch_(@ARGV);

sub dispatch_{
    my(@argv) = @ARGV;
    my($command) = shift @argv; # 
    my($r);
    
    print "ARGV:@ARGV \n";
    print "argv:@argv \n";
    
    if($ARGV[0] eq "setup"){
	&do_setup_(@argv);
    }elsif($ARGV[0] eq "fetch"){
	# XXX 
	&fetch("http://download.oracle.com/otn-pub/java/jdk/8u60-b27/jdk-8u60-linux-x64.tar.gz", 
	       "Cookie: oraclelicense=accept-securebackup-cookie");
	&fetch("http://ftp.yz.yamagata-u.ac.jp/pub/network/apache/maven/maven-3/3.3.3/binaries/apache-maven-3.3.3-bin.tar.gz")
    }elsif(($ARGV[0] eq "checkout")){
	&writeVersion_($BUILD_VERSION_FILE, "", "");
	&do_checkout_("checkout", @argv);
    }elsif(($ARGV[0] eq "tag-checkout")){
	die "tag-checkout currently not supported.";
	&writeVersion_($BUILD_VERSION_FILE, "tag", $argv[0]);
	my($opt) = " checkout" . shift @argv;
	&do_checkout_($opt, @argv);
    }elsif(($ARGV[0] eq "rev-checkout")){
	&writeVersion_($BUILD_VERSION_FILE, "rev", $argv[0]);
	my($opt) = "checkout  -r " . shift @argv;
	&do_checkout_($opt, @argv);
    }elsif(($ARGV[0] eq "build")){
	&do_build_(@argv);
    }elsif(($ARGV[0] eq "get-license")){
	&do_get_license_(@argv);
    }elsif($ARGV[0] eq "purge"){
	&do_purge_checkout_(@argv);
    }else{
	&usage_();
    }
}

sub do_build_{
    my(@dirs) = @_; 
    print STDERR "do_build_:@dirs\n";

    my($show_info) = `mvn --show-info`;
    chomp($show_info);

    $? = 0; # XXX
    if($?){
	die "mvn --show-info failed. This means we are not using mvn wrapper generated by $0 setup.";
    }
    
    if($0 =~ m|$show_info|){
    }else{
	die "Non mvn wrapper is used as psuedo mvn.";
    }
    my($file, $tag, $ver) = @_;
    my($c) = "$tag:$ver";
    if(&check_tag($c)){
	# Good.
    }else{
	die "Unknown tag $tag found.:$c";
    }
    
    open(W, ">$file") or die $!;
    print W "$c";
    close(W);
}

sub check_tag{
    my($a) = @_;
    my($tag, $ver) = split(/:/, $a);
    if($tag eq ""){
	#
	return 1;
    }else{
	if($tag eq "tag" and $ver ne ""){
	    return 1;
	}elsif($tag eq "rev" and $ver =~ m|[1-9][0-9]*|){
	    return 1;
	}else{
	    return 0;
	}
    }
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

    $curl .= "$url > $file";
    if( ! -f $file){
	`$curl`;
	if($?){
	    die "$curl failed";
	}
    }
}


sub usage_{
    my($prog) = @_;
    print STDERR <<"END_OF_USAGE";
usage:$prog setup jdk-id            # setup mvn & JAVA_HOME
      $prog checkout url            # checkout latest source from url
      $prog tag-checkout tag url    # checkout latest source from url with tag
      $prog rev-checkout rev url    # checkout latest source from url with rev
      $prog build [dirs]            # build and archive files to transfer

      $prog get-license dir [dirs]
END_OF_USAGE

    exit 1;
}
__END__

