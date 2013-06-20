# Knockout.js view model for the room.js client
class @ClientView

  # apply styles to a color marked up string using a span
  colorize = (str) ->
    str
      .replace(/\\\{/g, "!~TEMP_SWAP_LEFT~!")
      .replace(/\\\}/g, "!~TEMP_SWAP_RIGHT~!")
      .replace(/\{(.*?)\|/g, "<span class='$1'>")
      .replace(/\}/g, "</span>")
      .replace(/!~TEMP_SWAP_LEFT~!/g, "{")
      .replace(/!~TEMP_SWAP_RIGHT~!/g, "}")

  # escape any html in a string
  escapeHTML = (str) ->
    str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')

  # escape curly brackets in a string
  escapeBrackets = (str) ->
    str
      .replace(/\{/g, '\\{')
      .replace(/\}/g, '\\}')

  history: []
  currentHistory: -1

  socket: null

  inputCallback: null

  # construct the view model
  constructor: (@body, @screen, @input) ->
    @lines      = ko.observableArray []
    @maxLines   = ko.observable 1000
    @maxHistory = ko.observable 1000
    @command    = ko.observable ""
    @form       = ko.observable null

    @socket = io.connect(window.location.href+'client')
    @attachListeners()
    @focusInput()

    $(window).on 'resize', =>
      @setSizes()
      @scrollToBottom()

    ko.applyBindings @
    $('.cloak').removeClass 'cloak'
    @setSizes()

  # attach the websocket event listeners
  attachListeners: ->
    @socket.on 'connect', @connect
    @socket.on 'connecting', @connecting
    @socket.on 'disconnect', @disconnect
    @socket.on 'connect_failed', @connect_failed
    @socket.on 'error', @error
    @socket.on 'reconnect_failed', @reconnect_failed
    @socket.on 'reconnect', @reconnect
    @socket.on 'reconnecting', @reconnecting

    @socket.on 'output', @output
    @socket.on 'request_form_input', @request_form_input
    @socket.on 'request_input', @request_input

  # apply proper sizes to the input and the screen div
  setSizes: ->
    inputWidthDiff = @input.outerWidth() - @input.width()
    @input.width($(window).width() - inputWidthDiff - $('.prompt').outerWidth())
    @screen.height($(window).height() - @input.outerHeight() - 2)

  # scroll the screen to the bottom
  scrollToBottom: ->
    @screen.scrollTop(@screen[0].scrollHeight);

  # add a line of output from the server to the screen
  addLine: (line, escape = true) ->
    line = escapeHTML line if escape
    @lines.push colorize line
    if @lines().length > @maxLines()
      @lines.shift()
    @scrollToBottom()

  # give focus to the command input element
  focusInput: ->
    @input.focus()

  # send the entered command to the server
  # and add it to the command history
  sendCommand: ->
    command = @command()
    escapedCommand = escapeBrackets command
    if command
      @addLine "\n{black|> #{escapedCommand}}", false
      @history.unshift command
      if @history.length > @maxHistory()
        @history.pop()
      @currentHistory = -1
      if not @clientCommand command
        # if an input callback is waiting, send it to that, otherwise, send it to the server
        if @inputCallback?
          @inputCallback command
          @inputCallback = null
        else
          @socket.emit 'input', escapedCommand
      @command ""

  # simple client-side commands
  clientCommand: (command) ->
    if command == 'clear'
      @lines []
      true
    else if command == 'toasty!'
      toasty()
      true
    else
      false

  # given a javascript event for the 'up' or 'down' keys
  # scroll through history and fill the input box with
  # the selected command
  recall: (_, e) ->
    return true if @history.length == 0
    switch e.which
      when 38 # up
        if @currentHistory < @history.length - 1
          @currentHistory++
        @command @history[@currentHistory]
        # the up arrow likes to move the cursor to the beginning of the line
        # move it back!
        l = @command().length
        e.target.setSelectionRange(l,l)
      when 40 # down
        if @currentHistory > -1
          @currentHistory--
        if @currentHistory >= 0
          @command @history[@currentHistory]
        else
          @command ""
      else
        true

  #############################
  # websocket event listeners #
  #############################

  connect: =>
    @addLine '{bold green|Connected!}'

  connecting: =>
    @addLine '{gray|Connecting...}'

  disconnect: =>
    @addLine '{bold red|Disconnected from server.}'
    @loadedVerb null
    @form null

  connect_failed: =>
    @addLine '{bold red|Connection to server failed.}'

  error: =>
    @addLine '{bold red|An unknown error occurred.}'

  reconnect_failed: =>
    @addLine '{bold red|Unable to reconnect to server.}'

  reconnect: =>
  #  @addLine '{bold green|Reconnected!}'

  reconnecting: =>
    @addLine '{gray|Attempting to reconnect...}'

  # output event
  # adds a line of output to the screen
  output: (msg) =>
    @addLine msg

  # input was requested from the server.
  # the next thing the user sends has to be returned to fn
  request_input: (msg, fn) =>
    @addLine msg
    @inputCallback = fn

  # request_form_input event
  # the server has requested some form input
  # so we display a modal with a dynamically
  # constructed form
  request_form_input: (formDescriptor) =>
    @form new ModalFormView formDescriptor, @socket