import Scintilla, styler, BufferLines, Chunk, config from lunar
import File from lunar.fs
import style from lunar.ui
import PropertyObject from lunar.aux.moon
import destructor from lunar.aux

background_sci = Scintilla!
background_buffer = setmetatable {}, __mode: 'v'
buffer_titles = setmetatable {}, __mode: 'v'
title_counters = {}

file_title = (file) ->
  title = file.basename
  while buffer_titles[title]
    file = file.parent
    return title if not file
    title = file.basename .. File.separator .. title

  title

title_counter = (title) ->
  title_counters[title] = 1 if not title_counters[title]
  title_counters[title] += 1
  title_counters[title]

class Buffer extends PropertyObject
  new: (mode, sci) =>
    error('Missing argument #1 (mode)', 3) if not mode
    super!

    if sci
      @_sci = sci
      @doc = sci\get_doc_pointer!
      @scis = { sci }
    else
      @doc = background_sci\create_document!
      @destructor = destructor background_sci\release_document, @doc
      @scis = {}

    @completers = {}
    @mode = mode
    @properties = {}

  @property file:
    get: => @_file
    set: (file) =>
      @_file = file
      @title = file_title file
      @text = file.exists and file.contents or ''
      @dirty = false
      @can_undo = false

  @property mode:
    get: => @_mode
    set: (mode) => @_mode = mode

  @property title:
    get: => @_title or 'Untitled'
    set: (title) =>
      title ..= '<' .. title_counter(title) .. '>' if buffer_titles[title]
      @_title = title
      buffer_titles[title] = self

  @property text:
    get: => @sci\get_text!
    set: (text) =>
      @sci\clear_all!
      @sci\add_text #text, text
      @sci\set_code_page Scintilla.SC_CP_UTF8

  @property dirty:
    get: => @sci\get_modify!
    set: (status) =>
      if not status then @sci\set_save_point!
      else -- there's no specific message for marking as dirty
        @append ' '
        @delete @size, 1

  @property can_undo:
    get: => @sci\can_undo!
    set: (value) => @sci\empty_undo_buffer! if not value

  @property size: get: => @sci\get_text_length!
  @property lines: get: => BufferLines self, @sci

  @property eol:
    get: =>
      switch @sci\get_eolmode!
        when Scintilla.SC_EOL_LF then '\n'
        when Scintilla.SC_EOL_CRLF then '\r\n'
        when Scintilla.SC_EOL_CR then '\r'
    set: (eol) =>
      s_mode = switch eol
        when '\n' then Scintilla.SC_EOL_LF
        when '\r\n' then Scintilla.SC_EOL_CRLF
        when '\r' then Scintilla.SC_EOL_CR
        else error 'Unknown eol mode'
      @sci\set_eolmode s_mode

  @property showing: get: => #@scis > 0
  @property last_shown: get: => #@scis > 0 and os.time! or @_last_shown
  @property destroyed: get: => @doc == nil

  destroy: =>
    return if @destroyed
    error 'Cannot destroy a currently showing buffer', 2 if @showing

    if @destructor
      @destructor.defuse!
      @sci\release_document @doc
      @destructor = nil

    @doc = nil

  chunk: (pos, length) => Chunk self, pos, pos + length - 1

  word_at: (pos) =>
    start_pos = @sci\word_start_position pos - 1, true
    end_pos = @sci\word_end_position pos - 1, true
    return Chunk self, start_pos + 1, end_pos

  delete: (pos, length) => @sci\delete_range pos - 1, length

  insert: (text, pos) =>
    @sci\insert_text pos - 1, text
    pos + #text

  append: (text) => @sci\append_text #text, text

  replace: (pattern, replacement) =>
    matches = {}
    pos = 1
    text = @text

    while pos < @size
      start_pos, end_pos, match = text\find pattern, pos
      break unless start_pos

      -- only replace the match within pattern if present
      end_pos = match and (start_pos + #match - 1) or end_pos

      append matches, :start_pos, :end_pos
      pos = end_pos + 1

    for i = #matches, 1, -1
      match = matches[i]
      with @sci
        \set_target_start match.start_pos - 1
        \set_target_end match.end_pos
        \replace_target -1, replacement

    #matches

  save: =>
    if @file
      if config.get 'strip_trailing_whitespace', self
        ws = '[\t ]'
        @replace "(#{ws}+)#{@eol}", ''
        @replace "(#{ws}+)$", ''

      @file.contents = @text
      @dirty = false

  as_one_undo: (f) =>
    @sci\begin_undo_action!
    status, ret = pcall f
    @sci\end_undo_action!
    error ret if not status

  undo: => @sci\undo!

  @property sci:
    get: =>
      error 'Attempt to invoke operation on destroyed buffer', 2 if @destroyed
      if @_sci then return @_sci

      if background_buffer[1] != self
        background_sci\set_doc_pointer self.doc
        background_buffer[1] = self

      background_sci

  add_sci_ref: (sci) =>
    append @scis, sci
    @_sci = sci

  remove_sci_ref: (sci) =>
    @scis = [s for s in *@scis when s != sci]
    @_sci = @scis[1] if sci == @_sci
    @_last_shown = os.time! if #@scis == 0

  lex: (end_pos) =>
    if @_mode and @_mode.lexer
      styler.style_text @sci, self, end_pos, @_mode.lexer
    else
      styler.mark_as_styled @sci, self

  @meta {
    __len: => @size
    __tostring: => @title
  }

-- Config variables

with config
  .define
    name: 'strip_trailing_whitespace'
    description: 'Whether trailing whitespace will be removed upon save'
    default: true
    type_of: 'boolean'

return Buffer
