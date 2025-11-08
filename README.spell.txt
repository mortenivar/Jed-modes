				 What is it?

spell.sl is an extension minor mode to the Jed editor to spell check the
current buffer, either as as you type along ("on the fly") or in one fell
swoop. Misspelled words will be highlighted in red by default.

It uses the enchant wrapper program by default which means that the mode
supports any of the spell checking backends that enchant supports. Among
These are:

  - aspell
  - hunspell
  - nuspell
  - voikko (for Finnish users)
  - zemberek (for Turkish users)

It may also bypass enchant and use aspell or hunspell on their own; see
below for the explanation of the "Spell_User_Cmd" variable. Unless you have
some very specific needs that are only covered with many of the singular
options that exist to aspell and hunspell, I recommend just using enchant.

For spell checking very, very large texts, it should be noted that aspell is
significantly faster than hunspell.


				Requirements:


- The enchant spell checking wrapper program.
   
- One or more of the above mentioned spell checking backends plus
  accompanying dictionaries.


				  Features:


- Spell check the whole buffer, highlighting misspelled words.

- Spell check as you type along ("on the fly")

- Change spelling dictionary in a running session

- Spell check with buffer-specific dictionaries in the same Jed session

- Menu with suggestions for corrections of a misspelled word

- Easily add words to user's personal word list

- Possibility to complete words with the tabcomplete extension

- Auto correction of typos/misspellings

- Go to next or previous misspelled word


				Installation:


Place spell.sl in a directory where jed will find it. Add the following line
to your ~/.jedrc:

  autoload("spell_init", "spell.sl");


Then activate the mode on a per-mode basis by running the "spell_init"
function from a mode hook in your ~/.jedrc, E.g.

  define text_mode_hook ()
  {
    spell_init ();
  }

which will load the mode whenever you edit a text file. You may also load it
with

  <alt>-x spell_init

                                   
				Basic Usage:
				   

When loading a file, with the mode activated, all misspelled or unrecognized
words will be highlighted at once, so you may quickly scroll through the
buffer and take a note of which are actual misspellings. Spotting a
misspelling, then use the "go to next/previous misspelled" function to
quickly jump to it. If you're in doubt about its correct spelling, use the
"suggest correction" function to have a menu with suggestions displayed and
pick the right correction to have the misspelled word replaced. If the word
is not an actual misspelling but rather just a word which is not recognized
by the spell checker, you may want to add it to your personal dictionary, so
that it does not appear as misspelled anymore. Otherwise, spell checking as
you type along ("on the fly") should ensure that you are always immediately
alerted to your spelling mistake.



			       Customization:


Also in ~/.jedrc, you may set some custom variables, exemplified here with
their default values:

  variable Spell_Extended_Wordchars = "";
  variable Spell_Dict = NULL;
  variable Spell_Ask_Dictionary = 0;
  variable Spell_Misspelled_Color = "red";
  variable Spell_Flyspell = 1;
  variable Spell_Use_Replacement_Wordlist = 0;
  variable Spell_Use_Tabcompletion = 0;
  variable Spell_Spellcheck_Buffer_On_Startup = 1;
  variable Spell_Personal_Dict = NULL;
  variable Spell_User_Cmd = NULL;
  variable Spell_Minimum_Wordsize = 1;
  variable Spell_Ignore_Words_Without_Vowels = 0;

First, set this block of variables globally in your ~/.jedrc with the
default values of your choice and then possibly adapt them individually in
one or more mode hooks. E.g.

  define mailedit_mode_hook ()
  {
    Spell_Ask_Dictionary = 1;
    spell_init ();
  }

which would load the mode when editing a mail message and prompt you for a
spelling dictionary on startup. Note that the Spell_Ask_Dictionary variable
precedes the spell_init() function. Also note that you do not use the
"variable" keyword within a mode hook, as it has already been defined
outside the mode hook.


		  The Variable, "Spell_Extended_Wordchars":
 

is something you may want to set if you want to include some non-standard
characters as part of a word.

  variable Spell_Extended_Wordchars = "_";

which would include the underscore character as part of a word.


			 The Variable, "Spell_Dict":


holds the value for the default spelling dictionary to use. If none is
specified, it will be set from the environment on startup in which case the
value is always the locale code consisting of the combination of the ISO
639-1 language code and the ISO 3166-1 country code, joined by an
underscore, e.g. "de_DE" for German. Hunspell's dictionaries all follow this
naming convention. Needless to say, the corresponding dictionary must be
installed. You may even specify multiple dictionaries to use at once,
separating them with commas, like
  
  Spell_Dict = "da_DK,de_DE,fr_FR";
    
if you had a text consisting of both Danish, German and French parts.

Note that this format only works with enchant and hunspell, if used on its
own. It doesn't work with aspell, if used on its own.

Also note, that if the variable, "Spell_User_Cmd" is set, setting this
variable will have only take effect if you change the dictionary in a
running session.


		    The Variable, "Spell_Ask_Dictionary":


may be set to 1 to prompt you for a dictionary on startup.  This is handy in
e.g. a mail_mode hook, where it is normal to write in different languages.
Again, with enchant and hunspell you may specify multiple dictionaries
separated with commas.


		   The Variable, "Spell_Misspelled_Color":


is the color of misspelled words and defaults to "red". You may change it to
any of the following:

  "black"        "gray"
  "red"          "brightred"
  "green"        "brightgreen"
  "brown"        "yellow"
  "blue"         "brightblue"
  "magenta"      "brightmagenta"
  "cyan"         "brightcyan"
  "lightgray"    "white"
  "default"


		       The Variable, "Spell_Flyspell"


may be set to 1 to have misspelled words highlighted as you type along. 0 to
turn it off. It defaults to 1.


	       The Variable, "Spell_Use_Replacement_Wordlist":


may be set to 1 to have e.g. "too-fast-fingers-for-their-own-good"
misspellings, like typing "teh" instead of "the", auto corrected while
typing. It defaults to 0. For this you must maintain a list of misspellings
and their accompanying corrections in the hidden file, ".spell_repl.$DICT",
residing in you home directory, where $DICT denotes the language code of the
dictionary in use as described above. So, for the English language, the file
might be named ".spell_repl.en_US" or some other variant that you happen to
use. You may always see that code in the status line. The format of this
file is simply the misspelling to be auto corrected followed by a colon and
followed by the correction word or words, each on a line by itself, e.g.

  ..
  becuase:because
  ..
  teh:the
  thnaks:thanks
  thsi:this
  ..

You may of course also use it to expand abbreviations or mnemonics, e.g.

  mbj:Morten Bo Johansen

<space> or <return> triggers the function

Hint: The codespell program has a huge dictionary of common misspellings in
the English language and their corrections listed pairwise:

  https://raw.githubusercontent.com/codespell-project/codespell/refs/heads/main/codespell_lib/data/dictionary.txt

you may simply download that file and then do:

  sed 's/->/:/' dictionary.txt >> ~/.spell_repl.en_US

to enable the auto-correction of about 61.000 misspellings.

If you use other variants of the English dictionaries, then just create a
symbolic link to them, e.g.
  
  ln -s ~/.spell_repl.en_US ~/.spell_repl.en_GB


		  The Variable, "Spell_Use_Tabcompletion":


may be used to complete words, if you have the "tabcomplete" extension from
  
  https://jedmodes.sourceforge.io/mode/tabcomplete.html
  
installed. The name and location of the files to complete from are
~/.tabcomplete_$DICT where $DICT is the locale code as described above. So,
with French as an example, it would be ~/.tabcomplete_fr_FR. Note that it
is a hidden file. In order to populate the file with words to complete from
do:
  
  (for aspell): aspell dump master fr_FR > ~/.tabcomplete_fr_FR 

  (for hunspell): install the "hunspell-reader" program
  
    sudo npm install -g hunspell-reader
    
and then do
  
  hunspell-reader words -u /usr/share/hunspell/fr_FR.dic > ~/.tabcomplete_fr_FR
  
Please note that you should not use the "init_tabcomplete ()" function in a
mode hook in this case, but rather just set the variable
"Spell_Use_Tabcompletion = 1" in the mode hook.
  
Note, that if you use multiple dictionaries, it will be turned off
regardless.

Look at the README file for the tabcomplete extension to learn about some
settings relating to that extension.


	     The Variable, "Spell_Spellcheck_Buffer_On_Startup"


determines if spell checking will be performed on the buffer immediately
after it is loaded. The default is yes.


		    The Variable, "Spell_Personal_Dict":


holds the file name for a personal dictionary of choice. The mode
automatically sets this to the name of the dictionary being used, residing
in either the directory specified in the environment variable
ENCHANT_CONFIG_DIR and if this variable is not set, then to the directory
specified in the environment variable ${XDG_CONFIG_HOME}/enchant where
XDG_CONFIG_HOME usually resolves to ~/.config/.

If aspell is used on its own without enchant, then the name of personal
dictionary file defaults to ~/.aspell.$dict.pws, where $dict is the
dictionary currently in use.

With enchant, you may set it to anything you want on a per-mode basis.

Note, that aspell's and enchant/hunspell's personal dictionary formats are
incompatible.


		       The Variable, "Spell_User_Cmd":


is a custom spell checking command you may set. It will override the setting
from the mode. You may use that to e.g. use an aspell custom command instead
of enchant. A command like e.g.
  
  Spell_User_Cmd = "aspell --sug-mode=bad-spellers --ignore=4 --run-together -d da -a"

or any other options you may want to pass to aspell will be perfectly fine.
You may set this on a per-mode basis in a mode hook. Note that the "-d
<dictionary>" and "-a" options must always be present.


		   The Variable, "Spell_Minimum_Wordsize":


holds the threshold value for the length of words below or equal to which
you don't want them checked. The value defaults to '1'.


	     The Variable, "Spell_Ignore_Words_Without_Vowels":


as the name says, will exclude words that consist only of consonants from
being checked. It defaults to '0' (disabled)

All of these variables may be redefined in a mode hook.


		     Setting the Spell Checking Backend:
		     

You may set your preferred spell checking backends on a per-language basis. See

   man 5 enchant
   
on how to do that.   


			    Keybindings and Menu:


There are seven user functions that are tied to keys:

- spell_add_word_to_personal_dict: <ctrl>-c a

    adds word behind or under cursor to the personal dictionary for the
    current language used. Its color highlighting is removed

- spell_buffer: <ctrl>-c b

    spell check the current buffer, highlighting misspelled words

- spell_select_dictionary: <ctrl>-c d

    change the spelling dictionary. A menu with all installed dictionaries
    will pop up. You may specify more than one dictionary, separating them
    with commas

- spell_suggest_correction: <ctrl>-c s

    query for a spelling suggestion and possibly replace word

- spell_remove_word_highligtning: <ctrl>-c R

    remove color highlighting from a word

- spell_goto_misspelled: <shift>-<down>

- spell_goto_misspelled: <shift>-<up>

    go to the next or previous misspelled word. It only works after having
    spell checked the entire buffer. The default key binding <shift>-up/down
    may or may not work

These functions are also available from the menu:

  F10 -> System -> Spell

<ctrl>-c is the reserved key prefix in this case. You may have it
set to something else.

All of the key bindings above may be redefined in a mode hook if they are
inconvenient, e.g.:

  define text_mode_hook ()
  {
    unsetkey_reserved ("n");
    setkey_reserved ("spell_goto_misspelled\(1\)", "n");
    spell_init ();
  }

would redefine the keybinding for going to the next misspelled word to
<ctrl>-c n


	      Spell Checking a Buffer Without Loading the Mode:


The spell_buffer functions may also be used without loading the entire minor
mode. In your ~/.jedrc insert

  autoload("spell_buffer", "spell");
  add_completion("spell_buffer");
  
and then bind the spell_buffer function to some key in your global key map.
or use, alt-x spell_buffer


			      The Status Line:


If the mode is activated, the status line will always show the spell
checking backend currently in use and the dictionary. It will also show if
flyspelling and tabcompletion are enabled. In my case, it may look like this

  +-(0) t.txt (Text da_DK (hunspell)|fly|tabcomplete abbrev)   1/252,1    10:25pm

showing that I am using the "da_DK" dictionary with hunspell as the spell
checking backend and flyspelling and tabcompletion are enabled.

Note, that with multiple dictionaries specified, the spell checking backend
will be returned by enchant as "Personal Wordlist".


		   Spell Checking Programming Source Code:


The minor mode should not be enabled for source code files, but if you
enable the "spell_buffer()" function globally as described above, you may
use <alt>-x spell_buffer on source code files. The function in that case
isolates comments and strings and then runs the spell checker on those so
that the source code itself is omitted from the check. The buffer is put in
"no_mode" to remove the syntax highlighting from the language mode, so after
the check you must put it back in c_mode or whatever you came from. It is
not 100% clean. Especially, if you have source code which is commented out,
it will be checked and some irrelevant words are then likely to be
highlighted as misspelled. But in many cases, it will give a good, quick
overview.

Send bug reports or suggestions to: <mortenbo at hotmail dot com>
