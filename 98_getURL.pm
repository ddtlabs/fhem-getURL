# $Id$
package main;

use strict;
use warnings;
use HttpUtils;
use Data::Dumper;

sub CommandGetURL($@);
sub CommandGetURL_expandJSON($$;$$);

my %json;
# ------------------------------------------------------------------------------
sub getURL_Initialize($)
{
  my %lhash   = ( Fn  => "CommandGetURL", 
                  Hlp => "<url> [<device>:<reading>] <more optional arguments, see commandref>"
                );
  $cmds{getURL} = \%lhash;
  $_[0]->{parseParams} = 1
}


# ------------------------------------------------------------------------------
sub CommandGetURL($@)
{
  my ($hash, $cmd) = @_;
  my ($a, $h) = parseParams($cmd);
  my $url = $a->[0];
  
  return "Usage: getURL <url> [device:reading] <optional arguments, see commandref>"
    if @$a < 1;

  if ($h->{"--debug"} && $h->{"--debug"} =~ m/^[12]$/) {
    my $logCmd = $h->{"--hideurl"} ? $cmd =~ s/$a->[0]/<hidden-url>/r : $cmd;
    Log 1, "getURL $logCmd" ;
  }

  if ($url =~ m'^https?://' || $url !~ m'://') {
    CommandGetURL_httpReq($hash, $a, $h, $cmd);
  }
  elsif ($a->[0] =~ m'^telnet://') {
    Log 1, "getURL telnet protocol is not implemented right now";
    return "getURL: telnet protocol is not implemented right now";
  }
  else {
    my $msg = "getURL Unsupported URL: $a->[0]";
    Log 2, "getURL Unsupported URL: $a->[0]";
    return "getURL: Unsupported URL: $a->[0]";
  }

}


# ------------------------------------------------------------------------------
sub CommandGetURL_httpReq($$$$)
{
  my ($hash, $a, $h, $cmd) = @_;  # parseParams is used
  my @header;
  my $param = {
    hash       => $hash,
    timeout    => 5,
    loglevel   => 4,
    cmd        => $cmd,
    callback   => \&CommandGetURL_httpParse,
    setreading => ($a->[1] ? $a->[1] : undef)
  };

  # url handling (add leading "http(s)://" or/and trailing "/" if required
  $param->{url} = $a->[0];
  $param->{url} = "http://".$param->{url} if($param->{url} !~ m'https?://');
  $param->{url} .= "/" if CommandGetURL_paramCount($param->{url}) <= 2 ;

  foreach (keys %{$h}) {
    # Arguments for HttpUtils -> move to $param hash reference
    if (m/^--/) {
      if (m/^--form-.+$/) {
        $param->{data} .= "&" if( $param->{data} );
        $param->{data} .= substr($_,7)."=".urlEncode($h->{$_});
      }
      elsif (m/^--SSL_.+$/) {
        $param->{sslargs}{substr($_,2)} = $h->{$_};
      }
      else {
        $param->{substr($_,2)} = $h->{$_};
      }
      # remove HttpUtils Params (--.*) from parseParams $h
      delete $h->{$_};
    }
    # Arguments without leading -- become part of the header
    else {
      push @header, $_.": ".$h->{$_};
    }
  }

#failsafe
#  delete $param->{sslargs}{SSL_version}
#    if $param->{sslargs} && defined($param->{sslargs}{SSL_version}) &&
#       $param->{sslargs}{SSL_version} =~ m'^(!?)(?:(SSLv(?:2|3|23|2/3))|(TLSv1([12]|_[12]])?)'ix;


  # join header with \r\n
  $param->{header} .= "\r\n" if defined $param->{header} && @header;
  $param->{header} .= join("\r\n",@header);
  $param->{header} =~ s/\\n/\n/xg; # parseParams has escaped "\"
  $param->{header} =~ s/\\r/\r/xg;

  $param->{loglevel} = 1 if ($param->{debug} && $param->{debug} == 2);

  # check sslargs syntax, delete if malformed.
#  if ($param->{sslargs}) {
#    my $sslargs = eval $param->{sslargs};
#    if (!$@) {
##      $param->{sslargs} = \%{ $sslargs };
#      $param->{sslargs} = $sslargs;
#    }
#    else {
#      Log 2, "getURL Malformed --sslargs argument $param->{sslargs} will be ignored.";
#      Log 2, $@;
#      delete $param->{sslargs};
#    }
#  }

#  Debug "----------------------";
#  Debug Dumper $param;
#  Debug "----------------------";

  HttpUtils_NonblockingGet($param);
}


# ------------------------------------------------------------------------------
sub CommandGetURL_httpParse($$$)
{
  my ($param, $err, $data) = @_;
  my $hash  = $param->{hash};
  my $name  = $hash->{NAME};
  my $debug = $param->{debug};
  my $setreading = $param->{setreading};
  
  if($err ne "") {
    Log 1, "getURL $param->{cmd}" if !$debug;
    Log 1, "getURL ERROR while requesting $err";
    #readingsSingleUpdate($hash, "fullResponse", "ERROR");
  }
  elsif(defined $data && $data ne ""){
#Debug "param: ".Dumper $param;

    chomp $data;
#    Log $debug ? 1 : 4, "getURL got: $data from $param->{url}";
    Log $debug ? 1 : 4, "getURL got: $data";
    if ($param->{code} && $param->{code} =~ m/^[459]\d\d$/) {
      $data = "HTTP ERROR: $param->{code}";
      $err = 1;
    }

    if ($setreading) {
      #capture device/reading
      $setreading =~ m/^\[(.*):(.*)\]$/;
      if (defined $1 && defined $2) {
        my ($d,$r) = ($1,$2);
        if (IsDevice($d)) {
          if (!$err) {
            $data = CommandGetURL_stripHtml($data,$debug)
              if $param->{stripHtml};
            $data = CommandGetURL_substitute($data, $param->{substitute}, $debug)
              if $param->{substitute};
 
            # $data becomes a referece
            if ($param->{capture}) {
              $data = CommandGetURL_capture($data, $param->{capture}, $debug);
            }
            elsif ($param->{decodeJSON} || $param->{findJSON}) {
              $data = CommandGetURL_decodeJSON($data, $param->{findJSON} ,$debug);
            }
          }

          # break out of notify loop detection.
          InternalTimer(
            gettimeofday(),
            sub(){ CommandGetURL_updateReadings($defs{$d}, $r, $data, $debug) },
            $hash
          );
        }
        else {
          Log 2, "getURL ERROR: Device $d $setreading don't exist.";
        }
      }
      else { #if (defined $1 && defined $2)
        Log 2, "getURL ERROR: Invalid [device:reading] argument: $setreading.";
      }
    }
  }
}


# ------------------------------------------------------------------------------
sub CommandGetURL_stripHtml($$)
{
  my ($data, $debug) = @_;
  $data =~ s/<(?:[^>'"]*|(['"]).*?\1)*>//gs; # html
  $data =~ s/(^\s+|\r|\n|\s+$)//g; # remove whitespaces and \n
  Log 1, "getURL stripHtml: $data" if $debug;
  return $data;
}


# ------------------------------------------------------------------------------
sub CommandGetURL_substitute($$$)
{
  my ($data, $re, $debug) = @_;
  my ($re2, $re3) = split(" ",$re);
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
    eval "\$data =~ s/$re2/$re3/ge";
  }
  else {
    eval "\$data =~ s/$re2/$re3/g";
  }
  if ($@) {
    Log 2, "getURL WARNING: Invalid regexp: $re2\n$@";
    return undef;
  }

  Log 1, "getURL substitute: $data" if $debug;
  return $data;
}


# ------------------------------------------------------------------------------
sub CommandGetURL_capture($$$)
{
  my ($data, $re, $debug) = @_;
#  return \$data if !defined $re || $re eq "";
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
    CommandGetURL_LogDump("capture", \%capture, 1) if $debug;
    return \%capture;
  }
  else { # match
    Log 2, "getURL no matching capture group for regexp: $re";
  }
  return undef;
}


# ------------------------------------------------------------------------------
sub CommandGetURL_decodeJSON($$;$) {
  my ($dvalue, $findJSON, $debug) = @_;

  # global $data hash for user data is used.
  if (!defined $data{getURL}{JSON} || $data{getURL}{JSON} == 0) {
    eval "require JSON";
    if($@) {
      Log 1, "getURL decodeJSON: Can't load perl module JSON, please install it.";
      Log 1, "getURL decodeJSON: ".$@ if !defined $data{getURL}{JSON};
      $data{getURL}{JSON} = 0;
    } 
    else {
      $data{getURL}{JSON} = 1;
    }
  }

  if ($data{getURL}{JSON} == 1) {

   $dvalue = $findJSON ? CommandGetURL_findJSON($dvalue, $debug) : $dvalue;

    my $h;
    eval { $h = decode_json($dvalue); 1; };
    if ( $@ ) {
      Log 2, "getURL decodeJSON: Malformed JSON: $dvalue";
      Log 2, "getURL decodeJSON: $@";
    }
    else  {
      CommandGetURL_LogDump("decodeJSON", $h, 1) if $debug;
      my $exp = CommandGetURL_expandJSON("",$h);
      CommandGetURL_LogDump("expandJSON", $exp, 1) if $debug;
      return $exp;
    }
  }
  return undef;
}


# ------------------------------------------------------------------------------
sub CommandGetURL_expandJSON($$;$$) {
  my ($sPrefix,$ref,$prefix,$suffix) = @_;
  $prefix = "" if( !$prefix );
  $suffix = "" if( !$suffix );
  $suffix = "_$suffix" if( $suffix );

  if( ref( $ref ) eq "ARRAY" ) {
    while( my ($key,$value) = each @{ $ref } ) {
      CommandGetURL_expandJSON($sPrefix, $value, $prefix.sprintf("%02i",$key+1)."_");
    }
  }
  elsif( ref( $ref ) eq "HASH" ) {
    while( my ($key,$value) = each %{ $ref } ) {
      if( ref( $value ) ) {
        CommandGetURL_expandJSON($sPrefix, $value, $prefix.$key.$suffix."_");
      }
      else {
        my $reading = $sPrefix.$prefix.$key.$suffix;
        $json{$reading} = $value;
      }
    }
  }
  return \%json;
}

# ------------------------------------------------------------------------------
sub CommandGetURL_findJSON($;$) {
  my ($data, $debug) = @_;
  my $json;
  # taken from: stackoverflow.com/questions/21994677/find-json-strings-in-a-string
  my $pattern = '\{(?:[^{}]|(?R))*\}';
  $data =~ m/($pattern)/x;
  if ($1) {
    $data = $1;
    $data =~ s/\R//g; 
    $data =~ s/\s//g; 
    Log 1, "getURL findJSON: $data" if $debug;
    return $data;
  }

  Log 1, "getURL findJSON: <no JSON found>" if $debug;
  return undef ;
}


# ------------------------------------------------------------------------------
sub CommandGetURL_updateReadings($$$;$)
{
  my ($dhash, $dreading, $data, $debug) = @_;
  my $dname = $dhash->{NAME};
  
  if(defined($data)) {
    # remove illegal letters from reading name
    $dreading =~ s/[^A-Za-z\d_\.\-\/]/_/g;
    readingsBeginUpdate($dhash);

    if( ref($data) eq 'HASH' ) {
#Debug "HASH";
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
              Log 1, "getURL setreading [$dname:$r] $data->{$key}{$num}" if $debug;
            }
            else {
              if ($debug) {
                Log 1, $dhash->{READINGS}{$r} 
                  ? "getURL deletereading [$dname:$r]"
                  : "getURL setreading [$dname:$r] 'undef' (skipped due to undefined value)";
              }
              CommandDeleteReading( undef, "$dname $r" );
            }
          }
        }

        # unnamed capture groups
        else {
          if ($data->{$key}) {
            Log 1, "getURL setreading $dname ".$reading." ".$data->{$key} if $debug;
            readingsBulkUpdate($dhash, $reading, $data->{$key});
          }
          else {
            Log 1, "getURL deletereading [$dname:$reading] (due to undefined value)"
              if $debug && $dhash->{READINGS}{$reading};
            CommandDeleteReading( undef, "$dname $reading" );
          }
        }
        
      }
    }

    elsif( ref($data) eq 'SCALAR') {
#Debug "SCALAR";
      Log 1, "getURL setreading [$dname:$dreading] ${ $data }" if $debug;
      readingsBulkUpdate($dhash, $dreading, ${ $data });
    }
    elsif( ref($data) eq '') {
#Debug "NO REF";
      Log 1, "getURL setreading [$dname:$dreading] $data" if $debug;
      readingsBulkUpdate($dhash, $dreading, $data);
    }
    readingsEndUpdate($dhash, 1);
  }


  else { #defined $data
    if (defined $dhash->{READINGS}{$dreading}) {
      Log 1, "getURL deletereading [$dname:$dreading".".*]" if $debug;
      CommandDeleteReading( undef, "$dname $dreading".".*" );
    }
  }
}


# ------------------------------------------------------------------------------
sub CommandGetURL_LogDump($$$)
{
  my ($text, $refVar, $ll) = @_;;
  my $Indent = $Data::Dumper::Indent; my $Terse = $Data::Dumper::Terse;
  $Data::Dumper::Indent = 0; $Data::Dumper::Terse  = 1;
  Log $ll, "getURL $text: " . Dumper $refVar;
  $Data::Dumper::Indent = $Indent; $Data::Dumper::Terse = $Terse;

}


# ------------------------------------------------------------------------------
sub CommandGetURL_paramCount($)
{
  return () = $_[0] =~ m'/'g  # count slashes in a string
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

  <code>getURL &lt;URL&gt; [&lt;device&gt;:&lt;reading&gt;] &lt;optional arguments&gt;</code><br>
  <br>
  Request a http or https URL (non-blocking, asynchron)<br>
  Server respose can optionally be stored in a reading if you specify [&lt;device&gt;:&lt;reading&gt;]<br>
  <br>

<li>
  <u>Arguments:</u><br>
  <br>
  <a name="">URL</a><br>
  <ul>
    URL to request, http:// and https:// URLs are supported at the moment.<br>
  </ul><br>

  <a name="">[&lt;device&gt;:&lt;reading&gt;]</a><br>
  <ul>
    If you want to write the server response into a reading than specify
    [device:reading].<br>
    This server response can be optionally manipulated with arguments: 
    --stripHtml, --substitute. --capture, --decodeJSON to fit your needs. See below.<br>
  </ul><br>
</li>


<li>
  <u>Simple examples:</u><br>
    <br>
    <code>getURL https://www.example.com/cmd?control=gpio,14,1</code><br>
    <code>getURL https://www.example.com/cmd?control=gpio,14,1 [dev0:result]</code><br>
    <br>
</li>

<li>
  <u>Notes/Tips/Debug:</u><br>
    <br>
    - Use --debug=1 parameter and have a look at FHEM's log to debug cmd call.<br>
    - A http(s) request inspect tool can be found here: <a href="https://requestb.in/">RequestBin</a><br>
    - <a href="#getURL">getUrl</a> do not return a server response, directly.
    The reason is that it is working non-blocking. A possible response from
    server will be asynchron written into a reading of your choice. If you want
    to process this value you have to define a notify (or DOIF) that triggers on
    the value update or change.
    <br>
</li><br>


<li>
  <u>Optional arguments to adopt server response:</u><br>
     Used to filter server response befor writing into a reading.<br>
     Multiple options can be used. They are processed in shown order.<br><br>

    <a name="">--stripHtml</a>
    <ul>
     Strip HTML code from server response.<br>
     Possible values: 0,1<br>
     Default: 0<br>
     Example: <code>getURL https://www.example.com/ stripHtml=1</code><br>
    </ul><br>
    
    <a name="">--substitute</a><br>
    <ul>
    Replace (substitute) part of the server response. <br>
     Possible values: "&lt;regex_to_search_for&gt; &lt;replace_with__or_{perl_expression}&gt;"<br>
     Values must not contain a space.<br>
     Possible
     Default: none<br>
     Example: <code>getURL https://www.example.com/ --substitute=""</code><br>
    </ul><br>

    <a name="">--capture</a><br>
    <ul>
     Used to extract values from servers response with the help of so called capturue groups.<br>
     Possible values: regex with named or unnamed capture groups.<br>
     For details see perldoc: <a href="http://perldoc.perl.org/perlrequick.html">perlrequick</a>
     / <a href="https://perldoc.perl.org/perlre.html">perlre</a><br>
     Default: none<br>
     Examples with capture groups to extract a time string (eg. "time string 12:10:00 is given") into 3 different readings.<br>
     <code>getURL https://www.example.com/ [device1:reading2] --capture=".*\s(\d\d):(\d\d):(\d\d).*"</code><br>
     Destination readings are: reading1_1, reading1_2. reading1_3<br>
     <code>getURL https://www.example.com/ [device1:reading2] --capture=".*\s(?&lt;hour&gt;\d+):(?&lt;min&gt;\d+):(?&lt;sec&gt;\d+).*"</code><br>
     Destination readings are: reading1_hour, reading1_min. reading1_sec<br>
    </ul><br>

    <a name="">--decodeJSON</a><br>
    <ul>
    Decode a JSON string into readings. Only JSON objects are supported at the moment.
    <br>
     Possible values: 0,1<br>
     Default: 0<br>
     Example: <code>getURL https://www.example.com/getJSON --decodeJSON=1</code><br>
    </ul><br>

    <a name="">--findJSON</a><br>
    <ul>
    If the received JSON string is embedded in other text than you could try this option
    to extract and process the JSON string.<br>
     Possible values: 0,1<br>
     Default: 0<br>
     Example: <code>getURL https://www.example.com/otherJSON.txt --findJSON=1</code><br>
    </ul><br>

  <u>Examples:</u><br>
    <br>
    <code>getURL https://www.example.com/cmd --capture="^(.*):(.*):(.*)$"</code><br>
    <code>getURL https://www.example.com/cmd --capture=".*(?&lt;hour&gt;\d\d):(?&lt;min&gt;\d\d):(?&lt;sec&gt;\d\d).*""</code><br>
    <code>getURL https://www.example.com/cmd --stripHtml --capture="^(.*):(.*):(.*)$"</code><br>
    <code>getURL https://www.example.com/cmd --substitute="abc 123"</code><br>
    <code>getURL https://www.example.com/cmd --substitute=".*(TEST).* $1"</code><br>
    <code>getURL https://www.example.com/cmd --substitute=".*(TEST).* {ReadingsVal("dev0","reading1","")}"</code><br>
    <code>getURL https://www.example.com/cmd --findJSON=1</code><br>
    <code>getURL https://www.example.com/cmd --substitute="abc 123"  --decodeJSON=1</code><br>
    <br>


</li><br>


<li>
  <u>Debugging option:</u><br><br>
    <a name="">--debug</a>
    <ul>
     Debug server request and response processing<br>
     0: disabled, 1: enable command logging, 2: enable command and HttpUtils Logging
     Possible values: 0,1,2<br>
     Default: 0<br>
     Example: <code>getURL https://www.example.com/ debug=1</code><br>
    </ul><br>
    
</li><br>



<br>
<li>
<b>All following options are optional and intended for advanced users only.</b>
</li><br>


<li>
  <u>Optional arguments to add data to POST requests:</u><br><br>

    <a name="">--data</a>
    <ul>
     Specify data for POST requests.<br>
     HTTP POST Method is automatically selected. Can be overwritten with --method.<br>
     Default: no data<br>
     Example: <code>getURL https://www.example.com/ --data="Test data 1 2 3"</code><br>
    </ul><br>

    <a name="">--form-&lt;nameXXX&gt;</a>
    <ul>
     Specify data for formular POST requests, where &lt;nameXXX&gt; is the name of formular option<br>
     Default: none<br>
     Example: <code>getURL https://www.example.com/ --form-Test="abc"</code><br>
     Example: <code>getURL https://www.example.com/ --form-Test1=abc --form-Test2="defghi"</code><br>
    </ul><br>
</li><br>


<li>
  <u>Optional arguments to add HTTP header(s):</u><br><br>

    <a name="">--header</a>
    <ul>
     Used for own header lines Use \r\n so separate multiple headers.<br>
     See also header arguments without leading -- below.<br>
     Possible values: string<br>
     Default: none<br>
     Example: <code>getURL https://www.example.com/ --header="User-Agent: Mozilla/1.22"</code><br>
     Example: <code>getURL https://www.example.com/ --header="User-Agent: Mozilla/1.22\r\nContent-Type: application/xml"</code><br>
    </ul><br>

     Any combination of <a name="">&lt;header&gt;=&lt;value&gt;</a> (without leading --) will add a HTTP request header.<br>
     <ul>
      Can be used multiples times.<br>
      Example: <code>getURL https://www.example.com/ User-Agent=FHEM/5.8</code><br>
      Example: <code>getURL https://www.example.com/ Header1=123 Header2="xyz"</code><br>
    </ul><br>
</li><br>


<li>
  <u>Optional HttpUtils connection arguments:</u><br><br>
  If &lt;value&gt; contains a space then it must be enclosed in quotes<br><br>
  
    <a name="">--timeout</a>
    <ul>
     Timeout for http(s) request.<br>
     Possible values: &gt;0<br>
     Default: 4<br>
     Example: <code>getURL https://www.example.com/ --timeout=5</code><br>
    </ul><br>

    <a name="">--noshutdown</a>
    <ul>
     Set to "0" to implizit tell the server to shutdown the connection after this request.<br>
     Possible values: 0,1<br>
     Default: 1<br>
     Example: <code>getURL https://www.example.com/ --noshutdown=1</code><br>
    </ul><br>

    <a name="">--loglevel</a>
    <ul>
     Set loglevel for under laying HttpUtils. Used for debugging. See also --debug argument.<br>
     Possible values: 0,1<br>
     Default: 4<br>
     Example: <code>getURL https://www.example.com/ --loglevel=1</code><br>
    </ul><br>

    <a name="">--hideurl</a>
    <ul>
     Hide URLs in log entries. Useful if you hand over passwords in URLs.<br>
     Possible values: 0,1<br>
     Default: 0<br>
     Example: <code>getURL https://www.example.com/ --hideurl=1</code><br>
    </ul><br>

    <a name="">--ignoreredirects</a>
    <ul>
     Redirects by the server will be ignored if set to 1. Useful to extract cockies from server request and reuse in next request.<br>
     Possible values: 0,1<br>
     Default: 0<br>
     Example: <code>getURL https://www.example.com/ --ignoreredirects=1</code><br>
    </ul><br>

    <a name="">--method</a>
    <ul>
     HTTP method to use.<br>
     Defaults: GET (without --data option), POST (with --data option)<br>
     Example: <code>getURL https://www.example.com/ --method=POST --data="Testdata"</code><br>
    </ul><br>

    <a name="">--sslargs</a>
    <ul>
     Used to specify SSL/TLS parameters. Syntax is {option1 =&gt; value [,option2 =&gt; value]}.<br>
     Options can be found here:
     <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.016/lib/IO/Socket/SSL.pod#Description_Of_Methods">IO::Socket::SSL</a><br>
     Instead of using this argument with a hash syntax, it may be more easy to use <a href="#SSL">--SSL_xxx arguments</a>.
     Default: FHEM system default for SSL_version will be used<br>
     Note: FHEM system default for SSL_version can be set with global attribute
     <a href="https://fhem.de/commandref.html#sslVersion">sslVersion</a><br>
     Example: <code>getURL https://www.example.com/ --sslargs="{SSL_verify_mode => 0}"</code><br>
     Example: <code>getURL https://www.example.com/ --sslargs="{SSL_verify_mode => 0, SSL_version => 'TLVv1_2'}"</code><br>
    </ul><br>

    <a name="">--httpversion</a>
    <ul>
     Used to specify HTTP version for request.<br>
     Possible values: 1.0 or 1.1<br>
     Default: 1.0<br>
     Example: <code>getURL https://www.example.com/ --httpversion=1.1</code><br>
    </ul><br>

    <a name="">--digest</a>
    <ul>
     Prevent sending authentication via Basic-Auth. Credentials will be send only after an explizit HTTP digest request.<br>
     Possible values: 0,1<br>
     Default: 0<br>
     Example: <code>getURL https://user:passs@www.example.com/ --digest=1</code><br>
    </ul><br>
</li><br>


<li>
  <u>Optional SSL connection methods:</u><br><br>

    <a name="#SSL">--SSL_xxx</a>
    <ul>
     Used to specify SSL/TLS connection methods for request.<br>
     All IO::Socket::SSL methods are supported.<br>
     Possible values: see: <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.016/lib/IO/Socket/SSL.pod#Description_Of_Methods">IO::Socket::SSL</a><br>
     Default: FHEM defaults<br>
     Example: <code>getURL https://www.example.com/ --SSL_version="TLSv1_2"</code><br>
     Example: <code>getURL https://www.example.com/ --SSL_verify_mode=0</code><br>
     Example: <code>getURL https://www.example.com/ --SSL_cipher_list="ALL:!EXPORT:!LOW:!aNULL:!eNULL:!SSLv2"</code><br>
     Example: <code>getURL https://www.example.com/ --SSL_fingerprint="SHA256:19n6fkdz0qqmowiBy6XEaA87EuG/jgWUr44ZSBhJl6Y"</code><br>
    </ul><br>

</li><br>


<li>
  <u>Advanced examples:</u><br><br>
  
    A simple POST request:<br>
    <code>getURL https://www.example.com/cmd --data="gpio,14,1"</code><br><br>
    
    A simple POST request, server response will be written into reading "result" of device "dev1"<br>
    <code>getURL https://www.example.com/cmd --data="gpio,14,1" [dev1:result]</code><br>
</li>

</ul>

=end html

=begin html_DE

<a name="getURL"></a>
<h3>copy</h3>
<ul>
  <code>getURL &lt;url&gt; [get|post] [&lt;dependent arguments&gt;]</code><br>
  <br>
  Ruft eine url auf.
  </ul>

=end html_DE
=cut
