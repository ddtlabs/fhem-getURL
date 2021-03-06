# $Id$
package main;

use strict;
use warnings;
use HttpUtils;
use DevIo;
use Data::Dumper;

sub CommandGetURL($@);
sub getURL_parse_JSON__expand($$;$$);

my $gu_opts = {
  '--define'          => { noParam => 1, cat => "device/reading" },
  '--force'           => { noParam => 1, cat => "device/reading" },
  '--status'          => { noParam => 1, cat => "device/reading" },
  '--save'            => { noParam => 1, cat => "device/reading" },
  '--debug'           => { noParam => 1, cat => "logging" },
  '--loglevel'        => { noParam => 0, cat => "logging" },
  '--hideurl'         => { noParam => 1, cat => "logging" },
  '--capture'         => { noParam => 0, cat => "adopt response" },
  '--json'            => { noParam => 1, cat => "adopt response" },
  '--stripHtml'       => { noParam => 1, cat => "adopt response" },
  '--substitute'      => { noParam => 0, cat => "adopt response" },
  '--userFn'          => { noParam => 0, cat => "adopt response" },
  '--userExitFn'      => { noParam => 0, cat => "adopt response" },
  '--data'            => { noParam => 0, cat => "post data" },
  '--data-file'       => { noParam => 0, cat => "post data" },
  '--form_'           => { noParam => 0, cat => "post data" },
  'header'            => { noParam => 0, cat => "post data" },
  '--method'          => { noParam => 0, cat => "http" },
  '--httpversion'     => { noParam => 0, cat => "http" },
  '--noshutdown'      => { noParam => 1, cat => "http" },
  '--ignoreredirects' => { noParam => 1, cat => "http" },
  '--digest'          => { noParam => 1, cat => "http" },
  '--SSL_'            => { noParam => 0, cat => "http" },
  '--timeout'         => { noParam => 0, cat => "http/telnet" },
# todo: commandref
  '--user'            => { noParam => 0, cat => "telnet" },
  '--pass'            => { noParam => 0, cat => "telnet" },
  '--prompt'          => { noParam => 0, cat => "telnet" },
  '--uprompt'         => { noParam => 0, cat => "telnet" },
  '--pprompt'         => { noParam => 0, cat => "telnet" },
  '--init'            => { noParam => 1, cat => "telnet" },
};

my %gu_json;                 # result of json_decode
my @gu_cmdref;               # cached cmdref

my $gu_http_timeout   = 5;    # default http timeout
my $gu_telnet_timeout = 0.5;  # default http timeout

my $gu_debugStrLen    = 53;   # cut debug log reading value length
my $gu_helpOptsRows   = 3;    # options help: no of rows
my $gu_helpOptsWidth  = 20;   # options help: width of rows
my $gu_crMaxAge       = 1800; # drop @gu_cmdref after x seconds of inactivity


# ------------------------------------------------------------------------------
sub CommandGetURL($@)
{
  my ($hash, $cmdline) = @_;
  my ($err, $url, $sm, $opts, $tcmds, $d, $r);
  
  # some defaults
  #$opts->{loglevel} = 4;

  ($err, $url, $sm, $opts, $tcmds) = getURL_parseParams($cmdline);
  return $err if $err;

  if ($url =~  m/^(help|\?)$/) {
    my $help = getURL_help($hash, $cmdline);
    return $help;
  }

  # log whole cmdline if --debug, hide url if requested
  if ($opts->{"--debug"} && $opts->{"--debug"} =~ m/^[12]$/) {
    my $logCmd = $opts->{"--hideurl"} ? $cmdline =~ s/$url/<hidden-url>/r : $cmdline;
    Log 1, "getURL $logCmd" ;
  }

  # break up setMagic
  ($err, $opts) = getURL_parseSetMagic($sm, $opts);
  return $err if $err;
  
  # do the job
  if ($url =~ m'^https?://' || $url !~ m'://') {
    getURL_http_req($hash, $opts);
  }
  elsif ($url =~ m'^telnet://') {
    getURL_telnet_req($hash, $opts, $tcmds);
  }
  else {
    Log 2, "getURL Unsupported URL: $url";
    return "getURL: Unsupported URL: $url";
  }

}


# ------------------------------------------------------------------------------
sub getURL_Initialize($$)
{
  my ($hash) = @_;

  $cmds{geturl} = { 
    Fn  => "CommandGetURL", 
    Hlp => "Usage: getURL <url> [<device>:<reading>] <options>\n"
  };
  
  $hash->{ReadFn}   = 'getURL_telnet_read';
  $hash->{ReadyFn}  = 'getURL_telnet_ready';
}


# ------------------------------------------------------------------------------
sub getURL_parseParams($) {
  my ($cmdline) = @_;
  my ($a, $opts) = parseParams($cmdline);
  my ($err, $info);

  my ($url, $sm) = split(" ", $cmdline);         # non hash ref params
  return getURL_help(undef, "") if !$url;    # at least 1 argument is needed.

  return (undef, $url, undef, undef) if $url =~ m/^(help|\?)$/;

  shift $a;                                              # remove url
  shift $a if defined $a->[0] && $a->[0] =~ m/^\[.*\]/;  # remove sm if given
  
  # check hash part of parseParams()
  foreach my $opt ( keys %{ $opts } ) {
    # respect special cases --form_xx --SSL_
    if ($opt =~ m/^(--form_|--SSL_).*$/) {
      if ($opt =~ m/^(--form_|--SSL_)$/) {
        $err  = "getURL argument '$opt' is not valid. You have to expand the key.";
        $info = "getURL help $opt";
        last;
      }
      elsif ($opts->{$opt} eq "") {
        $err  = "getURL Value for argument '$opt' missing.";
        $info = "getURL help $1";
        last;
      }
    }
    # check unknown arguments
    elsif (!defined $gu_opts->{$opt} && $opt =~ m/^--/) {
      $err  = "getURL Unknown argument '$opt'.";
      $info = "getURL help";
      last;
    }
    # if argument eq "--arg="
    elsif ($opts->{$opt} eq "") {
      if (defined $gu_opts->{$opt} && $gu_opts->{$opt}{noParam} == 1) {
        $opts->{$opt} = 1;
      }
      # noParam == 0, a value must be specified
      else {
        $err  = "getURL Value for argument '$opt' missing.";
        $info = "getURL help $opt";
        last;
      }
    }
  }

  # add array part of pasereParams() to hash reference
  if(!$err) {
    foreach my $arg (@{ $a }) {
      # respect special cases --form_xx --SSL_
      if ($arg =~ m/^(--form_|--SSL_)$/) {   
        $err  = "getURL argument '$arg' needs to be expanded and a value is required.";
        $info = "getURL help $1";
        last;
      }
      # respect special cases --form_xx --SSL_
      elsif ( $arg =~ m/^(--form_|--SSL_).+/) {
        $err  = "getURL argument '$arg' needs a value. ";
        $info = "getURL help $1";
        last;
      }
      elsif (defined $gu_opts->{$arg}) {
        if ($gu_opts->{"$arg"}{noParam} == 1) {
          $opts->{$arg} = 1;
        }
        else {
          $err = "getURL Value is missing for argument '$arg'.";
          $info = "getURL help $arg";
          last;
        }
      }
      elsif ($cmdline !~ m'^telnet://' || ($cmdline =~ m'^telnet://' && $arg =~ m/^--/) ) {
        $err = "getURL Argument '$arg' is not valid.";
        $info = "getURL help";
        last;
      }
    }
  }

  if ($err) {
    $err .= " Use '$info' for more information.";
    Log 2, $err if $err;
    return ($err, undef, undef, undef);
  }

  # add cmd and url to $opts reference
  $opts->{'--cmdline'} = $cmdline;
  $opts->{'--url'} = $url;

  my @tcmd; #remove arguments with no value (eg. --status)
  foreach (@{$a}) {
    push @tcmd, $_ if $_ !~ m/^--/;
  }

  return ($err, $url, $sm, $opts, \@tcmd); # $a are remaining cmdline arguments (other then !key=value)
}


# ------------------------------------------------------------------------------
sub getURL_parseSetMagic($$)
{
  my ($sm, $opts) = @_;
  my ($d, $r, $err, $msg);

  my $define = $opts->{'--define'};
  my $save   = $opts->{'--save'};

  return (undef, $opts) if !$sm || $sm !~ m/^\[.*\]$/;

  if ($sm && $sm =~ m/^\[(.+):([A-Za-z\d_\.\-\/]+)\]$/) {
    $d = $1;
    $r = $2;
  
    if(!IsDevice($d) && defined $define) {
      $err = CommandDefine(undef, "$d dummy");
      $err = "getURL Error while define dummy '$d': $err" if $err;
      $msg = "getURL Dummy device '$d' successfully defined." if !$err;
      if ($save) {
        CommandSave(undef,undef);
        $msg .= " Structural changes saved.";
      }
      Log 2, $msg;
    }
    elsif (!IsDevice($d)) {
      $err = "getURL Device '$d' do not exist. Use option --define to create a dummy device.";
    }
  }
  elsif ($sm) {
    $err = "getURL Malformed device/reading combination '$sm', use [device:reading], allowed characters are: A-Za-z0-9._";
  }

  $opts->{'--device'}  = $d;
  $opts->{'--reading'} = $r;

  Log 2, $err if $err;
  return ($err, $opts);
}


# ------------------------------------------------------------------------------
sub getURL_telnet_opts2Params($$) {
  my ($hash, $opts) = @_;
  my ($param, $err);

  foreach (keys %{$opts}) {
    # Arguments for HttpUtils -> move to $param hash reference
    if (m/^--/) {
      $param->{substr($_,2)} = $opts->{$_};
      delete $opts->{$_};
    }
  }

  $param->{url} =~ m'^telnet://(?:.*:.*\@)?(.*):(\d+)';
  $err = "getURL wrong telnet URL format." if !$1 && !$2;
  $param->{addr} = "$1:$2" if $1 && $2;

  $param->{user} = $1 if $param->{url} =~ m'^telnet://(.*):.*\@.*:\d+'
                      && !defined $param->{user};
  $param->{pass} = $1 if $param->{url} =~ m'^telnet://.*:(.*)\@.*:\d+'
                      && !defined $param->{pass};
                      
  $param->{callback} = \&getURL_parse;
  $param->{protocol} = "telnet";
  $param->{prompt}   = "#" if !defined $param->{prompt};
  $param->{uprompt}  = "^username:" if !defined $param->{uprompt};
  $param->{pprompt}  = "^password:" if !defined $param->{pprompt};

  return ($err, $param);
}


# ------------------------------------------------------------------------------
sub getURL_telnet_opts2Params_test($$) {
  my ($hash, $opts) = @_;
  my ($param, $err);

  foreach (keys %{$opts}) {
    # Arguments for HttpUtils -> move to $param hash reference
    if (m/^--/) {
      $param->{substr($_,2)} = $opts->{$_};
      delete $opts->{$_};
    }
  }

# to be done... all other formats than ip:port
#  $param->{url} =~ s'^telnet://'';

  my $url = $param->{url};

  my ($user, $pass, $addr);
  if ($url =~ m'^telnet://(.+):(.+)\@(.+)') {
    $user = $1;
    $pass = $2;
    $addr = $3;
  }
  elsif ($url =~ m'^telnet://(.+)') {
    $addr = $1
  }
    
  $url = "$url:23" if $url !~ m/:([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$/;
  
  # extract address:port
  $url =~ m'^telnet://(?:.+:.+\@)?(.+):(\d+)';
  $err = "getURL wrong telnet URL format." if !$1 || !$2;
  $param->{addr} = "$1:$2" if $1 && $2;

  $param->{url} = $url;
    
    
  $param->{user} = $1 if $param->{url} =~ m'^telnet://(.*):.*\@.*:\d+'
                      && !defined $param->{user};
  $param->{pass} = $1 if $param->{url} =~ m'^telnet://.*:(.*)\@.*:\d+'
                      && !defined $param->{pass};
                      
  $param->{callback} = \&getURL_parse;
  $param->{protocol} = "telnet";
  $param->{prompt}   = "#" if !defined $param->{prompt};
  $param->{uprompt}  = "^(username|login):" if !defined $param->{uprompt};
  $param->{pprompt}  = "^password:" if !defined $param->{pprompt};

  return ($err, $param);
}


# ------------------------------------------------------------------------------
sub getURL_telnet_req($$$) {
  my ($hash,$opts,$tcmds) = @_;
  my ($err, $args);

  # convert $opts to $args (format used by telnet)
  ($err, $args) = getURL_telnet_opts2Params($hash, $opts);
  if ($err) {
    Log 2, $err;
    return $err;
  }

  # if there are no cmds to be executed
  if (!@{$tcmds}) { 
    Log 2, "getURL $args->{cmdline}" if !defined $args->{debug};
    $err = "getURL error: no telnet commands specified";
    Log 2, $err;
    return $err;
  }

  # split telnet commands at ; (must be escaped: ;;)
  my @tcmds = split(";",join(" ",@{$tcmds}));
  # remove leading white spaces
  foreach (0..$#tcmds) { $tcmds[$_] =~ s/^\s+// }
  # add telnet cmds ref to $args, processed in readFn
  $args->{cmd} = \@tcmds;
  
  # use a temp device for each dest IP, cmds are queued to this device
  my $type = "getURL";
  my $addr = $args->{addr};
#  my $ioname = "getURL" . "_". $addr =~ s/:/_/gr;
#  $ioname =~ s/[^-_a-zA-Z0-9\.]//g;
  my $ioname = "getURL" . "_". $addr;
  $ioname = makeDeviceName($ioname);
  my $iohash;
  
  # already defined (telnet session running) -> queue cmds to device
  if (defined $defs{$ioname}) {
    $iohash = $defs{$ioname};
    # queue cmd(s), first readFn call shifts it to $hash->{current} for further processing
    push @{ $iohash->{queue} }, $args;
  }
  # no getURL device available for dest IP. Create it.
  else {
    $iohash = getURL_telnet_mkIoDev($ioname, $type, $addr);
     # fail-save
    if (ref($iohash) eq "HASH") {
      # queue cmd(s), first readFn call shifts it to $hash->{current} for further processing
      push @{ $iohash->{queue} }, $args;
      # Parameters for DevIo_OpenDev
      $iohash->{TIMEOUT} = defined $args->{timeout} ? $args->{timeout} : $gu_telnet_timeout;
      $iohash->{devioLoglevel} = defined $args->{debug} && $args->{debug} eq "2" ? 1 : 4;
      #
      $iohash->{stage} = "none";
      $err = DevIo_OpenDev($iohash, 0, undef);
      if (!$err) {
        my $init = defined $args->{init} ? defined $args->{init} : "";
        DevIo_SimpleWrite($hash, $init, 2) if defined $args->{init};
      }
      else { $err = "getURL error opening IO device $ioname: $err" }
    }
    else { $err = "getURL error creating temporary IO device $ioname" }
  }
  
  return $err;
}


# ------------------------------------------------------------------------------
# ReadyFn
sub getURL_telnet_ready(@) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $debug = @{$hash->{queue}}[0]->{debug};
  my $stage = $hash->{stage};

  Log 1, "$name Telnet request abort, timout reached (stage: $stage)."
    if $stage ne "exit" && $debug;

  # remove first cmd from queue, we are here because no connect could be done.
  shift @{ $hash->{queue} };

  # close or try again if there are pending telnet cmds for this host
  getURL_telnet_close($hash);

return 0;
}


# ------------------------------------------------------------------------------
# readFn
sub getURL_telnet_read(@) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
#  Debug "getURL_telnet_read called";
    
  # avoid reading from closed device
  return undef unless($hash->{STATE} eq "opened");
  
  my $buf = DevIo_SimpleRead($hash);
  return '' if(!defined($buf));

  # move next cmd incl. params for further processing
  if (!defined $hash->{current}) {
    $hash->{current} = shift @{ $hash->{queue} } ;
    # reset stage flag
    $hash->{stage} = "";
    #fail-save, will be deleted in closeFn if everything worked fine
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{TIMEOUT}+1, sub(){getURL_telnet_close($hash)}, $hash);
  }

  $hash->{PARTIAL} .= $buf;
  $buf = $hash->{PARTIAL};
  
  my $debug   = $hash->{current}{debug};
  my $prompt  = $hash->{current}{prompt};
  my $user    = $hash->{current}{user};
  my $pass    = $hash->{current}{pass};
  my $logPass = $hash->{current}{hideurl} ? "*" x length($pass) : $pass;
  my $uprompt = $hash->{current}{uprompt};
  my $pprompt = $hash->{current}{pprompt};

  if ($hash->{stage} eq "exit") {
    if ($buf && $buf =~ m/exit/is) {
      getURL_telnet_close($hash);
    }
  }
  elsif ($buf =~ m/^$uprompt\s*$/mi) {
    Log 1, "$name found login/username prompt '$uprompt', send username '$user'" if $debug;
    $hash->{stage} = "username";
    $hash->{PARTIAL} = "";
    DevIo_SimpleWrite($hash, $user, 2, 1);;
  }
  elsif ($buf =~ m/^$pprompt\s*$/mi) {
    Log 1, "$name found password prompt '$pprompt', send password '$logPass'" if $debug;
    $hash->{stage} = "password";
    $hash->{PARTIAL} = "";
    DevIo_SimpleWrite($hash, $pass, 2, 1);
  }
  elsif ($buf =~ m/^$prompt\s*$/mi && $hash->{stage} ne "prompt") {
    Log 1, "$name found telnet prompt '$prompt'" if $debug;
    if (!defined $hash->{helper}{req}{cmdSend}) {
      $hash->{helper}{req}{cmdSend} = 1;
    }
    else {
      # $buf is complete, new prompt received -> send to callbackFn
      my $param = $hash->{current};
      $param->{HASH} = $hash;
      $param->{callback}($param, "", $buf);
      $hash->{PARTIAL} = "";
    }
    my $cmd = shift $hash->{current}{cmd};
    if ($cmd) {
      Log 1, "$name send cmd '$cmd'" if $debug;
      DevIo_SimpleWrite($hash, $cmd, 2, 1);
    }
    else {
      Log 1, "$name last cmd was send." if $debug;
      DevIo_SimpleWrite($hash, "", 2, 1);
      $hash->{stage} = "prompt"; # if !$hash->{helper}{req}{cmds};
    }
  }
  elsif ($buf =~ m/$hash->{current}{prompt}/i && $hash->{stage} eq "prompt") {
    Log 1, "$name send exit command." if $debug;
    $hash->{stage} = "exit";
    DevIo_SimpleWrite($hash, "exit", 2, 1);
  }
}


# ------------------------------------------------------------------------------
sub getURL_telnet_close($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $debug = $hash->{current}{debug};
  Log 1, "$name clossing session" if $debug;
  
  my $addr = $hash->{DeviceName} ? $hash->{DeviceName} : "???";

  DevIo_CloseDev($hash);
  delete $hash->{helper}{req};
  delete $hash->{current};
  $hash->{stage} = "closed";
  $hash->{PARTIAL} = "";
  RemoveInternalTimer($hash);
  delete $hash->{NEXT_OPEN};
  
  if ( @{ $hash->{queue} } ) {
    Log 1, "$name there are still " . @{$hash->{queue}}
         . " commands in the queue, work off now..." if $debug && @{$hash->{queue}};
    # Params for next cmd used by DevIo_OpenDev/DevIo_SimpleWrite
    my $nextCmd = (@{$hash->{queue}})[0];
    my $init = defined $nextCmd->{init} ? $nextCmd->{init} : "";
    $hash->{TIMEOUT} = defined $nextCmd->{timeout} ? $nextCmd->{timeout} : $gu_telnet_timeout;
    $hash->{devioLoglevel} = defined $nextCmd->{debug} && $nextCmd->{debug} eq "2" ? 1 : 4;
    my $err = DevIo_OpenDev($hash, 0, undef);
    if ($err) {
      my $ret = "$name error opening device $addr: $err";
      Log 2, $ret if $debug;
      return $ret;
    }
    else {
      DevIo_SimpleWrite($hash, $init, 2) if defined $nextCmd->{init};
    }
  }
  else {
    Log 1, "$name deleting temporary device $name" if $debug;
    delete $attr{$name};
    delete $defs{$name};
  }
}


# ------------------------------------------------------------------------------
sub getURL_telnet_mkIoDev($$$)
{
  my ($name,$type,$addr) = @_;

  my %iohash;
  $iohash{NR}         = $devcount++;
  $iohash{NAME}       = $name;
  $iohash{TYPE}       = $type;
  $iohash{SNAME}      = "getURL";
  $iohash{TEMPORARY}  = 1;
  $iohash{DeviceName} = $addr;
  $iohash{PARTIAL}    = "";
  $attr{$name}{room}  = "hidden";
  $defs{$name}        = \%iohash;

  return \%iohash;
}  


# ------------------------------------------------------------------------------
sub getURL_http_opts2Params($$) {
  my ($hash, $opts) = @_;
  my ($param, $err);

  # some defaults for NonblockingGet
  $param->{hash}     = $hash; #passthrough
  $param->{timeout}  = $gu_http_timeout;
  $param->{callback} = \&getURL_parse;
  $param->{protocol} = "http";

  my @header;
  foreach (keys %{$opts}) {
    # Arguments for HttpUtils -> move to $param hash reference
    if (m/^--/) {
      if (m/^--form_.+$/) {
        $param->{data} .= "&" if( $param->{data} );
        $param->{data} .= substr($_,7)."=".urlEncode($opts->{$_});
      }
      elsif (m/^--SSL_.+$/) {
        $param->{sslargs}{substr($_,2)} = $opts->{$_};
      }
      # args like: --debug, --stripHtml. capture
      # but also --cmdline, --url, --reading, --device
      else {
        $param->{substr($_,2)} = $opts->{$_};
      }
      # remove HttpUtils Params (--.*) from parseParams $opts
      delete $opts->{$_};
    }
    # Arguments without leading -- become part of the header
    else {
      push @header, $_.": ".$opts->{$_};
    }
    $param->{header} = join("\r\n",@header);
  }

  # option --data-file
  if (defined $param->{'data-file'}) {
    my $mpath = $attr{global}{modpath}."/".$param->{'data-file'};
    ($err, my @fdata) = FileRead({FileName => $mpath, ForceType => 'file'});
    if($err) {
      Log 2, "getURL $err";
      return ("getURL $err", undef);
    }
    $param->{data} .= join("\n", @fdata);  #todo: encode?
  }  

  # expand urls to full spelling: "http://boobar/"
  $param->{url} = "http://".$param->{url} if($param->{url} !~ m'https?://');
  # add trailing slash (req. by HttpUtils)
  my $slashCount = () = $param->{url} =~ m'/'g;
  $param->{url} .= "/" if $slashCount <= 2 ;
  
  return ($err, $param);
}


# ------------------------------------------------------------------------------
sub getURL_http_req($$)
{
  my ($hash, $opts) = @_;  # parseParams is used
  my ($err, $param);
  
  # convert $opts to $params (format used by httpUtils)
  ($err, $param) = getURL_http_opts2Params($hash, $opts);
  return $err if $err;
  return undef if !defined $param;

  Log 1, "getURL: request data:\n$param->{data}" 
    if ($param->{data} && $param->{debug});
  $param->{loglevel} = 1 
    if (!$param->{loglevel} && $param->{debug} && $param->{debug} == 2);

  HttpUtils_NonblockingGet($param);
}


# ------------------------------------------------------------------------------
sub getURL_parse($$$)
{
  my ($param, $err, $data) = @_;
  my $hash  = $param->{hash};
  my $name  = $hash->{NAME};
  my $debug = $param->{debug};
  my $d     = $param->{device};
  my $r     = $param->{reading};
  my $cmdline = $param->{cmdline};
  my $userExitFn = $param->{'userExitFn'};
  
  if($err ne "") {
    $err = "ERROR: ".$err;
    Log 2, "getURL $param->{cmdline}" if !$debug;
    Log 2, "getURL $err";
  }

  Log 1, "getURL received data:\n". ($data ? $data : "<undef>") if $debug && $debug eq "2";
  chomp $data;

  if ($d && $r) {
    $data = undef if $param->{code} && $param->{code} =~ m/^[459]\d\d$/ && !$param->{force};
    if (defined $data) {
      $data = getURL_parse_stripHtml($data,$debug) if $param->{stripHtml};
      if ((defined $param->{code} && $param->{code} !~ m/^[459]\d\d$/)
         || (defined $param->{protocol} && $param->{protocol} eq "telnet")) {
        if ($param->{substitute}) {
          $data = getURL_parse_substitute($data, $param->{substitute}, $debug);
        }
        if ($param->{capture}) {
          # $data becomes a hash referece
          $data = getURL_parse_capture($data, $param->{capture}, $debug);
        }
        elsif ($param->{json}) {
          # $data becomes a hash referece
          $data = getURL_parse_JSON($data, $param->{findJSON} ,$debug);
        }
        if ($param->{userFn}) {
          $data = getURL_parse_userFn($data, $param->{userFn}, $debug);
        }
      } # $param->{code} !~ m/^[459]
    } # defined $data
  } # $d && $r

  if ($param->{httpheader} && $param->{status}) {
    $err = (split("\n",$param->{httpheader}))[0];    #eg. HTTP/1.1 404 not found
    $err =~ s'^HTTP/\d(\.\d)?\s+'' if $err;          #eg. 404 not found
  }
  elsif (!$param->{status}) {
    $err = undef;  # no status reading will be written
  }

  # break out of notify loop detection.
  if ( $d && $r && ($data || $err) ) {
    InternalTimer(
      gettimeofday(),
      sub(){ getURL_updateReadings($defs{$d}, $r, $data, $cmdline, $userExitFn, $err, $debug) },
      $hash
    );
  }
}


# ------------------------------------------------------------------------------
sub getURL_parse_stripHtml($;$)
{
  my ($data, $debug) = @_;
  
  if (getURL_checkPM("HTML::Strip")) {
    my $hs = HTML::Strip->new();
    $data = $hs->parse($data);
  }
  else {
    Log 1, "getURL stripHtml: Fallback to regexp mode. Perl module HTML::Strip not installed" if $debug;
    $data =~ s/<(?:[^>'"]*|(['"]).*?\1)*>//gs; # html
    Log 1, "getURL stripHtml: $data" if $debug;
  }
  $data =~ s/(\s{2,}|\r|\n)/ /g; # replace \r\n with " "
  $data =~ s/(^\s+|\s+$)//g;     # remove whitespaces
  return $data;
}


# ------------------------------------------------------------------------------
sub getURL_parse_substitute($$;$)
{
  my ($data, $re, $debug) = @_;
  my ($re2, $re3) = split(" ",$re,2);
  my $isPerl; 

  if (!defined $re2 || !defined $re3) {
    Log 2,"getURL ERROR: Invalid regexp: $re";
    return undef;
  }
  if ($re2 =~ m/^\*/) {
    Log 2,"getURL ERROR: Regexp must not start with a *, ignoring regexp: $re2";
    return undef;
  }
  if($re3 =~ m/^{.*}/) {
    $isPerl = 1;
    my %specials= ();
    my $err = perlSyntaxCheck($re3, %specials);
    if($err) {
      Log 2, "getURL ERROR: Invalid perl statement $re3: $err";
      return undef;
    }
  }

  if ($isPerl) {
    eval "\$data =~ s/$re2/$re3/mge";
  }
  else {
    eval "\$data =~ s/$re2/$re3/mg";
  }
  if ($@) {
    Log 2, "getURL WARNING: Invalid regexp: $re2\n$@";
    return undef;
  }
  Log 1, "getURL substitute: " . ($data ? "\n".$data : "<undef>") if $debug;

  return $data;
}


# ------------------------------------------------------------------------------
sub getURL_parse_capture($$$)
{
  my ($data, $re, $debug) = @_;
  return undef if !defined $re || $re eq "";
  
  if ( $re =~ m/^\*/ ) {
    Log 2,"getURL regexp must not start with a *, ignoring regexp: $re";
    return undef;
  }

  eval { $data =~ /$re/ }; 
  if ($@) {
    Log 2, "getURL WARNING: invalid regexp: $re - $@";
    return undef;
  } 

  # exec another match wo/ eval due to further easy processing of %-, @#, etc
  my $match = () = $data =~ m/$re/;
  if ($match) { # is required if last regexp do not match
    my %capture;
    if (%-) { # named captures: http://perldoc.perl.org/perlvar.html#%25-
      foreach my $bufname (sort keys %-) {
        my $ary = $-{$bufname};
        foreach my $idx (0..$#$ary) {
          $capture{$bufname}{$idx} = (defined($ary->[$idx]) ? $ary->[$idx] : undef);
        }
      }
    }
    elsif (@+) { # unnamed captures: http://perldoc.perl.org/perlvar.html#%40%2b
      for (my $i = 1; $i <= $#+; $i++) {
        $capture{$i} = substr($data, $-[$i], $+[$i] - $-[$i]);
      }
    }
    Log 1, "getURL capture:\n". Dumper \%capture if $debug;
    return \%capture;
  }
  else { # match
    Log 2, "getURL no matching capture group for regexp: $re";
  }

  return undef;
}


# ------------------------------------------------------------------------------
sub getURL_parse_JSON($$;$) {
  my ($dvalue, $findJSON, $debug) = @_;
  $findJSON = 1 if !defined $findJSON;

  # global $data hash for user data is used.
  if (getURL_checkPM("JSON")) {
    $dvalue = $findJSON ? getURL_parse_JSON__find($dvalue, $debug) : $dvalue;
    my $h;
    eval { $h = decode_json($dvalue); 1; };
    if ( $@ ) {
      Log 2, "getURL decodeJSON: Malformed JSON: " . ($dvalue ? "\n".$dvalue : "<undef>");
      Log 2, "getURL decodeJSON: $@" if $dvalue;
      return undef;
    }
    else  {
      Log 1, "getURL decodeJSON:\n" . Dumper $h if $debug;
      my $exp = getURL_parse_JSON__expand("",$h);
      Log 1, "getURL expandJSON:\n" . Dumper $exp if $debug;
      return $exp;
    }
  }
  else {
    Log 2, "getURL decodeJSON: WARNING: Perl module JSON missing. Install it or use capture groups.";
    return undef;
  }
}


# ------------------------------------------------------------------------------
sub getURL_parse_JSON__find($;$) {
  my ($data, $debug) = @_;
  my $json;
  # taken from: stackoverflow.com/questions/21994677/find-json-strings-in-a-string
  my $pattern = '\{(?:[^{}]|(?R))*\}';
  $data =~ m/($pattern)/x;
  if ($1) {
    $data = $1;
    $data =~ s/\R//g; 
    Log 1, "getURL findJSON:\n".$data if $debug;
    return $data;
  }

  Log 1, "getURL findJSON: <no JSON found>" if $debug;
  return undef ;
}


# ------------------------------------------------------------------------------
sub getURL_parse_JSON__expand($$;$$) {
  my ($sPrefix,$ref,$prefix,$suffix) = @_;
  $prefix = "" if( !$prefix );
  $suffix = "" if( !$suffix );
  $suffix = "_$suffix" if( $suffix );

  if( ref( $ref ) eq "ARRAY" ) {
    while( my ($key,$value) = each @{ $ref } ) {
      getURL_parse_JSON__expand($sPrefix, $value, $prefix.sprintf("%02i",$key+1)."_");
    }
  }
  elsif( ref( $ref ) eq "HASH" ) {
    while( my ($key,$value) = each %{ $ref } ) {
      if( ref( $value ) ) {
        getURL_parse_JSON__expand($sPrefix, $value, $prefix.$key.$suffix."_");
      }
      else {
        my $reading = $sPrefix.$prefix.$key.$suffix;
        $gu_json{$reading} = $value;
      }
    }
  }

  return \%gu_json;
}


# ------------------------------------------------------------------------------
#getURL https://xxx.ddtlab.de [hd:testx1] --userFn={getURL_testFn($DATA, 10)}
sub getURL_parse_userFn($$;$)
{
  my ($data, $userFn, $debug) = @_;
  my $DATA = $data;
  
  my $ret = eval("$userFn");
  if ($@) {
    Log 1, "getURL Eval userFn: $userFn" if $debug;
    Log 2, "getURL userFn ERROR: ".$@;
  } 
  else {
    Log 1, "getURL userFn: " . ($ret ? "\n".$ret : "<undef>") if $debug;
    return $ret;
  }

  return undef;
}


# ------------------------------------------------------------------------------
sub getURL_updateReadings($$$$$$;$)
{
  my ($dhash, $dreading, $data, $cmdline, $userExitFn, $err, $debug) = @_;
  my $dname = $dhash->{NAME};
  readingsBeginUpdate($dhash);

  if(defined($data)) {
    # remove illegal letters from reading name
#    $dreading =~ s/[^A-Za-z\d_\.\-\/]/_/g;
    $dreading = makeReadingName($dreading);

    if( ref($data) eq 'HASH' ) {
      my $s = "_";
      foreach my $key ( sort keys %{$data}) {
        my $reading = $dreading.$s.$key;

        # named capture groups
        if (ref($data->{$key}) eq "HASH") {
          foreach my $num (keys %{$data->{$key}}) {
            # no numbering of singles values
            my $r = (scalar keys $data->{$key} > 1) ? $reading.$s.$num 
                                                    : $reading;
            if (defined $data->{$key}{$num}) {
              readingsBulkUpdate($dhash, $r, $data->{$key}{$num});
              Log 1, substr("getURL setreading [$dname:$r] \n$data->{$key}{$num}",0,$gu_debugStrLen) if $debug;
            }
            else {
              if ($debug) {
                Log 1, $dhash->{READINGS}{$r} 
                  ? "getURL deletereading [$dname:$r]"
                  : "getURL setreading [$dname:$r] \n'undef' (skipped due to undefined value)";
              }
              CommandDeleteReading( undef, "$dname $r" );
            }
          }
        }

        # unnamed capture groups
        else {
          if ($data->{$key}) {
            Log 1, "getURL setreading $dname \n".$reading." ".$data->{$key} if $debug;
            readingsBulkUpdate($dhash, $reading, $data->{$key});
          }
          else {
            Log 1, "getURL deletereading [$dname:$reading] (due to undefined value)"
              if $debug && $dhash->{READINGS}{$reading};
            CommandDeleteReading( undef, "$dname $reading" );
          }
        }
        
      }
    } # hash ref

    elsif( ref($data) eq 'ARRAY' ) {
      my $i = 1;
      foreach (@$data) {
        readingsBulkUpdate($dhash, $dreading."-$i", $_);
        $i++;
      }
    }

    elsif( ref($data) eq 'SCALAR') {
      Log 1, substr("getURL setreading [$dname:$dreading] \n${ $data }",0,$gu_debugStrLen) if $debug;
      readingsBulkUpdate($dhash, $dreading, ${ $data });
    }
    elsif( ref($data) eq '') {
      Log 1, substr("getURL setreading [$dname:$dreading] \n$data",0,$gu_debugStrLen) if $debug;
      readingsBulkUpdate($dhash, $dreading, $data) if $data;
    }

  } # if defined $data

  # delete reading(s)
  else {
    if (defined $dhash->{READINGS}{$dreading}) {
      Log 1, "getURL deletereading [$dname:$dreading".".*]" if $debug;
      CommandDeleteReading( undef, "$dname $dreading".".*" );
    }
  }

  # add result reading if defined
  Log 1, substr("getURL setreading [$dname:_lastStatus] \n$err",0,$gu_debugStrLen) if $debug && $err && $err ne "";
  readingsBulkUpdate($dhash, $dreading."_lastStatus", $err) if $err && $err ne "";

  readingsEndUpdate($dhash, 1);
  
  if ($userExitFn) {
    getURL_updateReadings_userExitFn($userExitFn, $dname, $dreading, $data, $cmdline, $debug);
  }
}


# ------------------------------------------------------------------------------
sub getURL_updateReadings_userExitFn($$$$$;$) {
  my ($userExitFn, $d, $r, $v, $cmdline, $debug) = @_;
  $debug = "" if !defined $debug;
  
  my %specials = ("%DEVICE" => "$d", "%NAME" => "$d", "%READING" => "$r", "%DATA" => "$v" , "%DEBUG" => "$debug");
  $userExitFn = EvalSpecials($userExitFn, %specials);

  Log 1, "getURL: --userExitFn: exec $userExitFn" if $debug;
  
  my $err = AnalyzeCommandChain(undef,$userExitFn);
  if ($err) {
    Log 2, "getURL $cmdline" if !$debug;
    Log 2, "getURL --userExitFn: exec: $userExitFn" if !$debug;
    Log 2, "getURL --userExitFn: $err";
  }
}


# ------------------------------------------------------------------------------
sub getURL_help($$) {
  my ($hash, $cmdline) = @_;
  my @p = split(" ", $cmdline);
  my $cmd = $p[0];
  my $opt = $p[1];
  my $hat = "General syntax:\n"
          . "getURL <url> [device:reading] <options>   - Request an URL\n"
          . "getUrl help                               - Show this help\n"
          . "getURL help <option>                      - Show help for an option\n"
          . "- Note that [device:reading] and <options> are optional.\n"
          . "- Use 'help getURL' for complete command reference.\n\n";
  my $usg = "\n";
  $usg = "\n".$hat if !defined $opt || !defined $gu_opts->{$opt};
  
  if (!$opt || !$gu_opts->{$opt}) {
    $usg .= "Argument '$opt' is not a valid option.\n\n" if $opt;
    $usg .= "Valid options are:\n";
    my @helpOptsItems = sort keys %{ $gu_opts };
    $usg .= getURL_help__joinRows($gu_helpOptsWidth, $gu_helpOptsRows, @helpOptsItems);
  }

  elsif ($gu_opts->{$opt})
  {
    $usg .= "$opt:\n\n";
    my $optHlp = getURL_help__showTopic($hash, $opt);
    $usg .= $optHlp ? $optHlp : "Topic not found in commandref\n";
  }

  return $usg;
}


# ------------------------------------------------------------------------------
sub getURL_help__joinRows($$@) {
  my ($width, $rows, @strings) = @_;
  my @ret;
  my $i = 1;
  foreach (@strings) {
    push(@ret, ($i<$rows ? "$_ ".' 'x($width - length($_)) : "$_\n"));
    $i++;
    $i=1 if($i > $rows);
  }
  
  return join("",@ret);
}


# ------------------------------------------------------------------------------
sub getURL_help__showTopic($$){
  my ($hash, $label) = @_;
  my ($err, $ret);

  my @c = caller;
  my $mod = $attr{global}{modpath}.substr($c[1],1);
 
 if (!@gu_cmdref) {
    if (!getURL_help__readCmdref($mod)) {
      Log 2, "getURL Could not find $mod.";
      return undef;
    }
  }
  # drop @gu_cmdref after $gu_crMaxAge seconds of inactivity
  RemoveInternalTimer($hash);
  InternalTimer( gettimeofday()+$gu_crMaxAge, sub(){ @gu_cmdref = (); }, $hash );

  my $found;
  foreach my $line (@gu_cmdref) {
    if (!$found) {
      if ($line =~ m/a name="getURL$label"/) {
        $found = 1;
      }
    } #!found
    else {
      last if $line =~ m'<!--topicEnd-->';
      next if !$line;
      $line =~ s'<a href="http.*">''g;
      $ret .= $line =~ s/\s+//r;
      $ret =~ s/<br>/\n/g;
      $ret =~ s'<\/?[\w]+>''g;
      $ret =~ s/&gt;/>/g;
      $ret =~ s/&lt;/</g;
      $ret =~ s/&nbsp;/ /g;
    }
  } #foreach
  return undef if !$ret;

  return $ret ;
}


# ------------------------------------------------------------------------------
sub getURL_help__readCmdref(@)
{
  my ($file) = @_;
  my $err;
  
  if(open(FH, $file)) {
    my $found;
    while( my $line = <FH>)  {   
      if ($found) {
        last if $line =~ m/^\=end html/;
        push(@gu_cmdref, $line);
      }
      else {
        $found = 1 if $line =~ m/^\=begin html/;
        next;
      }
    }
    close(FH);
    chomp(@gu_cmdref);
  }
  else {
    $err = "getURL Can't open $file: $!";  
  }
  return ($err, @gu_cmdref);
}


# ------------------------------------------------------------------------------
sub getURL_checkPM($;$) {
  my ($pm, $debug) = @_;
  return 1 if defined $data{getURL}{$pm} && $data{getURL}{$pm};

  eval "require $pm";
  if($@) {
    if (!defined $data{getURL}{$pm} || $debug) {
      Log 1, "getURL Can't load perl module $pm, please install it.";
      Log 1, "getURL $@";
    }
    $data{getURL}{$pm} = 0;
    return 0;
  }
  $data{getURL}{$pm} = 1;
  return 1;
}

# ------------------------------------------------------------------------------
sub getURL_isHostname($)
{
  return 0 if !defined $_[0];
  return 1 if ($_[0] =~ m/^([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$/)
           && !(getURL_isIPv4($_[0]) || getURL_isIPv6($_[0]));
  return 0;
}

# ------------------------------------------------------------------------------
sub getURL_isFqdn($)
{
  return 0 if !defined $_[0];
  return 1 if ($_[0]
    =~ m/^(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,63}$)$/);
  return 0;
}

# ------------------------------------------------------------------------------
sub getURL_isIPv64($)
{
  return 0 if !defined $_[0];
  return 1 if getURL_isIPv4($_[0]) || getURL_isIPv6($_[0]);
  return 0;
}

# ------------------------------------------------------------------------------
sub getURL_isIPv4($)
{
  return 0 if !defined $_[0];
  return 1 if($_[0]
    =~ m/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/);
  return 0;
}

# ------------------------------------------------------------------------------
sub getURL_isIPv6($)
{
  return 0 if !defined $_[0];
  return 1 if ($_[0]
    =~ m/^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$/);
  return 0;
}



1;

=pod
=item command
=item summary    Request a http url
=item summary_DE Ruft eine http url auf
=begin html

<a name="getURL"></a>
<h3>getURL</h3>
<ul>

  Request a http, https or telnet URL (non-blocking, asynchron)<br>
  Server response can optionally be stored in a reading if you specify [device:reading]<br>
  Optional arguments are described below.<br>
  <br>

  <code>
  <b>getURL httpURL</b><br>
  <b>getURL httpURL [device:reading]</b><br>
  <b>getURL httpURL --option</b><br>
  <b>getURL httpURL [device:reading] --option</b><br>
  <b>getURL telnetURL &lt;cmd&gt;</b><br>
  <b>getURL telnetURL [device:reading] &lt;cmd&gt;</b><br>
  <b>getURL telnetURL --option &lt;cmd&gt;</b><br>
  <b>getURL telnetURL [device:reading] --option &lt;cmd1;;cmd2;;cmd3&gt;</b><br>
  </code>
  <br>

  Arguments:<br>
  <ul>
    <li><b>URL</b>
    <ul>
      URL to request, http:// and https:// URLs are supported at the moment.<br>
      eg. https://example.com/<br>
    </ul>
    </li>
<br>
    <li><b>[device:reading]</b><br>
    <ul>
      Server response will be written into this reading if specified. Can be omitted.<br>
    </ul>
    </li>
<br>    
    <li><b>--option</b><br>
    <ul>
      There are groups of optional arguments to:<br>
        - <a href="#getURL_optModify">adopt server response (readings)</a><br>
        - <a href="#getURL_optData">add data to requests</a><br>
        - <a href="#getURL_optHeader">add HTTP headers</a><br>
        - <a href="#getURL_optConfig">configure server requests</a><br>
        - <a href="#getURL_optSSL">configure SSL/TLS methods</a><br>
        - <a href="#getURL_optDebug">Debug/Log</a><br>
    </ul>
    </li>
<br>
    <li><b>cmd</b><br>
    <ul>
      Telnet command(s). Multiple commands must be splited by: ;;<br>
    </ul>
    </li>
    
  </ul>
  <br>

  Examples:<br>
    <ul>
      <li>
        <code>getURL https://www.example.com</code><br>
      </li>
      <li>
        <code>getURL https://10.2.3.4:8383/ [dev0:result]</code><br>
      </li>
      <li>
        <code>getURL https://www.example.com/ --status --force </code><br>
      </li>
      <li>
        <code>getURL https://www.example.com/ [dev:rXXX] --status --force --define</code><br>
      </li>
      <li>
        <code>getURL https://www.example.com/ [dev:rYYY] --httpversion=1.1 --SSL_version=SSLv23:!SSLv3:!SSLv2</code><br>
      </li>
      <li>
        <code>getURL telnet://www.example.com:23 cmd</code><br>
      </li>
      <li>
        <code>getURL telnet://10.1.2.3:23 cmd1;;cmd2</code><br>
      </li>
      <li>
        <code>getURL telnet://www.example.com:23 cmd1 param1;;cmd2</code><br>
      </li>
      <li>
        <code>getURL telnet://10.1.2.3:23 [dev:reading] --user=admin --pass=xyz -prompt=host# cmd1 param1;; cmd2;; cmd3 param3a param3b</code><br>
      </li>
    </ul>
    <br>

  <br>
  Syntax help and help for options is also available:<br>
  <br>
  <code>
  <b>getURL help</b><br>
  <b>getURL help --option</b><br>
  </code>
<br><br>


  Notes:<br>
    <ul>
    <li>
      getUrl do not return a server response, directly.
      The reason is that it is working non-blocking. A possible response from
      server will be asynchron written into a reading of your choice. If you want
      to further process this value you have to use --userExitFn option or you have
      to define a notify (or DOIF) that triggers on the updated or changed value.
    </li>
    <li>
      Use --debug or --debug=2 argument and have a look at FHEM's log file to
      see requests and responses if something went wrong.
    </li>
    <li>
      An online http(s) request inspect tool can be found
      <a href="https://requestb.in/">here</a> to examine your command line
      arguments if you don't have an own webserver to test with.
    </li>
    <li>
      If a (set magic) device/reading combination is specified and an error
      occured or the returned 
      <a href ="https://en.wikipedia.org/wiki/List_of_HTTP_status_codes">
      HTTP status code</a> comply with 4xx, 5xx or 9xx then the status it is 
      written into a reading with suffix '_lastStatus'. 
      If all response codes (also good once) should be written into this reading
      then option '--status' must be applied. See below.
    </li>
    </ul><br>
<br>


<li>
  <a name="getURL_options"><u>Optional arguments to adopt command behaviour:</u></a><br>
  <br>

    <a name="getURL--define">--define</a>
    <ul>
      Define destination device for reading(s) if not already exist.<br>
      A dummy device will be defined/created if there is no accordingly device.<br>
      Allowed values: none<br>
      Default: disabled<br><br>
      
      Examples:<br>
      <code>
      # device 'dev' will be defined if not already defined to be able to write readings to.<br>
      getURL https://www.example.com/getJSON [dev:reading] --define<br>
      </code>
    </ul>
    <!--topicEnd-->

    <a name="getURL--save">--save</a>
    <ul>
      Save FHEM configuration if a dummy was created.<br>
      Allowed values: none<br>
      Default: disabled<br><br>
      
      Examples:<br>
      <code>
      getURL https://www.example.com/getJSON [dev:reading] --define --save<br>
      </code>
    </ul>
    <!--topicEnd-->

    <br>
    <a name="getURL--force">--force</a>
    <ul>
      Force write of received data to reading(s) even if there is a http response code pointing out an error.<br>
      Allowed values: none<br>
      Default: disabled<br><br>
      
      Example:<br>
      <code>
      getURL https://www.example.com/doIt [dev:reading] --force    # enable<br>
      </code>
    </ul>
    <!--topicEnd-->

    <br>
    <a name="getURL--status">--status</a>
    <ul>
      Write http status code or error into specified reading with suffix '_lastStatus'.<br>
      Allowed values: none<br>
      Default: disabled<br><br>
      
      Example:<br>
      <code>
      getURL https://www.example.com/doIt [dev:reading] --status<br>
      </code>
    </ul>
    <!--topicEnd-->
</li><br>


<br>
<li>
  <u><a name="getURL_optModify">Optional arguments to adopt server response:</a></u><br>
  <br>
     Used to filter/modify server response before it is written into a reading.<br>
     Multiple options can be used. They are processed in shown order.<br><br>

    <a name="getURL--capture">--capture</a>
    <ul>
      Used to extract values from servers response with the help of so called capturue groups.<br>
      For details see perldoc: <a href="http://perldoc.perl.org/perlrequick.html">perlrequick</a>
      &nbsp;/ <a href="https://perldoc.perl.org/perlre.html">perlre</a>. 
      <a href="https://regex101.com/">regex101.com</a> may also be helpful.<br>
      Note that options --capture and --json can not be used at the same time.<br>
      Allowed value: regex with capture groups<br>
      Default: none<br><br>
      
      Examples:<br>
        <code>
        # Unnamed capture groups to extract hour, min, sec from a string that contains<br>
        # "12:01:00" into 3 different readings.<br>
        # Destination readings are: time_1, time_2 and time_3<br>
        getURL https://www.example.com/ [dev1:time] --capture=".*\s(\d\d):(\d\d):(\d\d).*"<br>
        <br>
        # A named capture groups to extract the same string as above.<br>
        # Destination readings are: time_hour, time_min and time_sec<br>
        getURL https://www.example.com/ [dev1:time] --capture=".*\s(?&lt;hour&gt;\d\d):(?&lt;min&gt;\d\d):(?&lt;sec&gt;\d\d).*"<br>
        </code>
    </ul>
    <!--topicEnd-->

    <br>
    <a name="getURL--json">--json</a>
    <ul>
      Decode a JSON string into corresponding readings. Only JSON objects are supported at the moment.<br>
      Note that options --capture and --json can not be used at the same time.<br>
      Allowed values: none<br>
      Default: disabled<br><br>
      
      Example:<br>
      <code>
      # decode a given JSON string into corresponding readings<br>
      getURL https://www.example.com/getJSON [dev:reading] --json<br>
      </code>
    </ul>
    <!--topicEnd-->

    <br>
    <a name="getURL--stripHtml">--stripHtml</a>
    <ul>
     Remove HTML code from server response.<br>
     Perl module HTML::Strip must be installed for good results.
     If it is not installed there is a fallback to a simple regexp mode.<br>
     Missing module is only logged once or with option --debug=1<br>
     Allowed values: none<br>
     Default: disabled<br><br>

     Example:<br>
     <code>
     getURL https://www.example.com/ [dev:reading] --stripHtml<br>
     </code>
    </ul>
    <!--topicEnd-->
    
    <br>
    <a name="getURL--substitute">--substitute</a>
    <ul>
     Replace part(s) of the server response. <br>
     Allowed value: "&lt;toReplace&gt; &lt;replaceWith&gt;"<br>
     &lt;toReplace&gt; is a regular expression. If &lt;replaceWith&gt; is enclosed in {},
     then the content will be executed as a perl expression for each match.
     &lt;toReplace&gt; must not contain a space.<br>
     Default: none<br><br>
     
     Examples:<br>
       <code>
       # shorten server response "power 0.5 W previous: 0 delta_time: 300"<br>
       # to just "power 0.5 W"<br>
       getURL https://www.example.com/ --substitute="(.*W).* $1"<br>
       <br>
       # format each decimal number to 2 decimal places<br>
       getURL https://www.example.com/ --substitute="(\d+\.\d+) {sprintf("%0.2f", $1)}"
       </code>
    </ul>
    <!--topicEnd-->
    
    <br>
    <a name="getURL--userFn">--userFn</a>
    <ul>
      Can be specified to use Perl code to modify received data.<br>
      $DATA is used to hand over received data. $DATA is a scalar variable unless option 
      --capture or --json is used. In this case $DATA is a hash reference. $DATA 
      can be undefined if an previous --option returned an error or did not match. 
      The returned value can be a scalar or a scalar/array/hash reference.<br>
      If the returned value is undefined than the corresponding reading will be deleted.<br>
      Allowed value: {Perl code}<br>
      Default: none<br><br>

      Examples:<br>
      <code>
      # use only the first 4 characters<br>
      getURL https://www.example.com/test --userFn={substr($DATA,0,4)}<br>
      <br>
      # use an own sub, debug option is turned on.<br>
      getURL https://www.example.com/test --userFn={my_getURL_testFn($DATA,4)} --debug=1<br>
      </code>
    </ul>
    <!--topicEnd-->

    <br>
    <a name="getURL--userExitFn">--userExitFn</a>
    <ul>
      Used to call a FHEM command (chain) and/or perl code after server response is written into reading(s).<br>
      Variables that can be used:<br>
      $NAME, $READING, $DEBUG (type: scalar)<br>
      $DATA (type depending on used filterFn: scalar/reference)<br>
      If perl code is used then you have to return undef if no error occur.<br>
      Allowed value: FHEM command(s) and/or perl code<br>
      Default: none<br><br>

      Examples:<br>
      <code>
      # toggle Device<br>
      getURL https://xxx.ddtlab.de [dev:reading] --userExitFn="set $NAME toggle"<br>
      <br>
      # toggle Device and log variables<br>
      getURL https://xxx.ddtlab.de [dev:reading] --debug 
      --userExitFn='set $NAME toggle;;
      {Log 1, "$NAME $READING $DATA $DEBUG" if $DEBUG}'<br>
      <br>
      # call sub function (in 99_myUtils.pm)<br>
      getURL https://xxx.ddtlab.de [dev:reading] --userExitFn={mySub($NAME,$DATA)}<br>
      </code>
    </ul>
    <!--topicEnd-->
</li>


<br><br>
<li>
  <u><a name="getURL_optData">Optional arguments to add data to POST requests:</a></u><br>
  <br>

    <a name="getURL--data">--data</a>
    <ul>
      Specify data to submit with request.<br>
      HTTP POST Method is automatically selected, but can be overwritten with --method.<br>
      Enclose data in quotes if data contain spaces.<br>
      Allowed value: "any data to be send".<br>
      Default: none<br><br>
 
      Example:<br>
      <code>
      getURL https://www.example.com/ --data="Test data 1 2 3"<br>
      </code>
    </ul>
    <!--topicEnd-->
    
    <br>
    <a name="getURL--data-file">--data-file</a>
    <ul>
      Specify a file to read data from to submit with request.<br>
      If a path is specified then it must be relative to <a href="https://fhem.de/commandref.html#modpath">modpath</a>
      (typically /opt/fhem)<br>
      HTTP POST Method is automatically selected, but can be overwritten with --method.<br>
      Allowed value: a filename relative to modpath.<br>
      Default: none<br><br>
      
      Example:<br>
      <code>
      getURL https://www.example.com/ --data-file=mypostdata.txt<br>
      </code>
    </ul>
    <!--topicEnd-->
    
    <br>
    <a name="getURL--form_">--form_</a>
    <ul>
      Specify data for formular POST requests.
      Can be used multiple times.<br>
      Default: none<br><br>
      
      Examples:<br>
      <code>
      # add formular data "Test=abc" to request<br>
      getURL https://www.example.com/form.php --form_Test="abc"</code><br>
      <br>
      # add formular data "Test1=abc&Test2=def" to request<br>
      getURL https://www.example.com/form.php --form_Test1=abc --form_Test2="def"
      </code>
    </ul>
    <!--topicEnd-->
</li>


<br><br>
<li>
  <u><a name="getURL_optHeader">Optional arguments to add HTTP header(s):</a></u><br><br>

    <br>
    <a name="getURLheader">header</a> (without leading --)
    <ul>
      Any combination of 'header=value' will add a HTTP request header.<br>
      Can be used multiples times.<br>
      Allowed value: any header data<br>
      Default: User-Agent=fhem<br><br>
      
      Examples:<br>
      <code>
      getURL https://www.example.com/ User-Agent=FHEM/5.8<br>
      getURL https://www.example.com/ Header1=123 Header2="1 2 3"<br>
      </code>
    </ul>  
    <!--topicEnd-->

    <br>
    <a name="getURL--method">--method</a>
    <ul>
     HTTP method to use.<br>
     Defaults: GET (without --data option), POST (with --data option)<br><br>
     
     Example:<br>
     <code>
     getURL https://www.example.com/ --method=POST --data="Testdata"<br>
     </code>
    </ul>
    <!--topicEnd-->
    
    <br>
    <a name="getURL--httpversion">--httpversion</a>
    <ul>
     Used to specify HTTP version for request.<br>
     Allowed values: 1.0 or 1.1<br>
     Default: 1.0<br><br>
     
     Example:<br>
     <code>
     getURL https://www.example.com/ --httpversion=1.1<br>
     </code>
    </ul>
    <!--topicEnd-->
</li>


<br><br>
<li>
  <u><a name="getURL_optDebug">Log/debug options:</a></u><br><br>
    <a name="getURL--debug">--debug</a>
    <ul>
     Debug server request and response processing.<br>
     0: disabled, 1: enable command logging, 2: enable command and HttpUtils Logging<br>
     Allowed values: 0,1,2<br>
     Default: 0<br><br>
     
     Examples:<br>
     <code>
     getURL https://www.example.com/ debug    # enable for getURL<br>
     getURL https://www.example.com/ debug=1  # enbale for getURL<br>
     getURL https://www.example.com/ debug=2  # enable for getURL/HttpUtils<br>
     </code>
    </ul>
    <!--topicEnd-->

    <br>
    <a name="getURL--loglevel">--loglevel</a>
    <ul>
     Set loglevel for under laying HttpUtils. Used for debugging. See also --debug argument.<br>
     Allowed values: 0..5<br>
     Default: 4<br><br>
     Example:<br>
     <code>
     getURL https://www.example.com/ --loglevel=1<br>
     </code>
    </ul>
    <!--topicEnd-->
    
    <br>
    <a name="getURL--hideurl">--hideurl</a>
    <ul>
     Hide URLs in log entries. Useful if you hand over passwords in URLs.<br>
     Allowed values: none<br>
     Default: disabled<br><br>
     
     Example:<br>
     <code>
     getURL https://www.example.com/ --hideurl=1<br>
     </code>
    </ul>
    <!--topicEnd-->
</li>


<br><br>
<li>
  <u><a name="getURL_optConfig">Optional getURL/HttpUtils connection arguments:</a></u><br><br>
  If &lt;value&gt; contains a space then it must be enclosed in quotes<br><br>
  
    <a name="getURL--timeout">--timeout</a>
    <ul>
     Timeout for http(s) request.<br>
     Allowed values: &gt;0<br>
     Default: 4<br><br>
     
     Example:<br>
     <code>
     getURL https://www.example.com/ --timeout=5<br>
     </code>
    </ul>
    <!--topicEnd-->

    <br>
    <a name="getURL--noshutdown">--noshutdown</a>
    <ul>
     Set to "0" to implizit tell the server to shutdown the connection after this request.<br>
     Allowed values: 0,1<br>
     Default: 1<br><br>
     
     Example:
     <code>getURL https://www.example.com/ --noshutdown=0<br>
     </code>
    </ul>
    <!--topicEnd-->
    
    <br>
    <a name="getURL--ignoreredirects">--ignoreredirects</a>
    <ul>
     Redirects by the server will be ignored if set. Useful to extract cockies from server request and reuse in next request.<br>
     Allowed values: none<br>
     Default: disabled<br><br>
     
     Example:<br>
     <code>
     getURL https://www.example.com/ --ignoreredirects<br>
     </code>
    </ul>
    <!--topicEnd-->
    
    <br>
    <a name="getURL--digest">--digest</a>
    <ul>
     Prevent sending authentication via Basic-Auth. Credentials will be send only after an explizit HTTP digest request.<br>
     Allowed values: none<br>
     Default: disabled<br><br>

     Example:<br>
     <code>getURL https://user:passs@www.example.com/ --digest<br>
     </code>
    </ul>
    <!--topicEnd-->
</li>


<br><br>
<li>
  <u><a name="getURL_optSSL">Optional SSL connection methods:</a></u><br><br>

    <a name="getURL--SSL_">--SSL_</a>
    <ul>
     Used to specify SSL/TLS connection methods for request.<br>
     All IO::Socket::SSL methods are supported.<br>
     Allowed values: see: <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.016/lib/IO/Socket/SSL.pod#Description_Of_Methods">CPAN IO::Socket::SSL</a><br>
     Default: FHEM defaults<br><br>
     
     Examples:<br>
     <code>getURL https://www.example.com/ --SSL_version="TLSv1_2"<br>
     getURL https://www.example.com/ --SSL_verify_mode=0<br>
     getURL https://www.example.com/ --SSL_cipher_list="ALL:!EXPORT:!LOW:!aNULL:!eNULL:!SSLv2"<br>
     getURL https://www.example.com/ --SSL_fingerprint="SHA256:19n6fkdz0qqmowiBy6XEaA87EuG/jgWUr44ZSBhJl6Y"<br>
     </code>
    </ul>
    <!--topicEnd-->
</li>


<br><br>
<li>
  <u>More examples:</u><br><br>
  
    # The simplest form:<br>
    <code>getURL https://www.example.com/</code><br><br>
  
    # The simplest form but write server response into a reading<br>
    <code>getURL https://www.example.com/ [dev:reading]</code><br><br>
  
    # A simple GET request (for ESPEasy):<br>
    <code>getURL https://www.example.com/cmd?control=gpio,14,1</code><br><br>
  
    # A simple POST request:<br>
    <code>getURL https://www.example.com/cmd --data="test,14,1"</code><br><br>
    
    # A simple POST request, server response will be written into reading "result" of device "dev1"<br>
    <code>getURL https://www.example.com/cmd [dev1:result] --data="test,14,1"</code><br><br>
</li>

</ul>

=end html
=cut
