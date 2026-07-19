This little auxiliary mode for the Jed editor aims to facilitate the job of
wrapping commented lines or paragraphs in computer language modes, as well
as wrapping commented lines as you type. It can also work on string
variables. For paragraphs, the paragraph delimiter is always any line which
is not commented.

Normally, you have to write dedicated wrap_hooks, format_paragraph_hooks and
wrapok_hooks to get wrapping of commented paragraphs and line-wrapping of
comments as you type, which can be a little confusing. This mode obviates
the need for that and makes it as easy as pie:

   1) Move wrap.sl to a directory in your jed library path.
   
   2) In your ~/.jedrc or in your mode, near the top insert
   
        require("wrap");
        
   3) You must advertise your comment delimiter to your mode and say that we
      are in computer language mode, so in your mode definition function,
      insert e.g:
        
        define rust_mode
        {
          ...
          set_comment_info("Rust", "// ", "", 0x04);
          set_mode("Rust", 0x04);
          ...
        }

      to advertise that you comment delimiter is "// " like in a mode for
      e.g. the rust language.
      
      If your comment delimiter is "# ", it suffices
      to use:
      
        set_mode(mode, 0x04);

      "0x04" says that it is a generic language mode where the comment
       delimiter is "#" by default.

   4) Then finally, either in your mode definition function or in a mode
      hook in your ~/.jedrc, insert:
   
        wrap_mode();

That's it!

- You should only use it for computer language modes with a defined comment
  delimiter, except for formatting string variables which you may use
  anywhere.

- The key that is normally tied to the "format_paragraph()" function is
  hijacked by this mode and instead tied to the wrap_paragraph_or_string()
  function. Usually, it is <alt>-q

- The wrap column that sets the rightmost limit for the line length is set
  to the value of the global jed variable "WRAP", so if you want to change the
  default value of 72, do so by setting the WRAP variable.

- The wrapping is done with the same formatting as the intrinsic jed function
  "format_paragraph()" does it.

- If standing on a line that is not a comment or if a mark is set, then
  nothing will happen.

- It only works for modes that define a comment delimiter, except when
  operating on string variables.

- It also works for modes that set a comment delimiter, both for the
  beginning and end of the string, such as e.g. for the html markup
  language.

For breaking a line with a newline character (<enter>) and have the new line
automatically prefixed with the comment character, look at one of the library
files, sh.sl, groff_mode.sl, rust.sl or julia.sl for a guidance on how to
write a newline_and_indent function which is then run by the buffer hook,
"newline_indent_hook". Note, that the variables "Cmt_Char_Beg" and
"Cmt_Char_End" which hold the values for the currently defined comment
delimiters, are accessible to the parent mode.


                        Formatting string variables:


If you only want to use it to format string variables, you don't need to
"require" it, but just to load it on demand.

In your ~/.jedrc insert:

   autoload("strfmt", "wrap");

This function, strfmt(), ignores the WRAP setting as the rightmost outer
limit for the line length, so the value you pass to it instead represents
the line length you wish your string formatted to.

It is used as:

   String_Type strfmt(String_Type s, Int_Type wrap_column, [Int_Type indent_col])
    
so

   variable formatted_str = strfmt(s, 45);
   
would format the string variable, "s", to a line length of 45 characters and
return it as "formatted_str" with no indentation when inserting.

whereas

   variable formatted_str = strfmt(s, 72, 20);

would format the string variable, "s", at a line length of at most 72
characters, return it as "formatted_str" while prefixing each line with 20
spaces, so at insertion the lines are indented to column 20.


                  Using wrap_mode with existing Jed modes.


The file "comments.sl", shipping with Jed, and which is sourced from this
mode, defines comment characters for the following Jed modes:

   html, sgml, docbook, C, SLang, TeX, LaTeX, SH, matlab, perl, Fortran,
   TPas, PHP, java, tm, python
   
None of these, except SLang mode, implement the comment wrapping facilities
of this mode, but you can add them to these modes as easily as this, with
for instance perl mode:

In your ~/.jedrc, near the top, insert,

   require("wrap");
   
And then in the mode hook,

   define perl_mode_hook()
   {
      wrap_mode();
   }

Send comments, bug reports or suggestions to:

  Morten Bo Johansen <mortenbo at hotmail dot com>
