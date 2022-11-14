               sh.sl - a shell script mode for the Jed editor


                           Description of the Mode


This is an editing mode for the Jed editor, http://jedsoft.org/jed, to
facilitate the editing of shell scripts. It should work fine with bash,
dash, zsh and ksh and that family of shells.


                                Installation


- Copy sh.sl to a place where Jed will find it, usually
  /usr/share/jed/lib or /usr/local/jed/lib

- Insert the following two lines into your ~/.jedrc

     autoload("sh_mode", "sh");
     add_mode_for_extension("sh", "sh");

Then make sure that your scripts have the "*.sh" extension.


                                 Facilities


- Indentation of current line or a marked region, usually with <tab>

- Automatic indentation following a newline.

- Syntax highlighting of keywords, built-ins and variables.

- Automatic insertion of whole statement blocks if activated. If the code
  block is inserted within an existing block, it will be nicely indented
  relative to that block.

- If the shellcheck program is installed, you can have it check the current
  buffer for errors/warnings/notes and have offending lines colored in the
  color of the preprocessor directive, often magenta or brightgreen. You can
  jump to and fro between these error lines and see the error message from
  shellcheck in the message area.


                                Customization


Three variables may be set in ~/.jedrc, shown here with their defaults as a
block that may be inserted into the ~/.jedrc:

    variable SH_Indent = 2;
    variable SH_Browser = "lynx";
    variable SH_Expand_Kw_Syntax = 0;

- SH_Indent, determines the number of spaces for an indentation level.

- SH_Browser, sets the browser to use for looking up items on the shellcheck
  wiki

- SH_Expand_Kw_Syntax, if set to 1, typing <enter> after one of the keywords

    if, elif, for, while, select, until, case

  will expand and insert the complete syntax for these keywords, i.e. typing
  enter after the 'for' keyword will insert and expand it to

    for  in ; do

    done

with the editing point placed between 'for' and 'in'. If insertion is done
within an existing statement block, it will be indented relative to that
block.

                                    Keys


<ctrl>-c C,   will execute the shellcheck program (if installed) on the
              current script and color lines that are identified by
              shellcheck as having errors/warnings.

<shift>-down, will jump to the next shellcheck error line, relative to the
              editing point, and display the error message for that line in
              the message area. The editing point will be moved to column of
              the reported start of the offending code.

<shift>-up,   will jump to the previous shellcheck error line, relative to the
              editing point, and display the error message for that line in
              the message area. The editing point will be moved to column of
              the reported start of the offending code.

<ctrl>-c W,   will show the shellcheck wiki explanation for the current shellcheck
              error line in a browser. You need to have jumped to an error
              line first with one of the two key combos above.

<ctrl>-pgup,  briefly show the matching keyword that begins a code block or
              sub-block, if standing on the keyword that ends the block.
              Sometimes convenient in long, convoluted constructs.

<tab>,        usually, will indent the current line or a marked region

<enter>       will indent the current line and place the editing point on the new
              line in an indented position.


                            How Indentation Works


The indentation routine in this mode works on a line-by-line basis. The bulk
of the indentation is done by detecting the keyword in the current line and
the nearest keyword in a preceding line. Keywords may be statement keywords
like 'if, 'else', 'elif', etc. but may also be 'NULL' or a character that
may influence indentation like an opening left brace or parenthesis. The
relationship between the keyword in the current line and the preceding
keyword is most often enough to determine the indentation. If the keyword in
the current line is one that ends a statement block or sub-block such as
'fi', 'else', 'elif', 'done', etc., the matching parent keyword that begins
the block will be found, regardless of indentation level, so that nested
constructs will be correctly indented.

It has been tested on the ~2000 shell scripts installed on my computer by
executing the "sh_indent_region_or_line" function on the whole buffer and
it gets it right in nearly all cases, even in large, complex and intricate
scripts, but of course there are some ...


                                    Issues


- Indentation of the first line following a 'heredoc' block of text may not
  be correct, as the text block may contain false positive "keywords" that
  won't be skipped unless the 'heredoc' block of text is presented as a
  string. The 'heredoc' block itself may also be mangled.

- Indentation in multi-line code blocks following an 'eval' command don't
  work as these are detected as strings and therefore all keywords within them
  are detected as 'NULL'

- There are some occasional quoting issues that are hard to get around where
  a whole subsequent block of code may be identified as a string even if it
  isn't. E.g. how do you deal with a line like this:
  "for _G_char in '\' '`' '"' '$'" ?

 (probably several others)


Morten Bo Johansen, listmail at mbjnet dot dk
