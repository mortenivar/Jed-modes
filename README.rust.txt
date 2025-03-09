                                Description:


This is a Jed editing mode intended to make it easier to edit rust code than
with just an ordinary text mode. It formats the code very closely to the way
the rustfmt program does (given whatever coding style one has)

it has the following facilities:

   - syntax highlighting

   - indentation of line or region

   - indentation of editing point following a newline

   - format buffer with the rustfmt program. Errors will be shown in a
     window.

   - compile the buffer with the rustc compiler program. If there
     is output, the output will be displayed in a shell window.
     Errors will also be shown in a window.

   - interactively edit options to rustc.

   - Jumping up and down between block levels delimited by braces,
     parentheses or brackets.

   - "electric" braces from Jed's C mode.

                                Installation:


Copy the rust.sl file to the Jed library directory and in you ~/.jedrc
insert the following two lines;

   autoload ("rust_mode", "rust");
   add_mode_for_extension("rust", "rs");


                                Configuration:


There are two user defined variables that you may set in your ~/.jedrc,
shown here with their default values:

   variable Rust_Indent = 4;
   variable Rustc_Opts = "";

The first variable, Rust_Indent, sets the default number of spaces
per indentation level. It defaults to 4.

The second variable, Rustc_Opts, is a space separated string of options
to be passed to the rustc compiler. E.g. "-g -O"

Note that options to the rustfmt program should be set in its configuration
file, e.g. ~/.config/rustfmt/.rustfmt.toml"

there is a mode hook, "rust_mode_hook", where you may have some settings
specific to the mode.

                              Key definitions:


The following keys are defined:

<enter>         - indents the current line and puts editing point in an indented
                  position on the new line.

<ctrl>-c f      - format buffer with the rustfmt program.

<ctrl>-c o      - edit options to the rustc compiler.

<tab>           - will indent the current line. If a region is visibly marked, that
                  whole region will be indented.


Whatever keys you have defined for moving a paragraph up or down, will jump
up or down between code block levels. If you are on a line with one of the
opening delimiters, '{', '(' or '[' , the forward_paragraph() function will
jump to the matching closing delimiter of the block, '}', ')' or ']' and
vice versa with the backward_paragraph() function. Note that it _requires_
the file to be correctly indented!

You may access some of these functions in the mode menu with F10 -> Mode


                                   Issues:

Rust has a 'lifetime' notation which is marked by one (unbalanced) single
quote. This collides with having a single quote syntax.


Send suggestions or bug reports to: mortenbo at hotmail dot com
