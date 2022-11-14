% _debug_info=1;_traceback=1;_slangtrace=1;
%% groff_mode.sl - a Jed editing mode for nroff/troff/groff files
%% 
%% Copyright: Morten Bo Johansen <mbj@mbjnet.dk>
%% License: http://www.fsf.org/copyleft/gpl.html
%%
%% $Log: groff_mode.sl,v $
%% Revision 1.0  2018/02/14 19:51:20  mojo
%% - Initial version
%% Revision 1.1  2018/10/27 20:32:37  mojo
%% - When selecting from completions, pop up window w/completions
%% 
custom_variable ("Groff_Pdf_Viewer", "zathura");
custom_variable ("Groff_Cmd", "groff -G -g -e -p -t -Tps -k -K utf-8 -dpaper=a4 -P-pa4");

ifnot (is_defined ("Key_Shift_Tab"))
 () = evalfile ("keydefs");
ifnot (is_defined ("PCRE_CASELESS"))
 () = evalfile ("pcre");

private variable
  Inst_Prefix = "",
  Version = "1.1",
  Mode = "groff",
  pdf_file = path_basename_sans_extname (buffer_filename) + ".pdf",
  tmpfile = make_tmp_file (buffer_filename),
  ext = strtrim_beg (path_extname (buffer_filename ()), "."),
  MP = "-" + ext,
  macro_packages = ["-mm","-me","-ms","-mdoc","-mom","-man", "-mandoc", "-www"],
  % manpage_compile_cmd = "groff -t -e -mdoc -Tps -k -K utf-8 -dpaper=a4 -P-pa4",
  manpage_compile_cmd,
  man_exts = ["mdoc","man","1","2","3","4","5","6","7","8"];

ifnot (NULL == search_path_for_file (getenv ("PATH"), "mandoc", path_get_delimiter ()))
  manpage_compile_cmd = "mandoc -T pdf";
else
  manpage_compile_cmd = "groff -t -e -mdoc -Tps -k -K utf-8 -dpaper=a4 -P-pa4";


ifnot (any (macro_packages == MP))
 MP = "";

% man page extensions
if (any (man_exts == ext))
 MP = "-mdoc";

% Where is groff installed.
if (2 == file_status ("/usr/share/groff"))
 Inst_Prefix = "/usr/share/groff";
else if (2 == file_status ("/usr/local/share/groff"))
 Inst_Prefix = "/usr/local/share/groff";
else
 throw RunTimeError, "no groff installation in either /usr or /usr/local"; 

% Run a shell command
private define run_system_cmd (cmd)
{
  ifnot (0 == system ("$cmd >/dev/null 2>&1"$))
    throw RunTimeError, "$cmd failed"$;
}

% Edit and set the groff command used to compile the document
define edit_groff_cmd ()
{
  if (any (man_exts == ext))
    manpage_compile_cmd = read_mini ("Edit Groff Cmd:", "", manpage_compile_cmd);
  else
    Groff_Cmd = read_mini ("Edit Groff Cmd:", "", Groff_Cmd);
}

% Check if a line matches a regular expression pattern
private define re_line_match (pat, trim)
{
  push_spot ();
  variable line = line_as_string ();
  
  if (trim)
    line = strtrim (line);
  
  string_match (line, pat, 1);
  pop_spot ();
}

% Determine if we are between a pair of macros.
private define is_between_macros (beg_tag, end_tag)
{
  variable ibm = 0;

  CASE_SEARCH = 1;

  push_spot ();

  do
  {
    bol ();

    if ((looking_at (beg_tag)) || (looking_at (end_tag)))
    {
      if (looking_at (end_tag))
        ibm = 0;
      else if (looking_at (beg_tag))
        ibm = 1;
      else
        ibm = 0;

      break;
    }
  }
  while (up (1));

  pop_spot ();
  return ibm;
}

private define mark_word ()
{
  while (not (re_looking_at ("[ \t]")) && not (bolp ()))
  {
    ifnot (left (1))
      break;
  }

  if (re_looking_at ("^\\.[a-zA-Z][a-zA-Z] ")) % groff request or macro
    return;
  
  skip_non_word_chars ();
  push_visible_mark ();
  skip_word_chars ();
}

% Look for a program in a list of programs delimited by a space and
% use the first one found
private define find_prgs_use_first (prgs)
{
  variable 
    prgs_arr = strtok (prgs),
    path = getenv ("PATH");
  
  prgs_arr = prgs_arr[wherenot (_isnull (array_map (String_Type,
                                                    &search_path_for_file,
                                                    path, prgs_arr)))];
  ifnot (length (prgs_arr))
    throw RunTimeError, "Error: You must install one of $prgs"$;
  else
    return prgs_arr[0];
}

define t ()
{
  % ifnot (NULL == search_path_for_file ("/usr/bin:/usr/local/bin", "mandoc"))
  ifnot (NULL == search_path_for_file (getenv ("PATH"), "mandoc", path_get_delimiter ()))
    flush ("fff");
}

% How is a paragraph interpreted. From jed's nroff mode
define groff_parsep ()
{
  bol ();
  (looking_at_char ('.') or looking_at_char ('\\') or (skip_white (), eolp ()));
}

% Return the first line of a file
private define get_1st_line (file)
{
  variable fp, line = "";
  
  fp = fopen (file, "r");
  
  if (fp == NULL)
    return "";
  
  () = fgets (&line, fp);
  
  return line;
}

% Return names of installed Groff fonts.
private define get_font_names ()
{
  variable
    fontdir = "",
    fontfile = "",
    first_lines = [""],
    groff_fonts_user_dir = "",
    fontdirs = [""],
    fontfiles = [""];
  
  if (NULL != getenv ("GROFF_FONT_PATH"))
    groff_fonts_user_dir = getenv ("GROFF_FONT_PATH");
  
  fontdirs = ["${Inst_Prefix}/site-font/devps"$,
              "${Inst_Prefix}/current/font/devps"$,
              "${groff_fonts_user_dir}/devps"$];
  
  % include only existing directories in the array
  fontdirs = fontdirs[where (array_map (Int_Type, &file_status, fontdirs) == 2)];
  
  ifnot (length (fontdirs))
    throw RunTimeError, "none of the designated font directories exist";
  
  foreach fontdir (fontdirs)
    fontfiles = [fontfiles, array_map (String_Type, &dircat, fontdir, listdir (fontdir))];;

  first_lines = array_map (String_Type, &get_1st_line, fontfiles);
  % only Groff font files
  fontfiles = fontfiles[where (array_map (Int_Type, &string_match, first_lines, "GNU afmtodit", 1))];
  fontfiles = array_map (String_Type, &path_basename, fontfiles);
  
  ifnot (length (fontfiles))
    throw RunTimeError, "no Groff fonts found";
  
  fontfiles = fontfiles[array_sort (fontfiles)];
  
  return strjoin (fontfiles, ",");
}

% Insert a font name from a list of installed fonts
define insert_font_name ()
{
  ungetkey ('\t');
  insert (read_with_completion (get_font_names (), "Font:", "H", "", 's'));
}

%% Convert a truetype or open font type font to a groff font and make it
%% available to groff. It uses the environment variable
%% GROFF_FONT_PATH as the installation target.
define install_groff_font ()
{
  variable groff_fonts_user_dir = getenv ("GROFF_FONT_PATH");
  
  if (NULL == groff_fonts_user_dir || 0 == strlen (groff_fonts_user_dir))
    throw RunTimeError, "environment variable GROFF_FONT_PATH not set";
  
  ifnot (2 == file_status (groff_fonts_user_dir))
  {
    if (1 == get_y_or_n ("the directory \"$groff_fonts_user_dir\" does not exist, create it?"$))
      run_system_cmd ("mkdir -p $groff_fonts_user_dir"$);
    else
      throw RunTimeError, "aborting font installation!";
  }
  
  % The user defined font path should include only one directory. If it
  % contains more, then use the first one in the list.
  if (length (strchop (groff_fonts_user_dir, path_get_delimiter (), 0)) > 1)
  {
    groff_fonts_user_dir = strchop (groff_fonts_user_dir, path_get_delimiter (), 0)[0];
    flush ("using $groff_fonts_user_dir for font installation"$);
    sleep (1);
  }
  
  if (-1 == access (groff_fonts_user_dir, W_OK))
    throw RunTimeError, "you don't have write access to $groff_fonts_user_dir"$;
  
  variable font = "";
  
  ifnot (_NARGS)
    font = read_with_completion ("Font to install:", "", "", 'f');
  else
    font = ();
  
  ifnot (1 == file_status (font))
    throw RunTimeError, "$font does not exist or is not file"$;
  
  variable
    pwd = getcwd (),
    path = getenv ("PATH"),
    convertdir_files = [""],
    afmfile_arr = [""],
    afmtodit_opts = "",
    groff_font = "",
    fam_name = "",
    style = "R",
    styles = [""],
    afm_file = "",
    t42_file = "",
    pfa_file = "",
    devps_dl_str = "",
    devpdf_dl_str = "",
    textmap = dircat (Inst_Prefix, "current/font/devps/generate/textmap"),
    devps_dir = dircat (groff_fonts_user_dir, "devps"),
    devpdf_dir = dircat (groff_fonts_user_dir, "devpdf"),    devps_dl_file = dircat (devps_dir, "download"),
    devpdf_dl_file = dircat (devpdf_dir, "download"),
    convert_dir = make_tmp_file ("/tmp/fontinstall"),
    pe_file = dircat (convert_dir, "convert.pe"),
    font_sans_extname = path_basename_sans_extname (font),
    pe_str = "Open ($1);\nGenerate($fontname + \".pfa\");\nGenerate(\$fontname + \".t42\");",
    Styles = Assoc_Type[String_Type, ""];
  
    Styles["extrabolditalic"] = "EBI",
    Styles["semibolditalic"] = "SBI",
    Styles["mediumitalic"] = "MI",
    Styles["heavyitalic"] = "HI",
    Styles["lightitalic"] = "LI",
    Styles["blackitalic"] = "BLI",
    Styles["thinitalic"] = "TI",
    Styles["extralight"] = "EL",
    Styles["extrabold"] = "EB",
    Styles["boldoblique"] = "BO",
    Styles["bolditalic"] = "BI",
    Styles["demibold"] = "DB",
    Styles["semibold"] = "SB",
    Styles["regular"] = "R",
    Styles["oblique"] = "O",
    Styles["medium"] = "M",
    Styles["italic"] = "I",
    Styles["black"] = "BL",
    Styles["heavy"] = "H",
    Styles["light"] = "L",
    Styles["thin"] = "T",
    Styles["bold"] = "B";

  try
  {
    if (NULL == search_path_for_file (path, "fontforge"))
      throw OpenError, "fontforge is not installed"$;
    
    ifnot (1 == file_status (textmap))
      throw OpenError, "textmap file not found"; 
    
    if (-1 == mkdir (convert_dir, 0755))
      throw WriteError, "could not create $convert_dir"$;
    
    if (-1 == write_string_to_file (pe_str, pe_file))
      throw WriteError, "could not write to $pe_file"$;
    
    if (-1 == chdir (convert_dir))
      throw RunTimeError, "could not change to $convert_dir"$;
      
    styles = assoc_get_keys (Styles);
  
    % find a suitable font style abbreviation associated with font's style
    foreach style (styles)
    {
      if (pcre_exec (pcre_compile ("[_-]$style\.(otf|ttf)$"$, PCRE_CASELESS), font))
      {
        style = Styles[style];
        break;
      }
      else
        style = "R";
    }
 
    style = strup (read_with_completion ("R,B,I,BI", "Font Style for $font_sans_extname:"$, style, "", 's'));
    
    if (style == "I" or style == "O")
      afmtodit_opts = "-e text.enc -i50";
    else
      afmtodit_opts = "-e text.enc -i0 -m";

    font = str_quote_string (font, " ", '\\'); % filenames with spaces
    run_system_cmd ("fontforge -script $pe_file $font"$);
    convertdir_files = listdir (convert_dir);
    afm_file = convertdir_files[wherefirst (array_map (String_Type,
                                                       &path_extname, convertdir_files) == ".afm")];
    t42_file = convertdir_files[wherefirst (array_map (String_Type,
                                                       &path_extname, convertdir_files) == ".t42")];
    pfa_file = convertdir_files[wherefirst (array_map (String_Type,
                                                       &path_extname, convertdir_files) == ".pfa")];
    devps_dl_str = strcat (path_sans_extname (t42_file), "\t", path_basename (t42_file));
    devpdf_dl_str = strcat (path_sans_extname (pfa_file), "\t", path_basename (pfa_file));
    
    ifnot (1 == file_status (afm_file))
      throw OpenError, "$afm_file not found"$;
    
    if (is_substr (font_sans_extname, "-"))
      fam_name = strchop (font_sans_extname, '-', 0);
    if (is_substr (font_sans_extname, "_"))
      fam_name = strchop (font_sans_extname, '_', 0);

    if (length (fam_name) > 1)
    {
      ifnot (any (strlow (fam_name[-1]) == styles))
        fam_name = font_sans_extname;
      else
        fam_name = fam_name[[0:length (fam_name)-2]];
    }
    else
      fam_name = font_sans_extname;

    fam_name = strjoin (fam_name, "-");
    fam_name = read_mini ("Family Name for $font_sans_extname?"$, fam_name, fam_name);
    groff_font = fam_name + style;

    if (is_list_element (get_font_names, groff_font, ','))
      ifnot (get_y_or_n ("$groff_font already appears to be installed, overwrite"$))
        return;
    
    run_system_cmd ("afmtodit $afmtodit_opts $afm_file $textmap $groff_font"$);
    run_system_cmd ("mkdir -p $devps_dir"$);
    run_system_cmd ("mkdir -p $devpdf_dir"$);
    run_system_cmd ("chmod 0644 $groff_font $t42_file"$);
    run_system_cmd ("cp $groff_font $t42_file $devps_dir"$);
    run_system_cmd ("cp  $pfa_file $devpdf_dir"$);
    run_system_cmd ("ln -s -f ${devps_dir}/${groff_font} $devpdf_dir"$);
    run_system_cmd ("sh -c \"echo $devps_dl_str >> $devps_dl_file\""$);
    run_system_cmd ("sh -c \"echo $devpdf_dl_str >> $devpdf_dl_file\""$);
    run_system_cmd ("sort -u $devps_dl_file | tee $devps_dl_file"$);
    run_system_cmd ("sort -u $devpdf_dl_file | tee $devpdf_dl_file"$);
    run_system_cmd ("chmod 0755 $devpdf_dl_file $devps_dl_file"$);
    
    if (1 == file_status (devps_dl_file))
      run_system_cmd ("cp $devps_dl_file ${devps_dl_file}.bak"$);
    if (1 == file_status (devpdf_dl_file))
      run_system_cmd ("cp $devpdf_dl_file ${devpdf_dl_file}.bak"$);
  }
  finally
  {
    () = chdir (pwd);
    run_system_cmd ("rm -rf $convert_dir"$);
  }
  
  flush ("$groff_font installed in $groff_fonts_user_dir"$);
}

% Install all truetype and opentype fonts from a directory
define install_groff_fonts_in_dir ()
{
  variable
    dir = read_with_completion ("Font directory:", "", "", 'f'),
    fonts = listdir (dir),
    font = "",
    fonts_cs = "",
    answer = "",
    expr = "",
    ttf = fonts[where (array_map (String_Type, &path_extname, fonts) == ".ttf")],
    otf = fonts[where (array_map (String_Type, &path_extname, fonts) == ".otf")];
  
  fonts = [otf, ttf];

  ifnot (length (fonts))
    throw RunTimeError, "no *.ttf or *.otf fonts found in $dir"$;
  
  fonts_cs = strjoin (fonts, ",");
  
  ungetkey ('\t');
  answer =
    read_with_completion (fonts_cs,
                          "Install (a)ll fonts or fonts that match an (e)xpression or (c)ancel [a/e/c]:",
                          "", "", 's');
  switch (answer)
  { case "e":
    {
      update_sans_update_hook (1); 
      expr = read_mini ("Expression:", "", "");
      fonts = fonts[where (array_map (Int_Type, &string_match, fonts, expr, 1))];
      ifnot (length (fonts))
        throw RunTimeError, "no *.ttf or *.otf fonts match \"$expr\""$;
    }
  }
  { case "a": flush ("installing all fonts in $dir ..."$); sleep (3); }
  { return flush ("aborting"); }
  
  foreach font (fonts)
  {
    font = dircat (dir, font);
    try
    {
      install_groff_font (font);
      () = append_string_to_file ("[SUCCESS]: " + "$font\n"$, "/tmp/ifonts");
    }
    catch AnyError:
      () = append_string_to_file ("[FAILED]: " + "$font\n"$, "/tmp/ifonts");
  }

  variable fbname = "*** FONTS INSTALLATION RESULTS ***";
  
  if (bufferp (fbname))
    delbuf (fbname);

  pop2buf (fbname);
  () = insert_file ("/tmp/ifonts");
  set_buffer_modified_flag (0);
  most_mode ();
  bob ();
  () = delete_file ("/tmp/ifonts");
}

private variable pdfviewer_pid;

private define show_pdfviewer_error (pid, error)
{
  return flush (strtrim (error));
}

private define pdfviewer_signal_handler (pid, flags, status)
{
  variable msg = aprocess_stringify_status (pid, flags, status);
  flush (msg);
  
  ifnot (flags == 1) % if proces is no longer running
    __uninitialize (&pdfviewer_pid);
}

%% View current buffer in a pdf-viewer. Display in pdf-viewer is
%% updated with changes in buffer upon pressing a key, with no need to
%% save the file associated with the buffer in between.
define groff_preview_buffer ()
{
  variable
    ps_file = dircat ("/tmp", path_sans_extname (whatbuf ()) + ".ps"),
    pdf_file = dircat ("/tmp", path_sans_extname (whatbuf ()) + ".pdf"),
    tmpfile = make_tmp_file ("/tmp/viewmomdoc"),
    grofferr_file = make_tmp_file ("/tmp/grofferr"),
    grofferr_msg = "",
    xpdfserver = "xpdfserver",
    path = getenv ("PATH"),
    exit_status = 0,
    cmd = "";
  
  try
  {
    if (NULL == search_path_for_file (path, "ps2pdf"))
      throw RunTimeError, "package ghostscript is not installed"$;
    
    if (NULL == search_path_for_file (path, Groff_Pdf_Viewer))
      Groff_Pdf_Viewer = find_prgs_use_first ("zathura mupdf evince qpdfview okular apvlv atril gv xpdf");
    
    push_spot ();
    mark_buffer ();
    () = write_string_to_file (bufsubstr (), tmpfile);
    pop_spot ();
    
    if (MP == "-man" or MP == "-mandoc" or MP == "-mdoc")
      cmd = "$manpage_compile_cmd $tmpfile 2>$grofferr_file 1> $ps_file"$;
    else
      cmd = "$Groff_Cmd $MP $tmpfile 2>$grofferr_file 1> $ps_file"$;
    
    exit_status = system (cmd);
    grofferr_msg = strjoin (fgetslines (fopen (grofferr_file, "r")), " ");
    
    ifnot (exit_status == 0)
      throw RunTimeError, "$grofferr_msg - $cmd failed"$;
    
    run_system_cmd ("ps2pdf14 -sOutputFile=$pdf_file $ps_file"$);
    
    ifnot (__is_initialized (&pdfviewer_pid))
    {
      switch (Groff_Pdf_Viewer)
      { case "gv": 
          pdfviewer_pid = open_process ("gv", "--nocenter", "--watch",
                                        pdf_file, 3); }
      { case "xpdf": 
          pdfviewer_pid = open_process ("xpdf", "-remote", xpdfserver,
                                        pdf_file, 3); }
      { case "qpdfview": 
          pdfviewer_pid = open_process ("qpdfview", "--unique", pdf_file, 2); }
      
      { pdfviewer_pid = open_process (Groff_Pdf_Viewer, pdf_file, 1); };
      
      set_process (pdfviewer_pid, "output", &show_pdfviewer_error);
      set_process (pdfviewer_pid, "signal", &pdfviewer_signal_handler);
      process_query_at_exit (pdfviewer_pid, 0);
    }
    % this is to address some quirks that some pdf viewers have in
    % updating the display
    else 
    { 
      if (Groff_Pdf_Viewer == "mupdf") % mupdf wants a SIGHUP
        signal_process (pdfviewer_pid, 1);
      if (Groff_Pdf_Viewer == "xpdf")
        run_system_cmd ("xpdf -remote $xpdfserver -reload"$);
      if (Groff_Pdf_Viewer == "qpdfview")
        run_system_cmd ("qpdfview --unique $pdf_file"$);
    }
  }
  finally
  {
    () = delete_file (grofferr_file);
    () = delete_file (tmpfile);
    () = delete_file (ps_file);
    flush (grofferr_msg);
  }
}

% Draw various objects, lines, circles, arcs, etc.
define draw ()
{
  variable length, height, diam, coords;
  
  flush ("Draw: (h)line, (v)line, (c)ircle, s(o)lid circle, (e)llipse, (a)rc, (p)olygon, (s)pline");
  
  ifnot (input_pending (40))
    return flush ("");
  
  switch (getkey ()) 
  { case 'h': length = read_mini ("Line length?", "", ""); insert ("\\l'$length'"$); }
  { case 'v': height = read_mini ("Line height?", "", ""); insert ("\\L'$height'"$); }
  { case 'c': diam = read_mini ("Circle diameter?", "", ""); insert ("\\D'c $diam'"$); }
  { case 'o': diam = read_mini ("Circle diameter?", "", ""); insert ("\\D'C $diam'"$); }
  { case 'e': diam = read_mini ("Ellipse: horizontal and vertical diameter?", "", "");
    insert ("\\D'e $diam'"$); }
  { case 'p': coords = read_mini ("Polygon coordinates (space delim.)?", "", "");
    insert ("\\D'p $coords'"$); }
  { case 'a': coords = read_mini ("Arc coordinates (space delim.)?", "", "");
    insert ("\\D'a $coords'"$); }
  { case 's': coords = read_mini ("Spline coordinates (space delim.)?", "", "");
    insert ("\\D'~ $coords'"$); }
  { flush (""); }
}

% Give marked text some attribute or remove it.
define toggle_inline_markup ()
{
  variable str = "", sz = "", font_name = "";
  
  define_word ("-A-Za-zÀ-ÿ0-9\[\]\\");

  ifnot (markp ())
    mark_word ();
  
  () = dupmark ();
  str = bufsubstr ();
  
  ifnot (strlen (str))
    throw UsageError, "you must mark some words";

  if (string_match (str, "\\\\", 1))
    return insert (str_uncomment_string (bufsubstr_delete (), "\\[", "]\\"));

  flush ("Text Attributes: (f)ont face, (b)old, (i)talic, (s)ize:, (c)olor");
  
  ifnot (input_pending (40))
  {
    flush ("");
    return pop_mark_1;
  }
  
  switch (getkey ())
  { case 'f':
    {      
      ungetkey ('\t');
      font_name = read_with_completion (get_font_names (), "Font:", "H", "", 's');
      str = strcat ("\\f[$font_name]"$, str, "\\f[]");
    }
  }
  { case 'b': str = strcat ("\\f[B]", str, "\\f[]"); }
  { case 'i': str = strcat ("\\f[I]", str, "\\f[]"); }
  { case 's':
    {
      sz = read_mini ("Font Size?", "", "");
      str = strcat ("\\s[$sz]"$, str, "\\s[0]");
    }
  }
  
  { case 'c':
    {
      variable color = read_with_completion ("blue,red,yellow,green", "Color:", "blue", "", 's');
      str = strcat ("\\m[$color]"$, str, "\\m[]");
    }
  }
  
  flush ("");
  () = bufsubstr_delete ();
  insert (str);
}

define show_version ()
{
  flush (Version);
}

% Set the macro set to use
define use_macro_set ()
{
  macro_packages = strjoin (macro_packages, ",");
  ungetkey ('\t');
  MP = read_with_completion (macro_packages, "Macro set to use?", "", "", 's');
  
  ifnot (strlen (MP))
  {
    MP = "";
    return set_status_line (" %b  (%m " + "%a%n%o)  %p   %t", 0);
  }
  
  ifnot (MP[0] == '-')
    MP = "-" + MP;

  set_status_line (" %b  (%m " + MP  + "%a%n%o)  %p   %t", 0);
}

%% Draw some figures with gpic
define insert_pic (obj)
{
  variable a = "", b = "", c = "", d = "", s = "", direction = "", linedecor = "";
  variable color = "", length = "", width = "", height = "", rad = "";
  
  switch (obj)
  { case "line" or case "arrow": length = read_mini ("$obj length:"$, "", ""); }
  { case "box":
    width = read_mini ("$obj width:"$, "2", "");
    height = read_mini ("$obj height:"$, "1", "");
    rad = read_mini ("$obj fillet radius:"$, "0", "");
    s = strcat (obj, " \"@\"", " width ", width, " height ", height, " rad ", rad);

  }
  { case "ellipse":
    width = read_mini ("$obj width:"$, "2", "");
    height = read_mini ("$obj height:"$, "1", "");
    s = strcat (obj, " \"@\"", " width ", width, " height ", height);
  }
  { case "circle" or case "arc":
    rad = read_mini ("circle/arc radius?:", "1", "");
    s = strcat (obj, " \"@\"", " rad", " ", rad);
  }

  if (obj == "box" or obj == "circle" or obj == "ellipse")
  {
    a = read_mini ("$obj: (g)rey-shaded or (c)olored:"$, "", "");

    if (a == "g")
      s = strtrim (strcat (s, " fill 0.1"));
    if (a == "c")
    {
      color = read_mini ("$obj color?:"$, "blue", "");
      s = strtrim (strcat (s, " shaded \"$color\""$, " outline \"black\""));
    }
  }

  linedecor = read_mini ("(s)olid, d(a)shed, d(o)tted?:", "s", "");

  switch (linedecor)
  { case "a": linedecor = "dashed"; }
  { case "o": linedecor = "dotted"; }
  { case "s": linedecor = ""; }
  { linedecor = ""; }

  if (obj == "arrow" or obj == "line")
  {
    direction = read_mini ("(u)p, (d)own, (l)eft, (r)ight, up/l(e)ft, up/r(i)ght, down/le(f)t, down/ri(g)ht?:", "", "");
    switch (direction)
    { case "d": direction = "down"; }
    { case "e": direction = "up left"; }
    { case "f": direction = "down left"; }
    { case "g": direction = "down right"; }
    { case "i": direction = "up right"; }
    { case "l": direction = "left"; }
    { case "r": direction = "right"; }
    { case "u": direction = "up"; }
    { direction = ""; }

    s = strcompress (strcat (obj, " thickness 0 ", direction, " ", length, " ", linedecor), " ") + ";";
  }
  else
    s = strtrim (strcat (s, " thickness 0 ", linedecor)) + ";";

  if (is_between_macros (".PS", ".PE"))
    insert (s);
  else
    insert (strcat (".PS\n", s, "\n.PE\n"));

  if (is_substr (s, "@"))
  {
    () = bsearch ("@");
    del ();
  }
}

define draw_gpic ()
{
  ifnot (re_line_match ("^$", 1))
    throw UsageError, "not at an empty line";

  trim ();

  flush ("Gpic: (l)ine, (b)ox, (c)ircle, (e)llipse, a(r)c, (a)rrow, (s)cale to cm");
  
  ifnot (input_pending (40))
    return flush ("");
  
  switch (getkey ()) 
  { case 'a': insert_pic ("arrow"); }
  { case 'b': insert_pic ("box"); }
  { case 'l': insert_pic ("line"); }
  { case 'c': insert_pic ("circle"); }
  { case 'e': insert_pic ("ellipse"); }
  { case 'r': insert_pic ("arc"); }
  { case 's':
    if (is_between_macros (".PS", ".PE"))
      insert ("scale = 2.54\n");
    else
      insert (".PS\nscale = 2.54\n.PE");
  }
  { flush (""); }
}

%{{{ DFA syntax

#ifdef HAS_DFA_SYNTAX
create_syntax_table (Mode);
static define setup_dfa_callback (Mode)
{
  dfa_enable_highlight_cache ("groff.dfa", Mode);
  dfa_define_highlight_rule ("^\\.[a-zA-Z_]+", "keyword", Mode);
  dfa_define_highlight_rule ("^\\.\\\\\".*", "comment", Mode);
  dfa_define_highlight_rule ("[A-Z]?[0-9]+", "number", Mode);
  dfa_define_highlight_rule("\"([^\"\\\\]|\\\\.)*\"", "string", Mode);
  dfa_define_highlight_rule ("^\\\\[a-zA-Z]\\'[a-zA-Z]?", "keyword", Mode);
  dfa_build_highlight_table (Mode);
  enable_dfa_syntax_for_mode (Mode);
}
dfa_set_init_callback (&setup_dfa_callback, Mode);
#endif

%}}}
%{{{ Mode keymap

ifnot (keymap_p (Mode)) make_keymap (Mode);
definekey ("insert \(\"\t\"\)", Key_Shift_Tab, Mode);
definekey ("groff_preview_buffer", Key_F9, Mode);
definekey_reserved ("draw", "d", Mode);
definekey_reserved ("draw_gpic", "g", Mode);
definekey_reserved ("toggle_inline_markup", "i", Mode);
definekey_reserved ("insert_font_name", "f", Mode);
definekey_reserved ("install_groff_font", "I", Mode);
definekey_reserved ("install_groff_fonts_in_dir", "D", Mode);
definekey_reserved ("use_macro_set", "m", Mode);
definekey_reserved ("edit_groff_cmd", "e", Mode);

%}}}

private define groff_menu (menu)
{
  menu_append_popup (menu, "&Fonts");
  $1 = menu + ".&Fonts";
  {
    menu_append_item ($1, "Insert Font Name", "insert_font_name");
    menu_append_item ($1, "Install Groff Font", "install_groff_font");
    menu_append_item ($1, "Install Groff Fonts in Directory",  "install_groff_fonts_in_dir");
    menu_append_item ($1, "Toggle Font Attribute", "toggle_inline_markup");
  }
  menu_append_popup (menu, "&Draw With GNU PIC");
  $0 = menu + ".&Draw With GNU PIC";
  {
    menu_append_item ($0, "&Scale to cm", "insert (\".PS\\nscale = 2.54\\n.PE\")");
    menu_append_item ($0, "-----------", "");
    menu_append_item ($0, "&Arrow", "insert_pic \(\"arrow\"\)");
    menu_append_item ($0, "A&rc", "insert_pic \(\"arc\"\)");
    menu_append_item ($0, "&Box", "insert_pic \(\"box\"\)");
    menu_append_item ($0, "&Circle", "insert_pic \(\"circle\"\)");
    menu_append_item ($0, "&Ellipse", "insert_pic \(\"ellipse\"\)");
    menu_append_item ($0, "&Line", "insert_pic \(\"line\"\)");
  }
  menu_append_item (menu, "Use Macro Set", "use_macro_set");
  menu_append_item (menu, "Preview Current Buffer as PDF", "groff_preview_buffer");
  menu_append_item (menu, "Edit Groff Cmd", "edit_groff_cmd");
  menu_append_item (menu, "Draw With Gpic", "draw_gpic");
  menu_append_item (menu, "Draw Some Items", "draw");
  menu_append_item (menu, "Show Version", "show_version");
}

public define groff_mode ()
{
  set_mode (Mode, 1);
  set_buffer_hook ("par_sep", "groff_parsep");
  use_keymap (Mode);
  use_syntax_table (Mode);
  use_dfa_syntax (1);
  mode_set_mode_info (Mode, "init_mode_menu", &groff_menu);
  mode_set_mode_info (Mode, "fold_info", "\\\"{{{\r\\\"}}}\r\r");
  set_comment_info (Mode, "\.\\\" ", "", 0x04);
  set_status_line (" %b  (%m " + MP  + "%a%n%o)  %p   %t", 0);
  run_mode_hooks ("groff_mode_hook");
}
