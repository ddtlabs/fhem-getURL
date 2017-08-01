<html>
<body>
<h3>getURL</h3>


  Request a HTTP(S) URL (non-blocking, asynchron)
  
  Server response can optionally be stored in a reading if you specify [device:reading]
  
  Optional arguments are described below.
  
  
  getURL URL
  
  getURL URL [device:reading]
  
  getURL URL --option
  
  getURL URL [device:reading] --option
    

  Arguments:
  
    URL
    
      URL to request, http:// and https:// URLs are supported at the moment.
      eg. https://example.com/
    
    

    [device:reading]
    
      Server response will be written into this reading if specified. Can be omitted.
    
    
    --option
    
      There are groups of optional arguments to:
        - adopt server response (readings)
        - add data to requests
        - add HTTP headers
        - configure server requests
        - configure SSL/TLS methods
        - Debug/Log
  

  Examples:
    
      
        getURL https://www.example.com/
      
        getURL https://www.example.com/ [dev0:result]
      
        getURL https://www.example.com/ --status --force 
      
        getURL https://www.example.com/ [dev:rXXX] --status --force --define
      
        getURL https://www.example.com/ [dev:rYYY] --httpversion=1.1 --SSL_version=SSLv23:!SSLv3:!SSLv2
      
    
  Syntax help and help for options is also available:
    
  getURL help
  
  getURL help --option
  

  Notes:
    
      getUrl do not return a server response, directly.
      The reason is that it is working non-blocking. A possible response from
      server will be asynchron written into a reading of your choice. If you want
      to further process this value you have to use --userExitFn option or you have
      to define a notify (or DOIF) that triggers on the updated or changed value.
    
    
      Use --debug or --debug=2 argument and have a look at FHEM's log file to
      see requests and responses if something went wrong.
    
    
      An online http(s) request inspect tool can be found
      here to examine your command line
      arguments if you don't have an own webserver to test with.
    
    
      If a (set magic) device/reading combination is specified and an error
      occured or the returned HTTP status code comply with 4xx, 5xx or 9xx then the status it is 
      written into a reading with suffix '_lastStatus'. 
      If all response codes (also good once) should be written into this reading
      then option '--status' must be applied. See below.
    
  
  <u>Optional arguments to adopt command behaviour:</u>
  

    --define
    
      Define destination device for reading(s) if not already exist.
      A dummy device will be defined/created if there is no accordingly device.
      Allowed values: none
      Default: disabled
      
      Examples:
      
      # device 'dev' will be defined if not already defined to be able to write readings to.
      getURL https://www.example.com/getJSON [dev:reading] --define
      
    
    

    --save
    
      Save FHEM configuration if a dummy was created.
      Allowed values: none
      Default: disabled
      
      Examples:
      
      getURL https://www.example.com/getJSON [dev:reading] --define --save
      
    
    

    
    --force
    
      Force write of received data to reading(s) even if there is a http response code pointing out an error.
      Allowed values: none
      Default: disabled
      
      Example:
      
      getURL https://www.example.com/doIt [dev:reading] --force    # enable
      
    
    

    
    --status
    
      Write http status code or error into specified reading with suffix '_lastStatus'.
      Allowed values: none
      Default: disabled
      
      Example:
      
      getURL https://www.example.com/doIt [dev:reading] --status
      
    
    





  <u>Optional arguments to adopt server response:</u>
  
     Used to filter/modify server response before it is written into a reading.
     Multiple options can be used. They are processed in shown order.

    --capture
    
      Used to extract values from servers response with the help of so called capturue groups.
      For details see perldoc: perlrequick
      &nbsp;/ perlre. 
      regex101.com may also be helpful.
      Note that options --capture and --json can not be used at the same time.
      Allowed value: regex with capture groups
      Default: none
      
      Examples:
        
        # Unnamed capture groups to extract hour, min, sec from a string that contains
        # "12:01:00" into 3 different readings.
        # Destination readings are: time_1, time_2 and time_3
        getURL https://www.example.com/ [dev1:time] --capture=".*\s(\d\d):(\d\d):(\d\d).*"
        
        # A named capture groups to extract the same string as above.
        # Destination readings are: time_hour, time_min and time_sec
        getURL https://www.example.com/ [dev1:time] --capture=".*\s(?&lt;hour&gt;\d\d):(?&lt;min&gt;\d\d):(?&lt;sec&gt;\d\d).*"
        
    
    

    
    --json
    
      Decode a JSON string into corresponding readings. Only JSON objects are supported at the moment.
      Note that options --capture and --json can not be used at the same time.
      Allowed values: none
      Default: disabled
      
      Example:
      
      # decode a given JSON string into corresponding readings
      getURL https://www.example.com/getJSON [dev:reading] --json
      
    
    

    
    --stripHtml
    
     Remove HTML code from server response.
     Perl module HTML::Strip must be installed for good results.
     If it is not installed there is a fallback to a simple regexp mode.
     Missing module is only logged once or with option --debug=1
     Allowed values: none
     Default: disabled

     Example:
     
     getURL https://www.example.com/ [dev:reading] --stripHtml
     
    
    
    
    
    --substitute
    
     Replace part(s) of the server response. 
     Allowed value: "&lt;toReplace&gt; &lt;replaceWith&gt;"
     &lt;toReplace&gt; is a regular expression. If &lt;replaceWith&gt; is enclosed in {},
     then the content will be executed as a perl expression for each match.
     &lt;toReplace&gt; must not contain a space.
     Default: none
     
     Examples:
       
       # shorten server response "power 0.5 W previous: 0 delta_time: 300"
       # to just "power 0.5 W"
       getURL https://www.example.com/ --substitute="(.*W).* $1"
       
       # format each decimal number to 2 decimal places
       getURL https://www.example.com/ --substitute="(\d+\.\d+) {sprintf("%0.2f", $1)}"
       
    
    
    
    
    --userFn
    
      Can be specified to use Perl code to modify received data.
      $DATA is used to hand over received data. $DATA is a scalar variable unless option 
      --capture or --json is used. In this case $DATA is a hash reference. $DATA 
      can be undefined if an previous --option returned an error or did not match. 
      The returned value can be a scalar or a scalar/array/hash reference.
      If the returned value is undefined than the corresponding reading will be deleted.
      Allowed value: {Perl code}
      Default: none

      Examples:
      
      # use only the first 4 characters
      getURL https://www.example.com/test --userFn={substr($DATA,0,4)}
      
      # use an own sub, debug option is turned on.
      getURL https://www.example.com/test --userFn={my_getURL_testFn($DATA,4)} --debug=1
      
    
    

    
    --userExitFn
    
      Used to call a FHEM command (chain) and/or perl code after server response is written into reading(s).
      Variables that can be used:
      $NAME, $READING, $DEBUG (type: scalar)
      $DATA (type depending on used filterFn: scalar/reference)
      If perl code is used then you have to return undef if no error occur.
      Allowed value: FHEM command(s) and/or perl code
      Default: none

      Examples:
      
      # toggle Device
      getURL https://xxx.ddtlab.de [dev:reading] --userExitFn="set $NAME toggle"
      
      # toggle Device and log variables
      getURL https://xxx.ddtlab.de [dev:reading] --debug 
      --userExitFn='set $NAME toggle;;
      {Log 1, "$NAME $READING $DATA $DEBUG" if $DEBUG}'
      
      # call sub function (in 99_myUtils.pm)
      getURL https://xxx.ddtlab.de [dev:reading] --userExitFn={mySub($NAME,$DATA)}
      
    
    





  <u>Optional arguments to add data to POST requests:</u>
  

    --data
    
      Specify data to submit with request.
      HTTP POST Method is automatically selected, but can be overwritten with --method.
      Enclose data in quotes if data contain spaces.
      Allowed value: "any data to be send".
      Default: none
 
      Example:
      
      getURL https://www.example.com/ --data="Test data 1 2 3"
      
    
    
    
    
    --data-file
    
      Specify a file to read data from to submit with request.
      If a path is specified then it must be relative to modpath
      (typically /opt/fhem)
      HTTP POST Method is automatically selected, but can be overwritten with --method.
      Allowed value: a filename relative to modpath.
      Default: none
      
      Example:
      
      getURL https://www.example.com/ --data-file=mypostdata.txt
      
    
    
    
    
    --form_
    
      Specify data for formular POST requests.
      Can be used multiple times.
      Default: none
      
      Examples:
      
      # add formular data "Test=abc" to request
      getURL https://www.example.com/form.php --form_Test="abc"
      
      # add formular data "Test1=abc&Test2=def" to request
      getURL https://www.example.com/form.php --form_Test1=abc --form_Test2="def"
      
    
    





  <u>Optional arguments to add HTTP header(s):</u>

    
    header (without leading --)
    
      Any combination of 'header=value' will add a HTTP request header.
      Can be used multiples times.
      Allowed value: any header data
      Default: User-Agent=fhem
      
      Examples:
      
      getURL https://www.example.com/ User-Agent=FHEM/5.8
      getURL https://www.example.com/ Header1=123 Header2="1 2 3"
      
      
    

    
    --method
    
     HTTP method to use.
     Defaults: GET (without --data option), POST (with --data option)
     
     Example:
     
     getURL https://www.example.com/ --method=POST --data="Testdata"
     
    
    
    
    
    --httpversion
    
     Used to specify HTTP version for request.
     Allowed values: 1.0 or 1.1
     Default: 1.0
     
     Example:
     
     getURL https://www.example.com/ --httpversion=1.1
     
    
    





  <u>Log/debug options:</u>
    --debug
    
     Debug server request and response processing.
     0: disabled, 1: enable command logging, 2: enable command and HttpUtils Logging
     Allowed values: 0,1,2
     Default: 0
     
     Examples:
     
     getURL https://www.example.com/ debug    # enable for getURL
     getURL https://www.example.com/ debug=1  # enbale for getURL
     getURL https://www.example.com/ debug=2  # enable for getURL/HttpUtils
     
    
    

    
    --loglevel
    
     Set loglevel for under laying HttpUtils. Used for debugging. See also --debug argument.
     Allowed values: 0..5
     Default: 4
     Example:
     
     getURL https://www.example.com/ --loglevel=1
     
    
    
    
    
    --hideurl
    
     Hide URLs in log entries. Useful if you hand over passwords in URLs.
     Allowed values: none
     Default: disabled
     
     Example:
     
     getURL https://www.example.com/ --hideurl=1
     
    
    





  <u>Optional getURL/HttpUtils connection arguments:</u>
  If &lt;value&gt; contains a space then it must be enclosed in quotes
  
    --timeout
    
     Timeout for http(s) request.
     Allowed values: &gt;0
     Default: 4
     
     Example:
     
     getURL https://www.example.com/ --timeout=5
     
    
    

    
    --noshutdown
    
     Set to "0" to implizit tell the server to shutdown the connection after this request.
     Allowed values: 0,1
     Default: 1
     
     Example:
     getURL https://www.example.com/ --noshutdown=0
     
    
    
    
    
    --ignoreredirects
    
     Redirects by the server will be ignored if set. Useful to extract cockies from server request and reuse in next request.
     Allowed values: none
     Default: disabled
     
     Example:
     
     getURL https://www.example.com/ --ignoreredirects
     
    
    
    
    
    --digest
    
     Prevent sending authentication via Basic-Auth. Credentials will be send only after an explizit HTTP digest request.
     Allowed values: none
     Default: disabled

     Example:
     getURL https://user:passs@www.example.com/ --digest
     
    
    





  <u>Optional SSL connection methods:</u>

    --SSL_
    
     Used to specify SSL/TLS connection methods for request.
     All IO::Socket::SSL methods are supported.
     Allowed values: see: CPAN IO::Socket::SSL
     Default: FHEM defaults
     
     Examples:
     getURL https://www.example.com/ --SSL_version="TLSv1_2"
     getURL https://www.example.com/ --SSL_verify_mode=0
     getURL https://www.example.com/ --SSL_cipher_list="ALL:!EXPORT:!LOW:!aNULL:!eNULL:!SSLv2"
     getURL https://www.example.com/ --SSL_fingerprint="SHA256:19n6fkdz0qqmowiBy6XEaA87EuG/jgWUr44ZSBhJl6Y"
     
    
    





  <u>More examples:</u>
  
    # The simplest form:
    getURL https://www.example.com/
  
    # The simplest form but write server response into a reading
    getURL https://www.example.com/ [dev:reading]
  
    # A simple GET request (for ESPEasy):
    getURL https://www.example.com/cmd?control=gpio,14,1
  
    # A simple POST request:
    getURL https://www.example.com/cmd --data="test,14,1"
    
    # A simple POST request, server response will be written into reading "result" of device "dev1"
    getURL https://www.example.com/cmd [dev1:result] --data="test,14,1"



</body>
</html>
