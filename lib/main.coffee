{CompositeDisposable} = require 'atom'

module.exports = CreateGrammarSpec =
  subscriptions: null
  activeTextEditor: null
  activeBuffer: null
  specObject: null
  commentSyntaxStart: "//"

  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.commands.add 'atom-text-editor', 'create-grammar-spec:update-line': => @updateLine()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'create-grammar-spec:update-file': => @updateFile()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'create-grammar-spec:remove-specs': => @removeSpecs()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'create-grammar-spec:grammar-comment': => @modGrammar(true)
    @subscriptions.add atom.commands.add 'atom-text-editor', 'create-grammar-spec:grammar-uncomment': => @modGrammar(false)

  deactivate: ->
    @subscriptions.dispose()
    if @autoIndentJSX then atom.config.set('language-babel').autoIndentJSX = @autoIndentJSX

  # remove atom-grammar-test syntax checks
  # file maybe whole file - i.e. single cursor or a selected range
  removeSpecs: () ->
    @activeTextEditor = atom.workspace.getActiveTextEditor()
    @activeBuffer = @activeTextEditor.getBuffer()
    selectedRange = @activeTextEditor.getSelectedBufferRange()
    selectedRowTo   = Math.min selectedRange.start.row, selectedRange.end.row
    selectedRowFrom = Math.max selectedRange.start.row, selectedRange.end.row
    if selectedRowTo is selectedRowFrom
      selectedRowFrom = @activeBuffer.getLineCount() - 1
      selectedRowTo = 0
    for row in [selectedRowFrom..selectedRowTo]
      @deleteSpecRows(row)

  # update the files atom-grammar-test syntax check
  # file maybe whole file - i.e. single cursor or a selected range
  updateFile: () ->
    @activeTextEditor = atom.workspace.getActiveTextEditor()
    @activeBuffer = @activeTextEditor.getBuffer()
    selectedRange = @activeTextEditor.getSelectedBufferRange()
    selectedRowTo   = Math.min selectedRange.start.row, selectedRange.end.row
    selectedRowFrom = Math.max selectedRange.start.row, selectedRange.end.row
    if selectedRowTo is selectedRowFrom
      selectedRowFrom = @activeBuffer.getLineCount() - 1
      selectedRowTo = 0
    for row in [selectedRowFrom..selectedRowTo]
      @activeTextEditor.setCursorBufferPosition([row,0])
      @updateLine()

  # update the selected lines atom-grammar-test  syntax check
  updateLine: () ->
    @activeTextEditor = atom.workspace.getActiveTextEditor()
    @activeBuffer = @activeTextEditor.getBuffer()
    return if @activeTextEditor is ''
    return unless @activeTextEditor.getGrammar().packageName is 'language-babel'
    @getCommentSyntax()
    selectedRange = @activeTextEditor.getSelectedBufferRange()
    selectedRow = Math.max selectedRange.start.row, selectedRange.end.row
    return if @isLineSpecCheck(selectedRow)
    @autoIndentJSX ?= atom.config.get('language-babel').autoIndentJSX
    @deleteSpecRows(selectedRow+1)
    @createSpecObject(selectedRow)
    @createSpecLines(selectedRow)

  # create atom-grammar-test specLines
  createSpecLines: (row) ->
    col0Scopes = []
    col1Scopes = []
    remainingScopes = {}
    for scope, positionArray of @specObject
      if positionArray[0] is '^' then col0Scopes.push(scope)
      if positionArray[1] is '^' then col1Scopes.push(scope)
      remainingScopes[scope] = @commentSyntaxStart
      for index in [2..@activeTextEditor.lineTextForBufferRow(row).length]
        if positionArray[index] is '^'
          remainingScopes[scope] += '^'
        else
          remainingScopes[scope] += ' '
    specLines = []
    if col0Scopes.length then specLines.push(@commentSyntaxStart+" <- "+col0Scopes.join(' '))
    if col1Scopes.length  then specLines.push(" "+@commentSyntaxStart+" <- "+col1Scopes.join(' '))
    for scope, specLine of remainingScopes
      rex = new RegExp("^"+@commentSyntaxStartRex+"\\s*\\^")
      if rex.test specLine
        specLines.push(specLine+" "+scope)
    if specLines.length then @activeBuffer.insert([row+1,0],specLines.join(@commentSyntaxEnd+'\n')+@commentSyntaxEnd+ '\n')

  # create spec object for row
  # { 'scopename': sparse array with postion carrets }
  createSpecObject: (row) ->
    @specObject = {}
    lineText = @activeTextEditor.lineTextForBufferRow(row)
    return if /^\s*$/.test lineText
    for column in [0...lineText.length]
      continue if /\s/.test lineText[column]
      scopes = @activeTextEditor.scopeDescriptorForBufferPosition([row, column]).getScopesArray()
      scopes.map (scope) =>
        return if scope is 'source.js.jsx'
        if not @specObject[scope] then @specObject[scope] = []
        @specObject[scope][column] = '^'


  # delete block of atom-grammar-test spec lines following startRow
  deleteSpecRows: (startRow) ->
    if @isLineSpecCheck(startRow)
      endRow = startRow+1
      while endRow < @activeBuffer.getLineCount() and @isLineSpecCheck(endRow)
        endRow++
      endRow--
      @activeBuffer.deleteRows(startRow, endRow)

  getCommentSyntax: () ->
    lineText = @activeTextEditor.lineTextForBufferRow(0)
    if matchResult =  /^(\S*)\s*SYNTAX\s*TEST\s*(".*")\s*(\S*)/.exec lineText
      escapeStringRegExp = /[|^$+*?.\/]/g;
      # Get a valid regexp escaped string.
      @commentSyntaxStart = matchResult[1]
      @commentSyntaxEnd = matchResult[3]
      @commentSyntaxStartRex = matchResult[1].replace(escapeStringRegExp, '\\$&')



  # is line a atom-grammar-test spec check line
  isLineSpecCheck: (row) ->
    lineText = @activeTextEditor.lineTextForBufferRow(row)
    rex = new RegExp("^\\s*"+@commentSyntaxStartRex+"\\s*(<-|<<|>>|\\^)")
    return rex.test lineText

  # add/revove comments containing grammar line number to regex
  modGrammar: (addComments) ->
    @activeTextEditor = atom.workspace.getActiveTextEditor()
    @activeBuffer = @activeTextEditor.getBuffer()
    rows = @activeBuffer.getLineCount()
    while (rows > 0 )
      row = --rows
      lineText =  @activeTextEditor.lineTextForBufferRow row
      switch addComments
        when true
          if /(^\s*"(match|begin|end)":\s*")(.*)$/.test lineText
            if /(^\s*"(match|begin|end)":\s*")(\(\?#line:\d*\))(.*)$/.test lineText
              # already commented
              break
            commentText = "(?#line:"+(row+1)+")"
            newLineText = lineText.replace  /(^\s*"(match|begin|end)":\s*")(.*)$/, "$1"+commentText+"$3"
            @activeBuffer.deleteRows row, row
            @activeBuffer.insert [row,0], newLineText + "\n"
        when false
          if /(^\s*"(match|begin|end)":\s*")(\(\?#line:\d*\))(.*)$/.test lineText
            newLineText = lineText.replace /(^\s*"(match|begin|end)":\s*")(\(\?#line:\d*\))(.*)$/, "$1$4"
            @activeBuffer.deleteRows row, row
            @activeBuffer.insert [row,0], newLineText  + "\n"
