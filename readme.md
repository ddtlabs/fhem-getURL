getURL

    getURL <URL> [<device>:<reading>] <optional arguments>

    Request a http or https URL (non-blocking, asynchron)
    Server respose can optionally be stored in a reading if you specify [<device>:<reading>]

    Arguments:

    URL
        URL to request, http:// and https:// URLs are supported at the moment.

    [<device>:<reading>]
        If you want to write the server response into a reading than specify [device:reading].
        This server response can be optionally manipulated with arguments: --stripHtml, --substitute. --capture, --decodeJSON to fit your needs. See below.

    Simple examples:

    getURL https://www.example.com/cmd?control=gpio,14,1
    getURL https://www.example.com/cmd?control=gpio,14,1 [dev0:result]

    Notes/Tips/Debug:

    - Use --debug=1 parameter and have a look at FHEM's log to debug cmd call.
    - A http(s) request inspect tool can be found here: RequestBin
    - getUrl do not return a server response, directly. The reason is that it is working non-blocking. A possible response from server will be asynchron written into a reading of your choice. If you want to process this value you have to define a notify (or DOIF) that triggers on the value update or change.

    Optional arguments to adopt server response:
    Used to filter server response befor writing into a reading.
    Multiple options can be used. They are processed in shown order.

    --stripHtml
        Strip HTML code from server response.
        Possible values: 0,1
        Default: 0
        Example: getURL https://www.example.com/ stripHtml=1

    --substitute
        Replace (substitute) part of the server response.
        Possible values: "<regex_to_search_for> <replace_with__or_{perl_expression}>"
        Values must not contain a space.
        Possible Default: none
        Example: getURL https://www.example.com/ --substitute=""

    --capture
        Used to extract values from servers response with the help of so called capturue groups.
        Possible values: regex with named or unnamed capture groups.
        For details see perldoc: perlrequick / perlre
        Default: none
        Examples with capture groups to extract a time string (eg. "time string 12:10:00 is given") into 3 different readings.
        getURL https://www.example.com/ [device1:reading2] --capture=".*\s(\d\d):(\d\d):(\d\d).*"
        Destination readings are: reading1_1, reading1_2. reading1_3
        getURL https://www.example.com/ [device1:reading2] --capture=".*\s(?<hour>\d+):(?<min>\d+):(?<sec>\d+).*"
        Destination readings are: reading1_hour, reading1_min. reading1_sec

    --decodeJSON
        Decode a JSON string into readings. Only JSON objects are supported at the moment.
        Possible values: 0,1
        Default: 0
        Example: getURL https://www.example.com/getJSON --decodeJSON=1

    --findJSON
        If the received JSON string is embedded in other text than you could try this option to extract and process the JSON string.
        Possible values: 0,1
        Default: 0
        Example: getURL https://www.example.com/otherJSON.txt --findJSON=1

    Examples:

    getURL https://www.example.com/cmd --capture="^(.*):(.*):(.*)$"
    getURL https://www.example.com/cmd --capture=".*(?<hour>\d\d):(?<min>\d\d):(?<sec>\d\d).*""
    getURL https://www.example.com/cmd --stripHtml --capture="^(.*):(.*):(.*)$"
    getURL https://www.example.com/cmd --substitute="abc 123"
    getURL https://www.example.com/cmd --substitute=".*(TEST).* $1"
    getURL https://www.example.com/cmd --substitute=".*(TEST).* {ReadingsVal("dev0","reading1","")}"
    getURL https://www.example.com/cmd --findJSON=1
    getURL https://www.example.com/cmd --substitute="abc 123" --decodeJSON=1


    Debugging option:

    --debug
        Debug server request and response processing
        0: disabled, 1: enable command logging, 2: enable command and HttpUtils Logging Possible values: 0,1,2
        Default: 0
        Example: getURL https://www.example.com/ debug=1



    All following options are optional and intended for advanced users only.

    Optional arguments to add data to POST requests:

    --data
        Specify data for POST requests.
        HTTP POST Method is automatically selected. Can be overwritten with --method.
        Default: no data
        Example: getURL https://www.example.com/ --data="Test data 1 2 3"

    --form-<nameXXX>
        Specify data for formular POST requests, where <nameXXX> is the name of formular option
        Default: none
        Example: getURL https://www.example.com/ --form-Test="abc"
        Example: getURL https://www.example.com/ --form-Test1=abc --form-Test2="defghi"


    Optional arguments to add HTTP header(s):

    --header
        Used for own header lines Use \r\n so separate multiple headers.
        See also header arguments without leading -- below.
        Possible values: string
        Default: none
        Example: getURL https://www.example.com/ --header="User-Agent: Mozilla/1.22"
        Example: getURL https://www.example.com/ --header="User-Agent: Mozilla/1.22\r\nContent-Type: application/xml"

    Any combination of <header>=<value> (without leading --) will add a HTTP request header.
        Can be used multiples times.
        Example: getURL https://www.example.com/ User-Agent=FHEM/5.8
        Example: getURL https://www.example.com/ Header1=123 Header2="xyz"


    Optional HttpUtils connection arguments:

    If <value> contains a space then it must be enclosed in quotes

    --timeout
        Timeout for http(s) request.
        Possible values: >0
        Default: 4
        Example: getURL https://www.example.com/ --timeout=5

    --noshutdown
        Set to "0" to implizit tell the server to shutdown the connection after this request.
        Possible values: 0,1
        Default: 1
        Example: getURL https://www.example.com/ --noshutdown=1

    --loglevel
        Set loglevel for under laying HttpUtils. Used for debugging. See also --debug argument.
        Possible values: 0,1
        Default: 4
        Example: getURL https://www.example.com/ --loglevel=1

    --hideurl
        Hide URLs in log entries. Useful if you hand over passwords in URLs.
        Possible values: 0,1
        Default: 0
        Example: getURL https://www.example.com/ --hideurl=1

    --ignoreredirects
        Redirects by the server will be ignored if set to 1. Useful to extract cockies from server request and reuse in next request.
        Possible values: 0,1
        Default: 0
        Example: getURL https://www.example.com/ --ignoreredirects=1

    --method
        HTTP method to use.
        Defaults: GET (without --data option), POST (with --data option)
        Example: getURL https://www.example.com/ --method=POST --data="Testdata"

    --sslargs
        Used to specify SSL/TLS parameters. Syntax is {option1 => value [,option2 => value]}.
        Options can be found here: IO::Socket::SSL
        Instead of using this argument with a hash syntax, it may be more easy to use --SSL_xxx arguments. Default: FHEM system default for SSL_version will be used
        Note: FHEM system default for SSL_version can be set with global attribute sslVersion
        Example: getURL https://www.example.com/ --sslargs="{SSL_verify_mode => 0}"
        Example: getURL https://www.example.com/ --sslargs="{SSL_verify_mode => 0, SSL_version => 'TLVv1_2'}"

    --httpversion
        Used to specify HTTP version for request.
        Possible values: 1.0 or 1.1
        Default: 1.0
        Example: getURL https://www.example.com/ --httpversion=1.1

    --digest
        Prevent sending authentication via Basic-Auth. Credentials will be send only after an explizit HTTP digest request.
        Possible values: 0,1
        Default: 0
        Example: getURL https://user:passs@www.example.com/ --digest=1


    Optional SSL connection methods:

    --SSL_xxx
        Used to specify SSL/TLS connection methods for request.
        All IO::Socket::SSL methods are supported.
        Possible values: see: IO::Socket::SSL
        Default: FHEM defaults
        Example: getURL https://www.example.com/ --SSL_version="TLSv1_2"
        Example: getURL https://www.example.com/ --SSL_verify_mode=0
        Example: getURL https://www.example.com/ --SSL_cipher_list="ALL:!EXPORT:!LOW:!aNULL:!eNULL:!SSLv2"
        Example: getURL https://www.example.com/ --SSL_fingerprint="SHA256:19n6fkdz0qqmowiBy6XEaA87EuG/jgWUr44ZSBhJl6Y"


    Advanced examples:

    A simple POST request:
    getURL https://www.example.com/cmd --data="gpio,14,1"

    A simple POST request, server response will be written into reading "result" of device "dev1"
    getURL https://www.example.com/cmd --data="gpio,14,1" [dev1:result]
