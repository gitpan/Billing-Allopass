package Billing::Allopass;
use strict;

use vars qw($VERSION @ISA @EXPORT $session_file $result);



$VERSION = "0.01";

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw( allopass_check $result);

use HTTP::Request::Common qw(GET POST);
use LWP::UserAgent;
#use CGI qw/:standard/;
use CGI::Cookie;
#use URI::URL qw(url);

my $baseurl = 'http://www.allopass.com/check/vf.php4';
my $session_file='';
my $ttl=60;
my $os=0;

my $error='';
=head1 NAME

Billing::Allopass - A class for micropayment system from allopass I<http://www.allopass.com/>

=head1 SYNOPSIS

  ### Session-based access control (more secure)

  use Billing::Allopass;
  my $allopass=Billing::Allopass->new($session_file, [$ttl]);
  
  # Check access
  if ($allopass->check($document_id, [$RECALL])){
        print "OK\n";
  } else {
        print $allopass->get_last_error;
  }
  
  # No further access for this user
  $allopass->end_session($document_id);

OR

  ### Simple access control 
  use Billing::Allopass;

  if (allopass_check($document_id, $RECALL)){
        print "OK\n";
  } else {
        print "NOK\n";
  }
  
  

=head1 DESCRIPTION

This class provides you a easy api for the allopass.com system. It automatically handles user sessions. See l<http://www.allopass.com> for more informations on this system.

=head1 METHODS

=over 4

=item B<$allopass=Billing::Allopass->new($session_file, [$ttl]);> Class constructor. Provides session-based access check.
    $session_file is the physical location for the session file. The webserver must have write access to it. 
    $ttl is the number of minutes of inactivity for automatically removing sessions. Default : 60.
    This function returns 0 if there are no write access to $session_file. This file must exists before calling this constructor.

=cut

sub new {
    my $class = shift;
    $session_file=shift;
    return(0) if !-e $session_file || !-w $session_file;
    my $lttl=shift; $ttl=$lttl if defined $lttl && $lttl > 0;
    my $self = bless {}, $class;
    return $self;
}

=item B<allopass_check($document_id, $code)> - Simply checks if a code has been recently validated for this document.
    You must perform this check within 2 minutes after the code is entered.

=cut
sub allopass_check {
    my ($doc_id, $code, $r) = @_;
    my ($res, $ua, $req);
    $ua = LWP::UserAgent->new;
    $ua->agent('Mozilla/5.0');
    $req = POST $baseurl,
        [
        'CODE'      => $code ,
	'to'        => $doc_id ,
        ];
    #$req->headers->referer($baseurl);
    $res = $ua->simple_request($req)->as_string;
    return 1 if _is_res_ok($res);
    0;
}

=item B<check> - Checks if a client have access to this document
Must be used in class context

=cut

sub check {
    my $self=shift;
    my ($doc_id, $code, $r) = @_;
    my ($res, $ua, $req);
    
    if (_is_session($doc_id)) {
        return(1);
    } elsif (defined $code && $code ne "") {
        $ua = LWP::UserAgent->new;
        $ua->agent('Mozilla/5.0');
        $req = POST $baseurl,
        [
        'CODE'      => $code ,
	'AUTH'        => $doc_id ,
        ];
        #$req->headers->referer($baseurl);
        $res = $ua->simple_request($req)->as_string;
        if(_is_res_ok($res)) {
            _add_session($doc_id, $code);
            _set_error('Allopass Recall OK');
            return(1);
        }
        
    }
    0;
}


=item B<$allopass->end_session($document_id)> - Ends user session for specified document.

=cut

sub end_session {
    my $self=shift;
    _end_session(@_);
}

=item B<$allopass->get_last_error()> - Returns last recorded error

=cut

sub get_last_error {
    my $self=shift;
    $error;
}

### PRIVATE FUNCTIONS ==========================================================
##
#
sub _is_session {
    my $doc_id = shift;
    my $ok=0;

    my %cookies = fetch CGI::Cookie;
    my $docid=$doc_id; $docid=~s/\//\./g;

    if (!$doc_id) {
        _set_error("No Document ID");
        return(0) 
    }
    if (!$cookies{$docid}){
        _set_error("No Session Cookie");
        return(0) 
    }
    return(0) if !defined $cookies{$docid}->value;
    
    my $code = $cookies{$docid}->value if defined $cookies{$docid}->value;
    
    
    _set_error("Error opening $session_file for read");
    open (TEMP, "$session_file") or return(0);
        if ($os == 0) {flock (TEMP, 2);}
        my @index = <TEMP>;
        if ($os == 0) {flock (TEMP, 8);}
    close (TEMP);
    _set_error("Error opening $session_file for write");
    open (OUTPUT, ">$session_file") or return(0);
        _set_error('No session match found');
        my $a=time;
        if ($os == 0) {flock (TEMP, 2);}
        for (my $i = 0; $i < @index; $i++) {
            $index[$i] =~s/\n//g;
            next unless ($index[$i]);
            my ($docid, $pass, $IP, $heure, @autres) = split (/\|/, $index[$i]);
            next if ($a > ($heure + $ttl * 60));
            if ($doc_id eq $docid && $code eq $pass){
                print OUTPUT "$docid|$pass|$IP|" . $a . "||\n";
                _set_error('Session found');
                $ok=1;
            } else {
                print OUTPUT "$docid|$pass|$IP|$heure||\n";
            }
        }
        if ($os == 0) {flock (TEMP, 8);}
    close (OUTPUT);
    $ok;
}
sub _add_session {
    my $doc_id = shift;
    my $code = shift;
    foreach($doc_id, $code){
        s/\r//g;
        s/\n//g;
        s/\|/&#124;/g;
    }
    open (TEMP, "$session_file") or return("Error opening $session_file for read : ".$!);
        if ($os == 0) {flock (TEMP, 2);}
        my @index = <TEMP>;
        if ($os == 0) {flock (TEMP, 8);}
    close (TEMP);
    open (OUTPUT, ">$session_file") or return("Error opening $session_file for write : ".$!);
        my $a=time;
        if ($os == 0) {flock (TEMP, 2);}
        for (my $i = 0; $i < @index; $i++) {
            $index[$i] =~s/\n//g;
            next unless ($index[$i]);
            my ($docid, $pass, $IP, $heure, @autres) = split (/\|/, $index[$i]);
            next if ($a > ($heure + $ttl * 60));
            print OUTPUT "$docid|$pass|$IP|$heure||\n";
        }
        print OUTPUT "$doc_id|$code|$ENV{REMOTE_ADDR}|" . $a . "||\n";
        if ($os == 0) {flock (TEMP, 8);}
    close (OUTPUT);
    $doc_id=~s/\//\./g;
    my $cookie = new CGI::Cookie(-name=>$doc_id, -value=> $code );
    print "Set-Cookie: ",$cookie->as_string,"\n";
    0;
}
sub _end_session {
    my $doc_id = shift;
    
    my %cookies = fetch CGI::Cookie;
    my $docid=$doc_id; $docid=~s/\//\./g;
    return("Unable to remove session : Undefined sid") if !defined $cookies{$docid}->value;
    my $code = $cookies{$docid}->value if defined $cookies{$docid}->value;
    
    open (TEMP, "$session_file") or return("Error opening $session_file for read : ".$!);
        if ($os == 0) {flock (TEMP, 2);}
        my @index = <TEMP>;
        if ($os == 0) {flock (TEMP, 8);}
    close (TEMP);
    open (OUTPUT, ">$session_file") or return("Error opening $session_file for write : ".$!);
        my $a=time;
        if ($os == 0) {flock (TEMP, 2);}
        for (my $i = 0; $i < @index; $i++) {
            $index[$i] =~s/\n//g;
            next unless ($index[$i]);
            my ($docid, $pass, $IP, $heure, @autres) = split (/\|/, $index[$i]);
            next if ($a > ($heure + $ttl * 60));
            next if $docid eq $doc_id && $pass eq $code;
            print OUTPUT "$docid|$pass|$IP|$heure||\n";
        }
        if ($os == 0) {flock (TEMP, 8);}
    close (OUTPUT);
    $doc_id=~s/\//\./g;
    my $cookie = new CGI::Cookie(-name=>$doc_id, -value=> '' );
    print "Set-Cookie: ",$cookie->as_string,"\n";
    0;
}
sub _is_res_ok {
    my $res=shift;
    my($h, $c, $a)=split(/\n\n/, $res); $c=~s/\n//g; 
    if($res && $res!~/NOK/ && $res!~/ERR/ && $res!~/error/i && $c=~/OK/) {
        _set_error('Allopass Recall OK');
        return(1);
    }
    if ($c =~/NOK/) {
        _set_error("Allopass.com says : This code is invalid")
    } elsif ($c =~/ERR/) {
        _set_error("Allopass.com says : Invalid document id")
    } else {
        $res=~s/\n/ /g;$res=~s/\r/ /g;
        _set_error("Invalid Allopass.com response code : $res")
    }
    0;
}
sub _get_new_uid {
    my $id;
    $id=crypt(rand(99999999999),'firstpass');
    $id=crypt(rand(99999999999),'layer 2').$id;
    $id=crypt(rand(99999999999),'final !').$id;
    $id=~s/\|/\-/g;
    $id=~s/\//\-/g;
    $id=~s/\\/\-/g;
    $id;
}
sub _set_error {
    $error=shift;
}

=head1 AUTHOR

Bernard Nauwelaerts <bpn@it-development.be>

=head1 LICENSE

GPL/Artistic.  Enjoy !
See COPYING for further informations on the GPL.

=cut
1;
