                                 What is it?

aspell.sl is an extension minor mode to the jed editor to spell check the
current buffer as you type along ("on the fly").  Misspelled words will be
highlighted in red by default.  It borrows some ideas from flyspell.sl
from jedmodes, but adds some other functions and is also a little less
complicated to set up, in part because it supports aspell only.

                                 Installation:

Place aspell.sl in a directory where jed will find it. Add the following
line to your ~/.jedrc:

  autoload ("init_aspell", "aspell.sl");

Also in ~/.jedrc, you may set some customizable variables, exemplified here:

  variable Extended_Wordchars = "_";
  variable Aspell_Dict = "da" ;
  variable Aspell_Ask_Dictionary = 0;
  variable Aspell_Typo_Color = "red";
  variable Aspell_Flyspell = 1;
  variable Aspell_Use_Replacement_Wordlist = 0;
  variable Aspell_Use_Tabcompletion = 0;
  variable Aspell_Accept_Compound_Words = 1;

First, set this block of variables globally in your ~/.jedrc and then adapt
them individually in one or more mode hooks.

- The first variable, "Extended_Wordchars", is something you may
  want to set if you want to include some non-standard characters as part of
  a word.

    variable Extended_Wordchars = "_";

  which would include the underscore character as part of a word.

- The second variable, "Aspell_Dict", denotes the default spelling
  dictionary to use, but it is already set from the environment on startup.
  The value is always the two letter ISO-639-1 code for a language, e.g.
  "de" for German or this code plus the ISO-3166 country code in upper case
  joined by an underscore, like "de_AT" for Austrian German. Needless to
  say, the corresponding aspell dictionary must be installed, e.g.

   apt-get install aspell-de

  which would install the German aspell dictionary.

- The third variable, "Aspell_Ask_Dictionary", may be set to 1 to prompt
  you for a dictionary on startup.  This is handy in e.g. a mail_mode hook,
  where it is normal to write in different languages.

- The fourth variable, "Aspell_Typo_Color", is the color of misspelled words
  and defaults to "red". You may change it to any of the following:

    "black"        "gray"
    "red"          "brightred"
    "green"        "brightgreen"
    "brown"        "yellow"
    "blue"         "brightblue"
    "magenta"      "brightmagenta"
    "cyan"         "brightcyan"
    "lightgray"    "white"
    "default"

- The fifth variable, "Aspell_Flyspell", may be set to 1 to have misspelled
  words highlighted as you type along. 0 to turn it off. It defaults to 1.

- The sixth variable, "Aspell_Use_Replacement_Wordlist", may be set to 1 to
  have e.g. "too-fast-fingers-for-their-own-good"-typos, like typing "teh"
  instead of "the", autocorrected while typing. It defaults to 0. For this
  you must maintain a list of typos and their accompanying corrections in
  the file, ".aspell_repl.$LANG", residing in you home directory, where
  $LANG denotes the two-letter ISO-639-1 code for your language. So, for the
  English language, the file would be named ".aspell_repl.en". The format of
  this file is simply the typo to be autocorrected followed by a space and
  followed by the correction word, each on a line by itself, e.g.

  ..
  becuase because
  ..
  teh the
  thnaks thanks
  thsi this
  ..

- The seventh variable, "Aspell_Use_Tabcompletion", may be used to complete
  words, if you have the "tabcomplete" extension from,
  https://jedmodes.sourceforge.io/mode/tabcomplete, installed. Look at the
  file, README.tabcomplete.txt, to see how to create a language specific
  word list to complete from. Please note that you should not use the
  "init_tabcomplete ()" function in a mode hook in this case, but rather
  just set the variable "Aspell_Use_Tabcompletion = 1" in the mode hook.

- The eight variable, "Aspell_Accept_Compound_Words", determines whether
  words strung together from two or more words should be regarded as
  correctly spelled if their individual parts are correctly spelled. If
  this causes problems in some languages, then set this to '0'.
  
All of these eight variables may be redefined in a mode hook.

Also in ~/.jedrc it is necessary to add the following line(s) to one or more
mode hooks for which you want spell checking, e.g.

  define text_mode_hook ()
  {
    Aspell_Use_Replacement_Wordlist = 1;
    init_aspell ();
  }

Please note that you must set the aspell custom variables BEFORE running the
init_aspell () function.

                                   Usage:

There are five user functions that are tied to keys:

  - add_word_to_personal_wordlist: ctrl-c a

    (adds word behind or under cursor to the personal aspell dictionary for
     the current language used)

  - aspell_buffer: ctrl-c b

    (spell check the current buffer, highlighting misspelled words)

  - select_aspell_dictionary: ctrl-c d

    (change the spelling dictionary)

  - aspell_suggest_correction: ctrl-c s

    (query aspell for a spelling suggestion and possibly replace word)

  - toggle_aspell_flyspell: ctrl-c t

    (toggle spell checking on the fly on or off)

These functions are also available from the menu:

  F10 -> System -> Aspell

The aspell_buffer functions may also be used without loading the entire
minor mode. In your ~/.jedrc insert

  autoload ("aspell_buffer", "aspell.sl");

and then bind the aspell_buffer function to some key in your global key map.

All of the key bindings above may be redefined in a mode hook if they
are inconvenient, e.g.:

  define text_mode_hook ()
  {
    init_aspell ();
    local_unsetkey_reserved ("i");
    local_setkey_reserved ("select_aspell_dictionary", "i");
  }

would redefine the keybinding for selecting a spelling dictionary to
ctrl-c i

If the mode is activated, the status line will show, e.g.

  (Jed pre0.99.20-143U) Emacs: t.txt (Text aspell[de|fly] abbrev)  1/2,1  [15:25]

i.e. if you use it in text_mode, "aspell[de]", is shown in the status line
with the current spelling dictionary/language between the brackets, in this
case "de" for German.

                         Use Aspell With Tabcomplete:

If you have installed the tabcomplete extension from
jedmodes.sourceforge.io, then you may use it to autoload completion files
that match your spell checking language. E.g., when writing emails, it is
normal to write in different languages, so if you also want to be able to
complete words, it would be convenient to have a completion file for e.g.
English loaded when spell checking in that language. In that case, you might
configure this in the mailedit_mode_hook, if you use Jed's mailedit.sl
extension to edit your emails:

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

Normally, you would use the "init_tabcomplete ()" function in the mode hook to
load the tabcompletion functions, but in this case, you simply set the
variable, Aspell_Use_Tabcompletion, then a completions file,
"$HOME/.tabcompletion_$LANG" is loaded automatically, where $LANG corresponds
to your current spell checking dictionary. For English, the hidden file would
then be named ".tabcomplete_en", residing in your home directory.

                                Limitations:

  - The mode supports aspell only - as the name suggests!

  - You may only spell check in one language at a time, so having e.g. two
    buffers open in the same jed session and wanting to spell check in one
    separate language for each, won't work.

  - Highlighting of misspelled words is limited to words of a length of at
    most 48 bytes. Not sure if that is much of a problem, but in languages
    whose alphabets consist mostly or entirely of multibyte characters, some
    words may exceed the limit and not be checked.

  - Syntax highlighting for misspelled words containing multibyte characters
    is not working very well in Jed versions prior to "pre0.99.20-143", so
    in particular, if you use a language with such characters, you should
    consider upgrading, if necessary.

Send bug reports or suggestions to:

    Morten Bo Johansen <listmail at mbjnet dot dk>
