                                 What is it?

aspell.sl is an extension minor mode to the jed editor to spell check the
current buffer as you type along ("on the fly").  Misspelled words will be
highlighted in red by default. It borrows some ideas from flyspell.sl
from jedmodes, but adds some other functions and is also a little less
complicated to set up, in part because it supports Aspell only.

                                 Facilities

- Spell check the whole buffer, highlighting misspelled words.

- Spell check a region, highlighting misspelled words.

- Spell check ("flyspelling") as you type along ("on the fly")

- Change Aspell dictionary in a running session

- Spell check with buffer-specific dictionaries in the same Jed session

- Menu with suggestions for corrections of a misspelled word

- Add words to Aspell's personal word list

- Possibility to complete words with the tabcomplete extension

- Auto correction of typos

- Go to next or previous misspelled word

                                 Installation:

Place aspell.sl in a directory where jed will find it. Add the following
line to your ~/.jedrc:

  autoload ("init_aspell", "aspell.sl");

 You use it by running the "init_aspell" function from a mode hook in your
 ~/.jedrc, E.g.

  define text_mode_hook ()
  {
    init_aspell ();
  }

which will load the mode whenever you edit a text file, or load it with

  alt-x init_aspell

Also in ~/.jedrc, you may set some customizable variables, exemplified here:
with their default values

  variable Aspell_Extended_Wordchars = "";
  variable Aspell_Dict = "" ;
  variable Aspell_Ask_Dictionary = 0;
  variable Aspell_Typo_Color = "red";
  variable Aspell_Flyspell = 1;
  variable Aspell_Use_Replacement_Wordlist = 0;
  variable Aspell_Use_Tabcompletion = 0;
  variable Aspell_Accept_Compound_Words = 0;
  variable Aspell_Suggestion_Mode = "fast";
  variable Aspell_Spellcheck_Buffer_On_Startup = 1;
  variable Aspell_Show_Suggestions_Goto_Misspelled = 0;

First, set this block of variables globally in your ~/.jedrc with the
default values of your choice and then possibly adapt them individually in
one or more mode hooks. E.g.

  define mailedit_mode_hook ()
  {
    Aspell_Ask_Dictionary = 1;
    init_aspell ();
  }

which would load the mode when editing a mail message and prompt you for a
spelling dictionary on start up. Note that the Aspell_Ask_Dictionary
variable precedes the init_aspell() function. Also note that you do not use
the "variable" keyword within a mode hook, as it has already been defined
outside the mode hook.

- The first variable, "Aspell_Extended_Wordchars", is something you may
  want to set if you want to include some non-standard characters as part of
  a word.

    variable Extended_Wordchars = "_";

  which would include the underscore character as part of a word.

- The second variable, "Aspell_Dict", denotes the default spelling
  dictionary to use. If none is specified, it will be set from the
  environment on startup. The value is always the two letter ISO-639-1 code
  for a language, e.g. "de" for German or this code plus the ISO-3166
  country code in upper case joined by an underscore, like "de_AT" for
  Austrian German. Needless to say, the corresponding Aspell dictionary must
  be installed.

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
  instead of "the", auto corrected while typing. It defaults to 0. For this
  you must maintain a list of typos and their accompanying corrections in
  the hidden file, ".aspell_repl.$LANG", residing in you home directory,
  where $LANG denotes the language code of the aspell dictionary. So, for
  the English language, the file might be named ".aspell_repl.en" or
  ".aspell_repl.en_US" or some other variant that you happen to use. You
  may see that code in the status line. The format of this file is simply
  the typo to be auto corrected followed by a colon and followed by the
  correction word or words, each on a line by itself, e.g.

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

  When querying for a suggestion to a misspelling and accepting it as a
  correction, you will be asked if you want to add the pair of the
  misspelling and the correction to the replacement word list so that the
  misspelling is auto-corrected in the future.

  Hint: The codespell program has a huge dictionary of common misspellings in
        the English language and their corrections listed pairwise:

           https://raw.githubusercontent.com/codespell-project/codespell/refs/heads/main/codespell_lib/data/dictionary.txt

        you may simply download that file and then do:

           sed 's/->/:/' dictionary.txt >> ~/.aspell_repl.en

        to enable the auto-correction of about 61.000 misspellings.

- The seventh variable, "Aspell_Use_Tabcompletion", may be used to complete
  words, if you have the "tabcomplete" extension from,
  https://jedmodes.sourceforge.io/mode/tabcomplete, installed. Look at the
  file, README.tabcomplete.txt, to see how to create a language specific
  word list to complete from. Please note that you should not use the
  "init_tabcomplete ()" function in a mode hook in this case, but rather
  just set the variable "Aspell_Use_Tabcompletion = 1" in the mode hook.

- The eight variable, "Aspell_Accept_Compound_Words", determines whether
  words strung together from two or more words should be regarded as
  correctly spelled if their individual parts are correctly spelled. Whether
  or not this has any effect relies on the "run-together" option in the
  Aspell language data file, <lang>.dat, typically residing in
  /usr/lib/aspell-<version>/<lang>.dat For e.g. the Danish language, this
  option is set to "true" and therefore words that are strung together from
  two or more individually correctly spelled words are accepted as correctly
  spelled. For most languages, it won't have any effect.

- The ninth variable, "Aspell_Suggestion_Mode", can be used to change the
  mode in which Aspell suggests corrections to a misspelled word. It may be
  set, with an increasing degree of thoroughness in finding suggestions, to
  any of "ultra", "fast", "normal", "slow" and "bad-speller". It defaults to
  "fast". If suggestions with this value are poor, try with e.g. "normal" or
  "slow".

- The tenth variable, "Aspell_Spellcheck_Buffer_On_Startup", determines
  if spell checking will be performed on the buffer immediately after it
  is loaded.

- The eleventh variable, "Aspell_Show_Suggestions_Goto_Misspelled", if
  enabled, will show the menu for Aspell's  suggestions for correcting a
  misspelled word whenever you go to the next or previous misspelled word.


All of these eleven variables may be redefined in a mode hook.

                                   Usage:

There are ten user functions that are tied to keys:

  - add_word_to_personal_wordlist: ctrl-c a

    (adds word behind or under cursor to the personal Aspell dictionary for
     the current language used. Its color highlighting is removed)

  - aspell_buffer: <ctrl>-c b

    (spell check the current buffer, highlighting misspelled words)

  - select_aspell_dictionary: <ctrl>-c d

    (change the spelling dictionary)

  - aspell_set_suggestion_mode: <ctrl>-c S

    (set the algorithm that Aspell uses to suggest corrections)

  - aspell_suggest_correction: <ctrl>-c s

    (query Aspell for a spelling suggestion and possibly replace word)

  - toggle_aspell_flyspell: <ctrl>-c t

    (toggle spell checking on the fly on or off)

  - aspell_remove_word_highligtning: <ctrl>-c R

    (remove color highlighting from a word)

  - aspell_flyspell_region: <ctrl>-c r

    (spell check a marked region) 

  - aspell_goto_misspelled: <shift>-<down>

  - aspell_goto_misspelled: <shift>-<up>

    (go to the next or previous misspelled word. It only works after having
     spell checked the entire buffer. It doesn't work with spell checking a
     region)

These functions are also available from the menu:

  F10 -> System -> Aspell

<ctrl>-c is the reserved key prefix in this case. You may have it
set to something else.

All of the key bindings above may be redefined in a mode hook if they
are inconvenient, e.g.:

  define text_mode_hook ()
  {
    unsetkey_reserved ("n");
    setkey_reserved ("aspell_goto_misspelled\(1\)", "n");
    init_aspell ();
  }

would redefine the keybinding for going to the next misspelled word
to <ctrl>-c n

The aspell_buffer functions may also be used without loading the entire
minor mode. In your ~/.jedrc insert

  autoload ("aspell_buffer", "aspell");

and then bind the aspell_buffer function to some key in your global key map.


If the mode is activated, the status line will show, e.g.

  (Jed pre0.99.20-143U) Emacs: t.txt (Text aspell[de|fly] abbrev)  1/2,1  [15:25]

i.e. if you use it in text_mode, "aspell[de]", is shown in the status line
with the current spelling dictionary/language between the brackets, in this
case "de" for German.

                        Use Aspell With Tabcomplete:

This is an extension from jedmodes.sourceforge.io that you may use to e.g.
complete words, by default with the <tab> key. So, if your Aspell spelling
dictionary is "en_US", you could create a completion dictionary of words,
being in you home directory, with this command

  aspell dump master en_US > .tabcomplete_en_US

as the name format of this file is

  .tabcomplete_<aspell-dicitonary>

You can see what dictionary you are currently using in the status line.

This would create this file with all the words from the American English
aspell dictionary. Then in a Jed buffer with aspell loaded, type the first
few characters of a possibly difficult word to spell, like "extrat" and then
<tab> a few times to complete to the somewhat difficult word
"extraterritoriality"

The completion file will be loaded automatically based on the
Aspell dictionary you use.

You load it from a mode hook by first setting this variable in your ~/.jedrc:

    variable Aspell_Use_Tabcompletion;

E.g. if you use Jed's mailedit.sl extension to edit your emails, then in
your ~/.jedrc do

  define mailedit_mode_hook ()
  {
    Aspell_Use_Tabcompletion = 1;
    init_aspell ();
  }

Please note that the Aspell.* variables must PRECEDE the init_aspell ()
function in the mode hook, first.

                                Limitations:

  - The mode supports Aspell only - as the name suggests!

  - Highlighting of misspelled words is limited to words of a length of at
    most 48 bytes. Not sure if that is much of a problem, but in languages
    whose alphabets consist mostly or entirely of multibyte characters, some
    words may exceed the limit and not be checked.

  - Syntax highlighting for misspelled words containing multibyte characters
    is not working very well in Jed versions prior to "pre0.99.20-143", so
    in particular, if you use a language with such characters, you should
    consider upgrading, if necessary.

  - Jumping between misspellings does not work with region spell checking  

Send bug reports or suggestions to: <mortenbo at hotmail dot com>
