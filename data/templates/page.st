<!DOCTYPE html>
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    $if(feed)$
    <link href="$base$/_feed/" type="application/atom+xml" rel="alternate" title="$wikititle$" />
    <link href="$base$/_feed$pageUrl$" type="application/atom+xml" rel="alternate" title="$wikititle$ - $pagetitle$" />
    $endif$
    <title>$wikititle$ - $pagetitle$</title>
    $if(printable)$
    <link href="$base$/css/print.css" rel="stylesheet" media="all" type= "text/css" />
    $else$
    <!-- TODO easymde needs like 5 symbols from the font-awesome font, can we instead replace them by some built-in unicode symbols? -->
    <link href="$base$/css/easymde.min.css" rel="stylesheet" media="screen, projection" type="text/css" />
    <link href="$base$/font-awesome/css/fontawesome.css" rel="stylesheet" media="screen, projection" type="text/css" />
    <link href="$base$/font-awesome/css/solid.css" rel="stylesheet" media="screen, projection" type="text/css" />
    <link href="$base$/css/custom.css" rel="stylesheet" media="screen, projection" type="text/css" />
    <link href="$base$/css/print.css" rel="stylesheet" media="print" type= "text/css" />
    $endif$
    <!--[if IE]><link href="$base$/css/ie.css" rel="stylesheet" media="screen, projection" type="text/css" /><![endif]-->
  </head>
  <body>
    <div id="doc3">
        <div id="yui-main">
          <div id="maincol" class="yui-b">
            $content()$
          </div>
        </div>
    </div>
    $javascripts$
    $expire()$
    $getuser()$
  </body>
</html>
