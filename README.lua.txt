                                Description:


This is a Jed editing mode intended to make it easier to edit lua code than
with just an ordinary text mode.

It is meant as a drop-in replacement for the lua mode that ships with Jed
which has many glitches in its indentation functionality. From what I could
see, that mode needs a complete rewrite to make it behave, so I decided to
make this mode instead. I used the shell script mode from this repository as
a template so it was fairly fast and easy to make it.

it has the following facilities:

   - syntax highlighting

   - indentation of line or region

   - indentation of editing point following a newline

   - expansion of syntax typing <enter> after looping or conditional
     keywords

   - execution of code in a region or entire buffer with output
     being shown in window. Also works with interactive scripts.
     It only works with the terminal version of Jed.

   - Jumping up and down between keyword levels.


                                Installation:


Either copy the lua.sl file to the Jed library dircetory, overwriting the
version that ships with Jed or better yet, do something like this:

   mkdir -p ~/.local/share/jed/myjedlib
   mv lua.sl ~/.local/share/jed/myjedlib

   in your ~/.jedrc, insert this line near the top:

     set_jed_library_path (strcat(expand_filname(~/.local/share/jed/myjedlib), ",", get_jed_library_path));

Now this version of lua.sl should be loaded instead of the stock version.

You may check if it works by issuing

   jed -batch somefile.lua

it should respond with

   ...
   ...
   Reading somefile.lua
   loading /home/<user>/.local/share/jed/myjedlib/lua.sl
   ...

                                Configuration:

There are two user defined variables that you may set in your ~/.jedrc:

   variable Lua_Indent_Default = 2;
   variable Lua_Expand_Kw_Syntax = 1;

The first variable sets the default number of spaces per indentation level.
It defaults to 2.

The second variable enables expansion to the full syntax of a conditional or
looping keyword when you type <enter> after it. If you type if<enter>, it
will expand to

  if  then

  end

with the editing point being between "if" and "then".

It defaults to 1, which means enabled.


                              Key definitions:


The following keys are defined:

<enter>    - indents the current line and puts editing point in an indented
             position on the new line. If <enter> is pressed after one of
             the following keywords

               if, elseif, for, while, repeat, function

             it will expand them to their full syntax, if the user defined
             variable, Lua_Expand_Kw_Syntax, is set to '1'.

<ctrl>-c x - will execute the code in a region or whole buffer and show the
             output in an interactive lua window. Exit with <ctrl>-d
             It only works with the terminal version of Jed, not Xjed.

<tab>      - will indent the current line. If a region is visibly marked, that
             whole region will be indented.

Whatever keys you have defined for moving a paragraph up or down, will jump
up or down between keyword levels. If you are on a line with a looping or
conditional keyword or the delimiters, '{' and '}', the forward_paragraph()
function will jump to the matching 'end' or '}' keyword and vice versa with
the backward_paragraph() function. Note that it _requires_ the file to be
correctly indented!


                    Using with the tabcomplete extension:


A completion file is supplied in the archive file "tabcomplete_lua.tar.gz".
It contains the hidden file, ".tabcomplete_lua" which has about 150
functions to complete to, along with their help descriptions. It should be
dumped in your home directory.

In your ~/.jedrc, insert:

   variable Newl_Delim;

   define lua_mode_hook()
   {
     Newl_Delim = "\t";
     init_tabcomplete();
   }

Setting the Newl_Delim variable to the <tab> character, "\t", is necessary
to format the help strings from the completion file correctly.

Send suggestions or bug reports to: mortenbo at hotmail dot com


