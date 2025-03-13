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

   - jumping up and down between keyword levels.

   - color highlighting of code lines containing errors/warnings if
     the luacheck program is installed.

   - menu with quick access to functions defined in the buffer.

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

There are three user defined variables that you may set in your ~/.jedrc,
shown here with their default values:

   variable Lua_Indent_Default = 3;
   variable Lua_Expand_Kw_Syntax = 1;
   variable Luacheck_Cmd_Opts = "--no-color --no-global --no-unused --codes";

The first variable, Lua_Indent_Default, sets the default number of spaces
per indentation level. It defaults to 2.

The second variable, Lua_Expand_Kw_Syntax, enables expansion to the full
syntax of a conditional or looping keyword when you type <enter> after it.
If you type if<enter>, it will expand to

  if  then

  end

with the editing point being between "if" and "then".

It defaults to 1, which means enabled.

The third variable, Luacheck_Cmd_Opts, sets the options to the luacheck
program when checking the buffer for errors/warnings. The "--no-color"
option should always be retained, otherwise there will be ansi color codes
in the output.

                  Error checking with the luacheck program:

If the luacheck program is installed, you may check the buffer for
errors/warnings by having the offending lines of code colored. You may then
jump between the lines and see the error message printed in the message
area. Once you have corrected the code, run the function again to remove the
line coloring.

                              Key definitions:

The following keys are defined:

<enter>         - indents the current line and puts editing point in an indented
                  position on the new line. If <enter> is pressed after one of
                  the following keywords

                    if, elseif, for, while, repeat, function

                  it will expand them to their full syntax, if the user defined
                  variable, Lua_Expand_Kw_Syntax, is set to '1'.

<ctrl>-c x      - will execute the code in a region or whole buffer and show the
                  output in an interactive lua window. Exit with <ctrl>-d
                  It only works with the terminal version of Jed, not Xjed.

<ctrl>-c C      - will index and color lines in the buffer, identified by
                  luacheck as having errors/warnings.

<tab>           - will indent the current line. If a region is visibly marked, that
                  whole region will be indented.

<shift>-<down>  - will jump to the next line, identified by luacheck as
                  having an error or warning. The editing point is moved to
                  the start column of the error/warning.

<shift>-<up>    - will jump to the previous line, identified by luacheck as
                  having an error or warning. The editing point is moved to
                  the start column of the error/warning.

<shift>-<F10>   - pop up menu with quick access to functions defined in the
                  buffer.

   (Note that that the <shift>-<up/down> and <shift>-<F10> keys are not
   guaranteed to work.)

Whatever keys you have defined for moving a paragraph up or down, will jump
up or down between keyword levels. If you are on a line with a looping or
conditional keyword or the delimiters, '{' and '}', the forward_paragraph()
function will jump to the matching 'end' or '}' keyword and vice versa with
the backward_paragraph() function. Note that it _requires_ the file to be
correctly indented!

You may access some of these functions in the mode menu with F10 -> Mode

                    Using with the tabcomplete extension:

A completion file is supplied in the archive file "tabcomplete_lua.tar.gz".
It contains the hidden file, ".tabcomplete_lua" which has about 150
functions to complete to, along with their help descriptions. It should be
dumped in your home directory.

In your ~/.jedrc, insert:

   variable Newl_Delim;
   variable Extended_Wordchars;

   define lua_mode_hook()
   {
     Newl_Delim = "\t";
     Extended_Wordchars = ".:";
     init_tabcomplete();
   }

Setting the Newl_Delim variable to the <tab> character, "\t", is necessary
to format the help strings from the completion file correctly. The dot and
colon in the Extended_Wordchars variable ensures that completion works for
targets like "string.reverse" or "file:read".

                                   Issues:

It is not possible to define a string using string begin and end delimiters
with the define_syntax() function in Jed. In lua, a string enclosed in
double brackets, like [[string]], is therefore not correctly highlighted as
a string and words in these strings that are identical to keyword like 'if'
will affect indentation even if they should not.

Send suggestions or bug reports to: mortenbo at hotmail dot com
