                                 Description:
                                 
This pymode.sl is a modified version of the mode that ships with Jed.
Authors of that version are Harri Pasanen and Brien Barton.

The changes in this version are the following:

  - Added indentation after opening delimiters and indentation of 
    closing delimiters.
  
  - Wrap commented lines or paragraphs (with wrap.sl)
  
  - Cleanup: Removed all the redundant comment/uncomment stuff as it is
    handled with comment_region_or_line() from comments.sl which is
    sourced by the now required wrap.sl
    
  - FIX: Many of the builtin kws were not properly highlighted.
  
  - FIX: The key combinations to move lines or regions left or right
         were not using the right functions.
  
  - Added many new keywords for highlighting.
  
  - Check buffer with "ruff check" and color error lines. Jump to them with keys
  
  - View help for word at point, a typed-in word or an error identified by ruff.
  
  - Format buffer with "ruff format"
  
  - Fix some errors/warnings with ruff
  
  - Added a mode menu
  
  - Added a submenu to the mode menu with quick access to functions
  
  - Changed interface for executing code to use run_program() instead of
    run_shell_cmd(). You may also enter options to the program
    
  
                                Requirements:
                                
  
  - A python installation, of course.
  
  - wrap.sl from this repository.
  
  - If you want to use the ruff formatter and linter, then ruff is of course
    needed. On an Arch Linux system you would install it with
    
      sudo pacman -Sy python-ruff
      
  - The less(1) pager program.


                                Installation:
                                

You may simply copy this file over the one that ships with Jed.                                


                                    Usage:
                                    

Most of the functions are available from the menu, F10 -> Mode, and some are
bound to keys which are:

  TAB               indents line
          
  <ctrl>-c >        shifts line or region right
          
  <ctrl>-c <        shifts line or region left
          
  <ctrl>-c <ctrl>-c executes the region, or the whole buffer if region not marked.
          
  <ctrl>-c\t        reindents the region
          
  :                 colon dedents appropriately
          
  <ctrl>-c f        formats the buffer with "ruff format"
          
  <ctrl>-c k        runs the ruff linter on the buffer and colors and indexes
                    lines w/errors/warnings
          
  <F1>              shows help for word at point, a typed-in word, or if
                    after having run py_check() and standing on a line with
                    an error/warning, it will show the full explanation of the
                    error/warning. An empty string will start python's help
                    utility in an interactive window.
  
  <ctrl>-c <Up>     go to previous line with error/warning after a linter check
  
  <ctrl>-c <Down>   go to next line with error/warning after a linter check

Functions not tied to keys but available from the menu:

  py_fix() - fix some errors/warnings with ruff


                        Explanation of some commands:
                        

<ctrl>-c <ctrl>-c, will run any command on the buffer and show the output
and also interact with the user if the script features that. The command
defaults to python3 and it is followed by a prompt where you may type in
some arguments to the command, so, if at the two prompts, you did:

  Execute command: (default: python3) 󰌑
  additional arguments to "python3": -i 󰌑
  
then it would first execute the script or region in the script in the buffer
and then dump you into python's interactive mode afterwards. Output is
paused at the last screenful. If the output covers more than one screenful
and you want to see it, then use the terminal's scrollback feature, usually
tied to <Ctrl>-<Shift>-<PgUp> or as with the kitty terminal, you may use
<Ctrl>-<Shift>-g to have the whole scrollback buffer dumped into a pager.

<ctrl>-c k, will check the buffer with ruff and color all lines that ruff
has identified as having an issue. You may jump to and fro between them with
<ctrl>-c <Up>/<Down>. Typing <F1> on such a line will show the full
description of the error code in a pager.

Comments, etc. to Morten Bo Johansen <mortenbo at hotmail dot com>

