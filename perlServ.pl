#!/usr/bin/perl -w

use strict;
use IO::Socket;
use IO::Handle;

our $version = "0.5r1";

our $s404 = "404 File Not Found";
our $s403 = "403 Forbidden";
our $s200 = "200 OK";

our %types = (
	gif => "image/gif",
	jpeg => "image/jpeg",
	jpg => "image/jpeg",
	bmp => "image/bmp",
	tiff => "image/tiff",
	html => "text/html",
	txt => "text/plain"
);

our %conf = &parseConfig;
our $webroot = $conf{web_root};

sub Wait {
	wait;
}

sub trimSpace {
	my $s = shift;
	$s =~ s/^\s+//;
	$s =~ s/\s+$//;
	return $s;
}

sub parseConfig {
        open(my $conffh, "<", "./perlServ.conf") or die "config: $!\n";
        my %conf = (
                bind_address => "",
                bind_port => "",
                log_file => "",
                web_root => "",
                dir_list => "",
        );
        my @confs = <$conffh>;
        foreach my $opt (@confs) {
                if($opt =~ m/^bind_address =/) {
                        $conf{bind_address} = trimSpace((split /=/, $opt)[1]);
                }
                elsif($opt =~ m/^bind_port =/) {
                        $conf{bind_port} = trimSpace((split /=/, $opt)[1]);
                }
                elsif($opt =~ m/^log_file =/) {
                        $conf{log_file} = trimSpace((split /=/, $opt)[1]);
                }
                elsif($opt =~ m/^web_root =/) {
                        $conf{web_root} = trimSpace((split /=/, $opt)[1]);
                }
                elsif($opt =~ m/^dir_list =/) {
                        $conf{dir_list} = trimSpace((split /=/, $opt)[1]);
                }
        }
        close($conffh);
        return %conf;
}

sub getMime {
	my ($ext) = @_;
	my ($key, $value);
	while (($key, $value) = each(%types)) {
		if($key eq $ext){
			return $value;
		}
	}
}	

sub serveHeader {
	my ($client, $webroot, $status, $req) = @_;
	my ($type, $ext);
        if(-f ($webroot . $req)) {
		$ext = (split /\./, $req)[-1];
		$type = getMime($ext);
	}
	else {
		$type = getMime("html");
	}
	print $client "HTTP/1.0 $status\r\n";
        print $client "Content-type: $type\r\n\r\n";
}	

sub serve404 {
	my ($client, $webroot, $req) = @_;
	serveHeader($client, $webroot, $s404, $req);
	print $client "<html><h3>404 - File Not Found</h3><hr><br><b>$req</b> could not be located on this server.<br><br><hr><br>perlServ $version</html>";
}

sub getReq {
	my ($client, $webroot, $raw) = @_;
	my $reqp = (split / /, $raw)[1];
	return $client, $webroot, $reqp;
}	

sub serveReq {
        my ($client, $webroot, $req) = @_;
        begin: {
		if(-d ($webroot . $req)) {
			if($conf{dir_list} eq "true") {
				if(-f ($webroot . $req . "index.html")) {
					$req = $req . "index.html";
					goto begin;
				}
				opendir(my $reqfh, $webroot . $req) or serve404($client, $webroot, $req);
				my @dir = readdir($reqfh);
				serveHeader($client, $webroot, $s200, $req);
				print $client "<html><h3>Directory Listing</h3><hr><br>";
				@dir = sort(@dir);
				foreach (@dir) {
					if(!($_ =~ m/^\./)) {
						$req =~ s/\/$//;
						if(-d ($webroot . $req . "/" . $_)) {
							print $client "<a href=\"$req\/$_\"> $_\/ </a><br>";
						}
						else {
							print $client "<a href=\"$req\/$_\"> $_ </a><br>";
						}
					}	
				}
				print $client "<br><hr><br>perlServ $version</html>";
				close($reqfh);
			}
			else {
				serveHeader($client, $webroot, $s403, $req);
				print $client "<html><h3>403 - Forbidden</h3></html>";
			}
		}
		else {
			open(my $reqfh, "<", "$webroot" . $req) or serve404($client, $webroot, $req);
                	if($reqfh->opened()) {
				serveHeader($client, $webroot, $s200, $req);
                        	while (<$reqfh>) {
                                	print $client $_;
                        	}
                        	close($reqfh);
                	}
        	}
	}
}

$SIG{CHLD} = \&Wait;

my $server = IO::Socket::INET->new(
LocalHost => $conf{bind_address},
LocalPort => $conf{bind_port},
Type => SOCK_STREAM,
Reuse => 1,
Listen => 10) or die "sock: $!\n";

open(my $logfh, ">>", $conf{log_file}) or die "log: $!\n";
print $logfh "perlServ $version listening on " . $conf{bind_address} . ":" . $conf{bind_port} . ", awaiting connections...\n\n";

our ($client, $client_addr);
while (($client, $client_addr) = $server->accept()) {
        next if my $pid = fork;
        die "fork:  $!\n" unless defined $pid;
        
	my @client_info;
        while(<$client>) {
                last if /^\r\n$/;
		push(@client_info, $_);
        }

        my ($client_port, $client_ip) = sockaddr_in($client_addr);
        my $client_ipnum = inet_ntoa($client_ip);
        my $client_host = gethostbyaddr($client_ip, AF_INET);
	if($client_host) {
        	print $logfh "Host: $client_host [$client_ipnum] - Request: $client_info[0]$client_info[2]\n";
	}
	else {
		print $logfh "Host: $client_ipnum [$client_ipnum] - Request: $client_info[0]$client_info[2]\n";
	}
	serveReq(getReq($client, $webroot, $client_info[0]));

        close($client);
        exit(fork);
}

continue {
        close($client);
        kill CHLD => -$$;
}

