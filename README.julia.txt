                       A Julia Mode for the Jed Editor
                       
This is my stab at a julia mode for the jed editor. It sports:

- indentation

- syntax highlighting of keywords, library functions, operators, strings, etc

- a help system with help for more than 2200 julia functions, keywords,
  modules, etc.

- an apropos function

- show output in separate window from execution of julia code in a
  marked region or in the current line.
  

                       Installation and Customization:
                                

Move julia.sl to a place where jed will see it and add the following two
lines to your ~/.jedrc

  autoload ("julia_mode", "julia");
  add_mode_for_extension ("julia", "jl");
  
You may add another two variables to your ~/.jedrc

  variable Julia_Indent_Default = 2;
  variable Julia_Library_Path = "/home/<user>/.julia /usr/local/share/julia"
  
The first of these sets the default number of spaces per indentation level
to two in this case instead of the default of four.

The second of these variables makes jed look in the specified directory or
directories for the julia library files used for generating the help index.
If you specify two or more directories, they must be space separated.

You may add a julia_mode_hook to your .jedrc to do some other things on
startup, e.g.

  define julia_mode_hook ()
  { 
    if (eobp () && bobp ())
      insert ("#!/usr/bin/env julia\n\n");
    
    Tabcomplete_Use_Help = 0;
    init_tabcomplete ();
  }  

                       Using julia.sl With tabcomplete.sl
                       
julia.sl defines its own help interface, so if you use it with tabcomplete,
then make sure to set the variable Tabcomplete_Use_Help = 0; as shown
above.

                                    Keys:


The following keys have been defined:

                            (in the main buffer)

<F1>       help for word at point or with a prompt. Help is available for
           any colored word in the buffer.

<F2>       an apropos prompt

<F9>       show output from execution of julia code in line or region:
           if no region is marked the output from evaluating the code in
           the current line (with the '-E' argument to julia) will be
           shown.

<??>       indent current line or all lines in a marked region. The key
           is your usual key for indentation. Usually it is <tab>

<ctrl-c i> indent whole buffer

<ctrl-c v> show version and license of the mode

<enter>    indent word before editing point if applicable

<??>       scroll up one keyword level in function. This is bound to the
           key for the function, backward_paragraph()

<??>       scroll down one keyword level in function. This is bound to the
           key for the function, forward_paragraph()

Note that "ctrl-c" is the reserved key prefix which may be different in some
emulations.

                            (in the help buffer)
                            
<left arrow>  cycle backwards in help history
<right arrow> cycle forwards in help history
<enter>       show help for word at point
<q>           close help window

Please note that the help system relies on slang version pre2.3.3-59 or
newer.

Please send comments or suggestions to:

  Morten Bo Johansen
  listmail at mbjnet dot dk
  
