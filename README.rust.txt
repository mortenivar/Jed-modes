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

   - cargo run

   - cargo check

   - create new cargo project

   - cargo build release

   - cargo add crate

   - load cargo project 

   - interactively edit options to rustc.

   - jumping up and down between block levels delimited by braces,
     parentheses or brackets.

   - "dynamic" braces from Jed's C mode.

   - quick access menu with defined functions in the buffer.


                                Installation:


Copy the rust.sl file to the Jed library directory and in you ~/.jedrc
insert the following two lines;

   autoload ("rust_mode", "rust");
   add_mode_for_extension("rust", "rs");


                                Configuration:


There are four user defined variables that you may set in your ~/.jedrc,
shown here with their default values:

   variable Rust_Indent = 4;
   variable Rustc_Opts = "";
   variable("Rust_Brace_Style", "k&r");
   variable("Rust_Proj_dir", expand_filename("~/devel/rust"));

The first variable, Rust_Indent, sets the default number of spaces
per indentation level. It defaults to 4.

The second variable, Rustc_Opts, is a space separated string of options
to be passed to the rustc compiler. E.g. "-g -O"

The third variable, Rust_Brace_Style, is a string that may be set to
any of the following values to enforce its corresponding brace style:

   "gnu"      Style advocated by GNU
   "k&r"      Style popularized by Kernighan and Ritchie
   "bsd"      Berkeley style
   "foam"     Derivate bsd-style used in OpenFOAM
   "linux"    Linux kernel indentation style
   "jed"      Style used by the author
   "kw"       The Kitware style used in ITK, VTK, ParaView,

The fourth variable, Rust_Proj_dir, sets the storage directory for your
program/projects.

Note that options to the rustfmt program should be set in its configuration
file, e.g. ~/.config/rustfmt/.rustfmt.toml". These settings should probably
correspond to the brace style used while editing.

There is a mode hook, "rust_mode_hook", where you may have some settings
specific to the mode, e.g. in your ~/.jedrc insert:

    variable Rust_Brace_Style;

    define rust_mode_hook()
    {
       Rust_Brace_Style = "linux";
    }

to enforce the brace style used by the Linux kernel develeopers while
editing.


                              Key definitions:


The following keys are defined:

<enter>         - indents the current line and puts editing point in an indented
                  position on the new line.

<ctrl>-c f      - format buffer with the rustfmt program.

<ctrl>-c o      - edit options to the rustc compiler.

<ctrl>-c p      - create new cargo project

<ctrl>-c L      - load existing cargo project

<ctrl>-c a      - add crate

<ctrl>-c r      - build release

<tab>           - will indent the current line. If a region is visibly marked, that
                  whole region will be indented.

<f7>            - cargo check.

<f8>            - cargo run

<F9>            - compile buffer with rustc

<Shift>-<F10>   - pop up quick access menu with function definitions.

Whatever keys you have defined for moving a paragraph up or down, will jump
up or down between code block levels. If you are on a line with one of the
opening delimiters, '{', '(' or '[' , the forward_paragraph() function will
jump to the matching closing delimiter of the block, '}', ')' or ']' and
vice versa with the backward_paragraph() function. Note that it _requires_
the file to be correctly indented!

You may access some of these functions in the mode menu with F10 -> Mode


                                   Issues:

Rust has a 'lifetime' notation which is marked by one (unbalanced) single
quote. This collides with having a single quote string syntax.


Send suggestions or bug reports to: mortenbo at hotmail dot com
