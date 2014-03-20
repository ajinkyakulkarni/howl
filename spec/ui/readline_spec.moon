import Window, Readline from howl.ui

describe 'Readline', ->
  window = Window!
  local readline

  before_each -> readline = Readline window

  describe 'read(prompt, input)', ->
    it 'suspends the current coroutine while waiting for submission', ->
      co = coroutine.create -> readline\read 'foo'
      assert coroutine.resume co
      assert.equals "suspended", coroutine.status co

    it 'resumes the coroutine upon submission, causing return of the chosen value', ->
      local value
      coroutine.wrap(-> value = readline\read 'foo: ')!
      readline.text = 'bar'
      readline.keymap.return readline
      assert.equals "bar", value

    it 'returns nil upon cancel', ->
      local value
      coroutine.wrap(-> value = readline\read 'foo: ')!
      readline.text = 'bar'
      readline.keymap.escape readline
      assert.is_nil value