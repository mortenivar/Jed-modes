                               1. DESCRIPTION:

This is just another word completion function which uses the TAB key as
completion key by default. The words that are targets for completion are
loaded from a file. File is read line by line and may include other files.
Target word may actually be one or more words. There may be optional fields
in the line delimited by two colons where the additional fields may hold
e.g. a syntax for a programming function and a help text for the function.
Using the newline escape character "\n" in the syntax will see it expanded
upon completion. Using the "@@" string in the syntax will have it replaced
with the editing point upon completion. Using the single character, '@'
after a target word, means that it is an alias (see 3.1.). Thus, you can
create the equivalent of simple boilerplate snippets.

                2. NAME AND LOCATION OF THE COMPLETIONS FILE

The name and location of the file holding the target words for completion
defaults to /home/${user}/.completions_{mode}, i.e. a hidden file in your
home directory, which e.g. in slang_mode would be named ".completions_slang"
or in text_mode, ".completions_text".

If you don't like that, you can change it in a mode hook by giving a new
name to the completions file as an argument to the init_tabcomplete function,
e.g.

     define slang_mode_hook ()
     {
       ..
       init_tabcomplete ("/home/user/myslangfuns");
     }

                               3. INSTALLATION

1) Move the file, "tabcomplete.sl" to a directory in your jed library
   path, usually /usr/share/jed/lib or /usr/local/share/jed/lib

2) Create a file with target words or snippets to complete from.
   See sections 2. and 4.

3) In your $HOME/.jedrc, insert the following line:

     autoload ("init_tabcomplete", "tabcomplete");

   After this line, you must specify what modes to use completion for in a
   mode hook. E.g. in your $HOME/.jedrc insert:

     define slang_mode_hook ()
     {
       Wordchars = "a-zA-Z0-9";
       Extended_Wordchars = "_"
       init_tabcomplete ();
     }

   A completions file for SLang is supplied which also includes syntaxes. If
   you don't like that, you can just start up with no completions file, then
   one will be auto-generated and written to your home directory as
   ".completions_slang", without syntaxes, of course.

                      4. FORMAT OF THE COMPLETIONS FILE

Each entry is on a line by itself. Line format is:

   target word :: [optional syntax for word] :: [optional help text for word]

I.e. three fields all delimited by two colons where the last two fields are
optional.

So in their simplest form, lines in the completions file may look like this:

   cave
   caveat emptor!

If these lines were the only two lines in the completion file, then typing
'c' and hitting the TAB key two or more times would alternate between
inserting the words on the two lines after the editing point. Typing e.g. the
space key after the word(s) has been inserted will confirm the insertion of
the completed word. Typing "cavea" + TAB would insert only "caveat emptor!".

Lines may also look like this:

   fopen :: (@@, )

In this case, after having completed "fopen" with TAB and confirmed its
insertion with the enter key, then the inserted line will look like

   fopen (, )

with the editing point being just before the comma, as the two at-signs have
been replaced by the editing point.

Or lines may look like this:

   _for :: i (0, @@, 1)\n{\n\n}

In this case, after having completed "_for" with TAB , then the inserted
line will expand to

   _for i (0, , 1)
   {

   }

with the editing point being just before the second comma.

A line may also look like this:

   read_with_completion :: (@@, , , , ) :: Void read_with_completion (String prt, String dflt, String s, Integer type)

The last field is a short help text, in this case explaining the syntax of
the function that may be shown in the message area upon completion.

A line may also look like this:

  .gcolor :: &groff_get_color_names(1) :: Set (glyph) drawing color

Here the second field, "&groff_get_color_names(1)", is a S-Lang function to
be executed upon completion, which is implied by prefixing the function name
with the "&" character.


                                 4.1 ALIASES

Using the single '@' character after the target word in the first field
means that the word is an alias. The alias word will not be inserted.
Thereby you can create mnemonic little snippets to be inserted. E.g.:

  duck@ :: Donald Duck\n1313 Webfoot Walk\nDuckburg\nCalisota.

Typing "duck" + TAB will then yield

  Donald Duck
  1313 Webfoot Walk
  Duckburg
  Calisota

as the newline escapes "\n" will be expanded.

                           4.2 INCLUDE OTHER FILES

In the completions file, you can include other files to complete from with
the "#INC" directive like this

  #INC /some/otherfile/to/include

                                  5. USAGE

These keys perform the following actions:

  - TAB: cycles through possible completions or inserts completed word and
         breaks cycle if there is only one completion. This key may be
         redefined (see section 5.1). If the character before the editing
         point is one of, ')', ']' or '}', this key will insert or delete
         any of these characters until they are balanced with their matching
         delimiters, '(', '[' or '{'.

         NOTE: If you have already fully typed the word you want to complete
               and this word forms the beginning of other words that are
               completion candidates, such as if you type "if" (which forms
               the beginning of "ifnot") and then hit <tab>, then nothing 
               happens but if you type <space>, the "if" construct will be
               expanded. Typing <tab> another time will complete to "ifnot".

  - Shift-Tab: In "C" and "SLang" modes, this will move the editing point
               two lines down and run the indent_line () function. Useful
               for quickly moving from a condition statement to a block
               between a pair of braces or to quickly move out from such a
               block.

  - <backspace>: breaks the cycle and returns you to the stub

  - <space>: breaks cycle and inserts completion plus possible syntax. If
             there is no syntax to be inserted, a space is inserted after
             the completed word.

  - <enter>: Like <space>, but does not insert a space after a completed
             word with no syntax attached.

  - any other key: breaks cycle and inserts the key pressed

  - F1: Shows help for word at point (if available).

  - F2: An "apropos" function that searches the help texts and returns
        the corresponding functions, if available.

  - ctrl-c c: Select a different completions file.

  - ctrl-c w: Append the word at point or marked words to the completions file.

You can redefine these keys in a mode hook.

Multi line constructs, including nested constructs will be automatically
indented upon insertion.

                        5.1 User Definable Variables

In your $HOME/.jedrc you can enter the following variables which modify the
behaviour of some of the functions like this, their default values are shown:

  variable Show_Help_Upon_Completion = 1;

This variable toggles the display of a help text in the message area upon
insertion of the completed word. 0 == off, 1 == on

  variable Completion_Key = "\t";

The completion key. Default is TAB.

  variable Wordchars = "\w"R;

This variable controls which characters that may be part of a word. This is
crucial as to what words you want completed.

  variable Extended_Wordchars = "-_";

This variable controls what other characters may be part of a word.

  variable Insert_Completion_Word = 1;

This variable controls whether or not the completion word itself should
be inserted into the buffer.

  variable Newl_Delim = "\\n";

This variable controls the delimiter to use for expanding newlines in
aliases and syntax.

  variable Tabcomplete_Use_Help = 1;

This variable controls whether to use the native help interface or not.
If you use the julia mode, you should set this to '0' as julia.sl defines
its own help interface.

  variable Use_Completion_Menu = 0;

This variable controls whether to use a pop up menu with completion
targets or to complete from or if completing from the editing point.
If this is enabled, completion in the minibuffer will be disabled.

  variable Sep_Fun_Par_With_Space = 0;

Should there be a space between function name and opening parenthesis
upon completion? E.g. strtok () vs. strtok(). Looping or conditional
keywords will always have a space. The julia language will not accept
spaces, so set it to 0 in that case.

  variable SLang_Completion_In_Minibuffer = 0;
  
Setting this variable in SLang mode to '1' will enable this utility's
completion at the minibuffer's S-Lang> cli prompt. Note that key (sequence)
bound to invoking the S-Lang> prompt is detected and if you have more than
one key (sequence) bound to invoking the prompt, it may not detect the one
you're actually using. In that case, check those key bindings and remove the
one(s) you're not using.

  variable Minimum_Completion_Word_Size = 2;

This variable controls the minimum size for words that are candidates for
completion. If completion is from a generic word list such as a list that
may be generated with the "aspell (..) dump master (..)" command, then
personally I prefer a rather large value such as e.g. 10 for this variable
so that the completion candidates will be limited to words that are
cumbersome to write and/or difficult to spell. I think it is especially
convenient if also the variable Use_Completion_Menu is set to 1.

All of these variables should first be entered globally in your ~/.jedrc
with your preferred default values (or no values) and then possibly fine
tuned with other values within a mode hook for that particular mode. E.g:

  variable Show_Help_Upon_Completion;
  variable SLang_Completion_In_Minibuffer;
  variable Tabcomplete_Use_Help;
  variable Extended_Wordchars;
  
  define slang_mode_hook ()
  {
    Extended_Wordchars = "_#%";
    Show_Help_Upon_Completion = 1;
    SLang_Completion_In_Minibuffer = 1;
    Tabcomplete_Use_Help = 1;
    init_tabcomplete ();
  }

PLEASE NOTE that the variables must come BEFORE the init_tabcomplete () function.

                    6. Create a Wordlist to Complete From

An easy way to make a word list of regular words to be completed from, is to
use a spell checkers' function to dump the master word list into a
completions file. E.g. with aspell:

  cd
  aspell -d fr dump master > .tabcomplete_fr

this would dump all words from aspell's French dictionary into the hidden
file ".tabcomplete_fr" in your home directory.

                       7. Use Tabcomplete With Aspell

If you have installed the aspell spell checking extension, then you may use
it to autoload completion files that match your spell checking language.
E.g., when writing emails, it is normal to write in different languages, so
if you also want to be able to complete words, it would be convenient to
have a completion file for e.g. English loaded when spell checking in that
language. In that case, you might configure this in the mailedit_mode_hook,
if you use Jed's mailedit.sl extension to edit your emails. In your ~/.jedrc: 

  variable Aspell_Use_Replacement_Wordlist;
  variable Aspell_Ask_Dictionary;
  variable Aspell_Use_Tabcompletion;
  
  define mailedit_mode_hook ()
  {
    Aspell_Use_Replacement_Wordlist = 1;
    Aspell_Ask_Dictionary = 1;
    Aspell_Use_Tabcompletion = 1;
    init_aspell ();
  }

Please note that the Aspell.* variables must PRECEDE the init_aspell ()
function in the mode hook and that these variables should already have been
defined outside the mode hook, first.

Normally, you would use the "init_tabcomplete ()" function in the mode hook
to load the tabcompletion functions, but in this case, you simply set the
variable, Aspell_Use_Tabcompletion, then a completions file,
"$HOME/.tabcompletion_$LANG" is loaded automatically, where $LANG
corresponds to your current spell checking dictionary. For English, the
hidden file would then be named ".tabcomplete_en" or ".tabcomplete_en_US"
for American English, residing in your home directory. These completion
files must of course be created first, see above.

For modes, i.e. programming language modes, where you don't want spell
checking, use the "init_tabcomplete ()" function in the mode hook instead to
load the tabcomplete functions.

The $LANG part should match as a substring of your current locale setting in
either one of the environment variables, $LANG, $LC_MESSAGES or $LC_ALL, e.g.
if the environment variable $LANG is set to "en_US.utf-8".


Send bug reports or suggestions to: Morten Bo Johansen, mortenbo at hotmail dot com
