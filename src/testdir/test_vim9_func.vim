" Test various aspects of the Vim9 script language.

source check.vim
source term_util.vim
source view_util.vim
source vim9.vim
source screendump.vim

func Test_def_basic()
  def SomeFunc(): string
    return 'yes'
  enddef
  call SomeFunc()->assert_equal('yes')
endfunc

func Test_compiling_error()
  " use a terminal to see the whole error message
  CheckRunVimInTerminal

  call TestCompilingError()
endfunc

def TestCompilingError()
  var lines =<< trim END
    vim9script
    def Fails()
      echo nothing
    enddef
    defcompile
  END
  call writefile(lines, 'XTest_compile_error')
  var buf = RunVimInTerminal('-S XTest_compile_error',
              #{rows: 10, wait_for_ruler: 0})
  var text = ''
  for loop in range(100)
    text = ''
    for i in range(1, 9)
      text ..= term_getline(buf, i)
    endfor
    if text =~ 'Error detected'
      break
    endif
    sleep 20m
  endfor
  assert_match('Error detected while compiling command line.*Fails.*Variable not found: nothing', text)

  # clean up
  call StopVimInTerminal(buf)
  call delete('XTest_compile_error')
enddef

def CallRecursive(n: number): number
  return CallRecursive(n + 1)
enddef

def CallMapRecursive(l: list<number>): number
  return map(l, {_, v -> CallMapRecursive([v])})[0]
enddef

def Test_funcdepth_error()
  set maxfuncdepth=10

  var caught = false
  try
    CallRecursive(1)
  catch /E132:/
    caught = true
  endtry
  assert_true(caught)

  caught = false
  try
    CallMapRecursive([1])
  catch /E132:/
    caught = true
  endtry
  assert_true(caught)

  set maxfuncdepth&
enddef

def ReturnString(): string
  return 'string'
enddef

def ReturnNumber(): number
  return 123
enddef

let g:notNumber = 'string'

def ReturnGlobal(): number
  return g:notNumber
enddef

def Test_return_something()
  ReturnString()->assert_equal('string')
  ReturnNumber()->assert_equal(123)
  assert_fails('ReturnGlobal()', 'E1012: Type mismatch; expected number but got string', '', 1, 'ReturnGlobal')
enddef

def Test_missing_return()
  CheckDefFailure(['def Missing(): number',
                   '  if g:cond',
                   '    echo "no return"',
                   '  else',
                   '    return 0',
                   '  endif'
                   'enddef'], 'E1027:')
  CheckDefFailure(['def Missing(): number',
                   '  if g:cond',
                   '    return 1',
                   '  else',
                   '    echo "no return"',
                   '  endif'
                   'enddef'], 'E1027:')
  CheckDefFailure(['def Missing(): number',
                   '  if g:cond',
                   '    return 1',
                   '  else',
                   '    return 2',
                   '  endif'
                   '  return 3'
                   'enddef'], 'E1095:')
enddef

def Test_return_bool()
  var lines =<< trim END
      vim9script
      def MenuFilter(id: number, key: string): bool
        return popup_filter_menu(id, key)
      enddef
      def YesnoFilter(id: number, key: string): bool
        return popup_filter_yesno(id, key)
      enddef
      defcompile
  END
  CheckScriptSuccess(lines)
enddef

let s:nothing = 0
def ReturnNothing()
  s:nothing = 1
  if true
    return
  endif
  s:nothing = 2
enddef

def Test_return_nothing()
  ReturnNothing()
  s:nothing->assert_equal(1)
enddef

func Increment()
  let g:counter += 1
endfunc

def Test_call_ufunc_count()
  g:counter = 1
  Increment()
  Increment()
  Increment()
  # works with and without :call
  g:counter->assert_equal(4)
  eval g:counter->assert_equal(4)
  unlet g:counter
enddef

def MyVarargs(arg: string, ...rest: list<string>): string
  var res = arg
  for s in rest
    res ..= ',' .. s
  endfor
  return res
enddef

def Test_call_varargs()
  MyVarargs('one')->assert_equal('one')
  MyVarargs('one', 'two')->assert_equal('one,two')
  MyVarargs('one', 'two', 'three')->assert_equal('one,two,three')
enddef

def MyDefaultArgs(name = 'string'): string
  return name
enddef

def MyDefaultSecond(name: string, second: bool  = true): string
  return second ? name : 'none'
enddef

def Test_call_default_args()
  MyDefaultArgs()->assert_equal('string')
  MyDefaultArgs('one')->assert_equal('one')
  assert_fails('MyDefaultArgs("one", "two")', 'E118:', '', 3, 'Test_call_default_args')

  MyDefaultSecond('test')->assert_equal('test')
  MyDefaultSecond('test', true)->assert_equal('test')
  MyDefaultSecond('test', false)->assert_equal('none')

  CheckScriptFailure(['def Func(arg: number = asdf)', 'enddef', 'defcompile'], 'E1001:')
  CheckScriptFailure(['def Func(arg: number = "text")', 'enddef', 'defcompile'], 'E1013: Argument 1: type mismatch, expected number but got string')
enddef

def Test_nested_function()
  def Nested(arg: string): string
    return 'nested ' .. arg
  enddef
  Nested('function')->assert_equal('nested function')

  CheckDefFailure(['def Nested()', 'enddef', 'Nested(66)'], 'E118:')
  CheckDefFailure(['def Nested(arg: string)', 'enddef', 'Nested()'], 'E119:')

  CheckDefFailure(['func Nested()', 'endfunc'], 'E1086:')
  CheckDefFailure(['def s:Nested()', 'enddef'], 'E1075:')
  CheckDefFailure(['def b:Nested()', 'enddef'], 'E1075:')

  CheckDefFailure([
        'def Outer()',
        '  def Inner()',
        '    # comment',
        '  enddef',
        '  def Inner()',
        '  enddef',
        'enddef'], 'E1073:')
  CheckDefFailure([
        'def Outer()',
        '  def Inner()',
        '    # comment',
        '  enddef',
        '  def! Inner()',
        '  enddef',
        'enddef'], 'E1117:')
enddef

func Test_call_default_args_from_func()
  call MyDefaultArgs()->assert_equal('string')
  call MyDefaultArgs('one')->assert_equal('one')
  call assert_fails('call MyDefaultArgs("one", "two")', 'E118:', '', 3, 'Test_call_default_args_from_func')
endfunc

def Test_nested_global_function()
  var lines =<< trim END
      vim9script
      def Outer()
          def g:Inner(): string
              return 'inner'
          enddef
      enddef
      defcompile
      Outer()
      g:Inner()->assert_equal('inner')
      delfunc g:Inner
      Outer()
      g:Inner()->assert_equal('inner')
      delfunc g:Inner
      Outer()
      g:Inner()->assert_equal('inner')
      delfunc g:Inner
  END
  CheckScriptSuccess(lines)

  lines =<< trim END
      vim9script
      def Outer()
          def g:Inner(): string
              return 'inner'
          enddef
      enddef
      defcompile
      Outer()
      Outer()
  END
  CheckScriptFailure(lines, "E122:")

  lines =<< trim END
      vim9script
      def Func()
        echo 'script'
      enddef
      def Outer()
        def Func()
          echo 'inner'
        enddef
      enddef
      defcompile
  END
  CheckScriptFailure(lines, "E1073:")
enddef

def Test_global_local_function()
  var lines =<< trim END
      vim9script
      def g:Func(): string
          return 'global'
      enddef
      def Func(): string
          return 'local'
      enddef
      g:Func()->assert_equal('global')
      Func()->assert_equal('local')
  END
  CheckScriptSuccess(lines)

  lines =<< trim END
      vim9script
      def g:Funcy()
        echo 'funcy'
      enddef
      s:Funcy()
  END
  CheckScriptFailure(lines, 'E117:')
enddef

def Test_local_function_shadows_global()
  var lines =<< trim END
      vim9script
      def g:Gfunc(): string
        return 'global'
      enddef
      def AnotherFunc(): number
        var Gfunc = function('len')
        return Gfunc('testing')
      enddef
      g:Gfunc()->assert_equal('global')
      AnotherFunc()->assert_equal(7)
      delfunc g:Gfunc
  END
  CheckScriptSuccess(lines)

  lines =<< trim END
      vim9script
      def g:Func(): string
        return 'global'
      enddef
      def AnotherFunc()
        g:Func = function('len')
      enddef
      AnotherFunc()
  END
  CheckScriptFailure(lines, 'E705:')
  delfunc g:Func
enddef

func TakesOneArg(arg)
  echo a:arg
endfunc

def Test_call_wrong_args()
  CheckDefFailure(['TakesOneArg()'], 'E119:')
  CheckDefFailure(['TakesOneArg(11, 22)'], 'E118:')
  CheckDefFailure(['bufnr(xxx)'], 'E1001:')
  CheckScriptFailure(['def Func(Ref: func(s: string))'], 'E475:')

  var lines =<< trim END
    vim9script
    def Func(s: string)
      echo s
    enddef
    Func([])
  END
  CheckScriptFailure(lines, 'E1013: Argument 1: type mismatch, expected string but got list<unknown>', 5)

  lines =<< trim END
    vim9script
    def FuncOne(nr: number)
      echo nr
    enddef
    def FuncTwo()
      FuncOne()
    enddef
    defcompile
  END
  writefile(lines, 'Xscript')
  var didCatch = false
  try
    source Xscript
  catch
    assert_match('E119: Not enough arguments for function: <SNR>\d\+_FuncOne', v:exception)
    assert_match('Xscript\[8\]..function <SNR>\d\+_FuncTwo, line 1', v:throwpoint)
    didCatch = true
  endtry
  assert_true(didCatch)

  lines =<< trim END
    vim9script
    def FuncOne(nr: number)
      echo nr
    enddef
    def FuncTwo()
      FuncOne(1, 2)
    enddef
    defcompile
  END
  writefile(lines, 'Xscript')
  didCatch = false
  try
    source Xscript
  catch
    assert_match('E118: Too many arguments for function: <SNR>\d\+_FuncOne', v:exception)
    assert_match('Xscript\[8\]..function <SNR>\d\+_FuncTwo, line 1', v:throwpoint)
    didCatch = true
  endtry
  assert_true(didCatch)

  delete('Xscript')
enddef

def Test_call_lambda_args()
  CheckDefFailure(['echo {i -> 0}()'],
                  'E119: Not enough arguments for function: {i -> 0}()')

  var lines =<< trim END
      var Ref = {x: number, y: number -> x + y}
      echo Ref(1, 'x')
  END
  CheckDefFailure(lines, 'E1013: Argument 2: type mismatch, expected number but got string')
enddef

" Default arg and varargs
def MyDefVarargs(one: string, two = 'foo', ...rest: list<string>): string
  var res = one .. ',' .. two
  for s in rest
    res ..= ',' .. s
  endfor
  return res
enddef

def Test_call_def_varargs()
  assert_fails('MyDefVarargs()', 'E119:', '', 1, 'Test_call_def_varargs')
  MyDefVarargs('one')->assert_equal('one,foo')
  MyDefVarargs('one', 'two')->assert_equal('one,two')
  MyDefVarargs('one', 'two', 'three')->assert_equal('one,two,three')
  CheckDefFailure(['MyDefVarargs("one", 22)'],
      'E1013: Argument 2: type mismatch, expected string but got number')
  CheckDefFailure(['MyDefVarargs("one", "two", 123)'],
      'E1013: Argument 3: type mismatch, expected string but got number')

  var lines =<< trim END
      vim9script
      def Func(...l: list<string>)
        echo l
      enddef
      Func('a', 'b', 'c')
  END
  CheckScriptSuccess(lines)

  lines =<< trim END
      vim9script
      def Func(...l: list<string>)
        echo l
      enddef
      Func()
  END
  CheckScriptSuccess(lines)

  lines =<< trim END
      vim9script
      def Func(...l: any)
        echo l
      enddef
      Func(0)
  END
  CheckScriptSuccess(lines)

  lines =<< trim END
      vim9script
      def Func(..._l: list<string>)
        echo _l
      enddef
      Func('a', 'b', 'c')
  END
  CheckScriptSuccess(lines)

  lines =<< trim END
      vim9script
      def Func(...l: list<string>)
        echo l
      enddef
      Func(1, 2, 3)
  END
  CheckScriptFailure(lines, 'E1013: Argument 1: type mismatch')

  lines =<< trim END
      vim9script
      def Func(...l: list<string>)
        echo l
      enddef
      Func('a', 9)
  END
  CheckScriptFailure(lines, 'E1013: Argument 2: type mismatch')

  lines =<< trim END
      vim9script
      def Func(...l: list<string>)
        echo l
      enddef
      Func(1, 'a')
  END
  CheckScriptFailure(lines, 'E1013: Argument 1: type mismatch')
enddef

let s:value = ''

def FuncOneDefArg(opt = 'text')
  s:value = opt
enddef

def FuncTwoDefArg(nr = 123, opt = 'text'): string
  return nr .. opt
enddef

def FuncVarargs(...arg: list<string>): string
  return join(arg, ',')
enddef

def Test_func_type_varargs()
  var RefDefArg: func(?string)
  RefDefArg = FuncOneDefArg
  RefDefArg()
  s:value->assert_equal('text')
  RefDefArg('some')
  s:value->assert_equal('some')

  var RefDef2Arg: func(?number, ?string): string
  RefDef2Arg = FuncTwoDefArg
  RefDef2Arg()->assert_equal('123text')
  RefDef2Arg(99)->assert_equal('99text')
  RefDef2Arg(77, 'some')->assert_equal('77some')

  CheckDefFailure(['var RefWrong: func(string?)'], 'E1010:')
  CheckDefFailure(['var RefWrong: func(?string, string)'], 'E1007:')

  var RefVarargs: func(...list<string>): string
  RefVarargs = FuncVarargs
  RefVarargs()->assert_equal('')
  RefVarargs('one')->assert_equal('one')
  RefVarargs('one', 'two')->assert_equal('one,two')

  CheckDefFailure(['var RefWrong: func(...list<string>, string)'], 'E110:')
  CheckDefFailure(['var RefWrong: func(...list<string>, ?string)'], 'E110:')
enddef

" Only varargs
def MyVarargsOnly(...args: list<string>): string
  return join(args, ',')
enddef

def Test_call_varargs_only()
  MyVarargsOnly()->assert_equal('')
  MyVarargsOnly('one')->assert_equal('one')
  MyVarargsOnly('one', 'two')->assert_equal('one,two')
  CheckDefFailure(['MyVarargsOnly(1)'], 'E1013: Argument 1: type mismatch, expected string but got number')
  CheckDefFailure(['MyVarargsOnly("one", 2)'], 'E1013: Argument 2: type mismatch, expected string but got number')
enddef

def Test_using_var_as_arg()
  writefile(['def Func(x: number)',  'var x = 234', 'enddef', 'defcompile'], 'Xdef')
  assert_fails('so Xdef', 'E1006:', '', 1, 'Func')
  delete('Xdef')
enddef

def DictArg(arg: dict<string>)
  arg['key'] = 'value'
enddef

def ListArg(arg: list<string>)
  arg[0] = 'value'
enddef

def Test_assign_to_argument()
  # works for dict and list
  var d: dict<string> = {}
  DictArg(d)
  d['key']->assert_equal('value')
  var l: list<string> = []
  ListArg(l)
  l[0]->assert_equal('value')

  CheckScriptFailure(['def Func(arg: number)', 'arg = 3', 'enddef', 'defcompile'], 'E1090:')
enddef

" These argument names are reserved in legacy functions.
def WithReservedNames(firstline: string, lastline: string): string
  return firstline .. lastline
enddef

def Test_argument_names()
  assert_equal('OK', WithReservedNames('O', 'K'))
enddef

def Test_call_func_defined_later()
  g:DefinedLater('one')->assert_equal('one')
  assert_fails('NotDefined("one")', 'E117:', '', 2, 'Test_call_func_defined_later')
enddef

func DefinedLater(arg)
  return a:arg
endfunc

def Test_call_funcref()
  g:SomeFunc('abc')->assert_equal(3)
  assert_fails('NotAFunc()', 'E117:', '', 2, 'Test_call_funcref') # comment after call
  assert_fails('g:NotAFunc()', 'E117:', '', 3, 'Test_call_funcref')

  var lines =<< trim END
    vim9script
    def RetNumber(): number
      return 123
    enddef
    var Funcref: func: number = function('RetNumber')
    Funcref()->assert_equal(123)
  END
  CheckScriptSuccess(lines)

  lines =<< trim END
    vim9script
    def RetNumber(): number
      return 123
    enddef
    def Bar(F: func: number): number
      return F()
    enddef
    var Funcref = function('RetNumber')
    Bar(Funcref)->assert_equal(123)
  END
  CheckScriptSuccess(lines)

  lines =<< trim END
    vim9script
    def UseNumber(nr: number)
      echo nr
    enddef
    var Funcref: func(number) = function('UseNumber')
    Funcref(123)
  END
  CheckScriptSuccess(lines)

  lines =<< trim END
    vim9script
    def UseNumber(nr: number)
      echo nr
    enddef
    var Funcref: func(string) = function('UseNumber')
  END
  CheckScriptFailure(lines, 'E1012: Type mismatch; expected func(string) but got func(number)')

  lines =<< trim END
    vim9script
    def EchoNr(nr = 34)
      g:echo = nr
    enddef
    var Funcref: func(?number) = function('EchoNr')
    Funcref()
    g:echo->assert_equal(34)
    Funcref(123)
    g:echo->assert_equal(123)
  END
  CheckScriptSuccess(lines)

  lines =<< trim END
    vim9script
    def EchoList(...l: list<number>)
      g:echo = l
    enddef
    var Funcref: func(...list<number>) = function('EchoList')
    Funcref()
    g:echo->assert_equal([])
    Funcref(1, 2, 3)
    g:echo->assert_equal([1, 2, 3])
  END
  CheckScriptSuccess(lines)

  lines =<< trim END
    vim9script
    def OptAndVar(nr: number, opt = 12, ...l: list<number>): number
      g:optarg = opt
      g:listarg = l
      return nr
    enddef
    var Funcref: func(number, ?number, ...list<number>): number = function('OptAndVar')
    Funcref(10)->assert_equal(10)
    g:optarg->assert_equal(12)
    g:listarg->assert_equal([])

    Funcref(11, 22)->assert_equal(11)
    g:optarg->assert_equal(22)
    g:listarg->assert_equal([])

    Funcref(17, 18, 1, 2, 3)->assert_equal(17)
    g:optarg->assert_equal(18)
    g:listarg->assert_equal([1, 2, 3])
  END
  CheckScriptSuccess(lines)
enddef

let SomeFunc = function('len')
let NotAFunc = 'text'

def CombineFuncrefTypes()
  # same arguments, different return type
  var Ref1: func(bool): string
  var Ref2: func(bool): number
  var Ref3: func(bool): any
  Ref3 = g:cond ? Ref1 : Ref2

  # different number of arguments
  var Refa1: func(bool): number
  var Refa2: func(bool, number): number
  var Refa3: func: number
  Refa3 = g:cond ? Refa1 : Refa2

  # different argument types
  var Refb1: func(bool, string): number
  var Refb2: func(string, number): number
  var Refb3: func(any, any): number
  Refb3 = g:cond ? Refb1 : Refb2
enddef

def FuncWithForwardCall()
  return g:DefinedEvenLater("yes")
enddef

def DefinedEvenLater(arg: string): string
  return arg
enddef

def Test_error_in_nested_function()
  # Error in called function requires unwinding the call stack.
  assert_fails('FuncWithForwardCall()', 'E1096:', '', 1, 'FuncWithForwardCall')
enddef

def Test_return_type_wrong()
  CheckScriptFailure([
        'def Func(): number',
        'return "a"',
        'enddef',
        'defcompile'], 'expected number but got string')
  CheckScriptFailure([
        'def Func(): string',
        'return 1',
        'enddef',
        'defcompile'], 'expected string but got number')
  CheckScriptFailure([
        'def Func(): void',
        'return "a"',
        'enddef',
        'defcompile'],
        'E1096: Returning a value in a function without a return type')
  CheckScriptFailure([
        'def Func()',
        'return "a"',
        'enddef',
        'defcompile'],
        'E1096: Returning a value in a function without a return type')

  CheckScriptFailure([
        'def Func(): number',
        'return',
        'enddef',
        'defcompile'], 'E1003:')

  CheckScriptFailure(['def Func(): list', 'return []', 'enddef'], 'E1008:')
  CheckScriptFailure(['def Func(): dict', 'return {}', 'enddef'], 'E1008:')
  CheckScriptFailure(['def Func()', 'return 1'], 'E1057:')

  CheckScriptFailure([
        'vim9script',
        'def FuncB()',
        '  return 123',
        'enddef',
        'def FuncA()',
        '   FuncB()',
        'enddef',
        'defcompile'], 'E1096:')
enddef

def Test_arg_type_wrong()
  CheckScriptFailure(['def Func3(items: list)', 'echo "a"', 'enddef'], 'E1008: Missing <type>')
  CheckScriptFailure(['def Func4(...)', 'echo "a"', 'enddef'], 'E1055: Missing name after ...')
  CheckScriptFailure(['def Func5(items:string)', 'echo "a"'], 'E1069:')
  CheckScriptFailure(['def Func5(items)', 'echo "a"'], 'E1077:')
enddef

def Test_vim9script_call()
  var lines =<< trim END
    vim9script
    var name = ''
    def MyFunc(arg: string)
       name = arg
    enddef
    MyFunc('foobar')
    name->assert_equal('foobar')

    var str = 'barfoo'
    str->MyFunc()
    name->assert_equal('barfoo')

    g:value = 'value'
    g:value->MyFunc()
    name->assert_equal('value')

    var listvar = []
    def ListFunc(arg: list<number>)
       listvar = arg
    enddef
    [1, 2, 3]->ListFunc()
    listvar->assert_equal([1, 2, 3])

    var dictvar = {}
    def DictFunc(arg: dict<number>)
       dictvar = arg
    enddef
    {'a': 1, 'b': 2}->DictFunc()
    dictvar->assert_equal(#{a: 1, b: 2})
    def CompiledDict()
      {'a': 3, 'b': 4}->DictFunc()
    enddef
    CompiledDict()
    dictvar->assert_equal(#{a: 3, b: 4})

    #{a: 3, b: 4}->DictFunc()
    dictvar->assert_equal(#{a: 3, b: 4})

    ('text')->MyFunc()
    name->assert_equal('text')
    ("some")->MyFunc()
    name->assert_equal('some')

    # line starting with single quote is not a mark
    # line starting with double quote can be a method call
    'asdfasdf'->MyFunc()
    name->assert_equal('asdfasdf')
    "xyz"->MyFunc()
    name->assert_equal('xyz')

    def UseString()
      'xyork'->MyFunc()
    enddef
    UseString()
    name->assert_equal('xyork')

    def UseString2()
      "knife"->MyFunc()
    enddef
    UseString2()
    name->assert_equal('knife')

    # prepending a colon makes it a mark
    new
    setline(1, ['aaa', 'bbb', 'ccc'])
    normal! 3Gmt1G
    :'t
    getcurpos()[1]->assert_equal(3)
    bwipe!

    MyFunc(
        'continued'
        )
    assert_equal('continued',
            name
            )

    call MyFunc(
        'more'
          ..
          'lines'
        )
    assert_equal(
        'morelines',
        name)
  END
  writefile(lines, 'Xcall.vim')
  source Xcall.vim
  delete('Xcall.vim')
enddef

def Test_vim9script_call_fail_decl()
  var lines =<< trim END
    vim9script
    var name = ''
    def MyFunc(arg: string)
       var name = 123
    enddef
    defcompile
  END
  CheckScriptFailure(lines, 'E1054:')
enddef

def Test_vim9script_call_fail_type()
  var lines =<< trim END
    vim9script
    def MyFunc(arg: string)
      echo arg
    enddef
    MyFunc(1234)
  END
  CheckScriptFailure(lines, 'E1013: Argument 1: type mismatch, expected string but got number')
enddef

def Test_vim9script_call_fail_const()
  var lines =<< trim END
    vim9script
    const var = ''
    def MyFunc(arg: string)
       var = 'asdf'
    enddef
    defcompile
  END
  writefile(lines, 'Xcall_const.vim')
  assert_fails('source Xcall_const.vim', 'E46:', '', 1, 'MyFunc')
  delete('Xcall_const.vim')
enddef

" Test that inside :function a Python function can be defined, :def is not
" recognized.
func Test_function_python()
  CheckFeature python3
  let py = 'python3'
  execute py "<< EOF"
def do_something():
  return 1
EOF
endfunc

def Test_delfunc()
  var lines =<< trim END
    vim9script
    def g:GoneSoon()
      echo 'hello'
    enddef

    def CallGoneSoon()
      GoneSoon()
    enddef
    defcompile

    delfunc g:GoneSoon
    CallGoneSoon()
  END
  writefile(lines, 'XToDelFunc')
  assert_fails('so XToDelFunc', 'E933:', '', 1, 'CallGoneSoon')
  assert_fails('so XToDelFunc', 'E933:', '', 1, 'CallGoneSoon')

  delete('XToDelFunc')
enddef

def Test_redef_failure()
  writefile(['def Func0(): string',  'return "Func0"', 'enddef'], 'Xdef')
  so Xdef
  writefile(['def Func1(): string',  'return "Func1"', 'enddef'], 'Xdef')
  so Xdef
  writefile(['def! Func0(): string', 'enddef', 'defcompile'], 'Xdef')
  assert_fails('so Xdef', 'E1027:', '', 1, 'Func0')
  writefile(['def Func2(): string',  'return "Func2"', 'enddef'], 'Xdef')
  so Xdef
  delete('Xdef')

  g:Func0()->assert_equal(0)
  g:Func1()->assert_equal('Func1')
  g:Func2()->assert_equal('Func2')

  delfunc! Func0
  delfunc! Func1
  delfunc! Func2
enddef

def Test_vim9script_func()
  var lines =<< trim END
    vim9script
    func Func(arg)
      echo a:arg
    endfunc
    Func('text')
  END
  writefile(lines, 'XVim9Func')
  so XVim9Func

  delete('XVim9Func')
enddef

let s:funcResult = 0

def FuncNoArgNoRet()
  s:funcResult = 11
enddef

def FuncNoArgRetNumber(): number
  s:funcResult = 22
  return 1234
enddef

def FuncNoArgRetString(): string
  s:funcResult = 45
  return 'text'
enddef

def FuncOneArgNoRet(arg: number)
  s:funcResult = arg
enddef

def FuncOneArgRetNumber(arg: number): number
  s:funcResult = arg
  return arg
enddef

def FuncTwoArgNoRet(one: bool, two: number)
  s:funcResult = two
enddef

def FuncOneArgRetString(arg: string): string
  return arg
enddef

def FuncOneArgRetAny(arg: any): any
  return arg
enddef

def Test_func_type()
  var Ref1: func()
  s:funcResult = 0
  Ref1 = FuncNoArgNoRet
  Ref1()
  s:funcResult->assert_equal(11)

  var Ref2: func
  s:funcResult = 0
  Ref2 = FuncNoArgNoRet
  Ref2()
  s:funcResult->assert_equal(11)

  s:funcResult = 0
  Ref2 = FuncOneArgNoRet
  Ref2(12)
  s:funcResult->assert_equal(12)

  s:funcResult = 0
  Ref2 = FuncNoArgRetNumber
  Ref2()->assert_equal(1234)
  s:funcResult->assert_equal(22)

  s:funcResult = 0
  Ref2 = FuncOneArgRetNumber
  Ref2(13)->assert_equal(13)
  s:funcResult->assert_equal(13)
enddef

def Test_repeat_return_type()
  var res = 0
  for n in repeat([1], 3)
    res += n
  endfor
  res->assert_equal(3)

  res = 0
  for n in add([1, 2], 3)
    res += n
  endfor
  res->assert_equal(6)
enddef

def Test_argv_return_type()
  next fileone filetwo
  var res = ''
  for name in argv()
    res ..= name
  endfor
  res->assert_equal('fileonefiletwo')
enddef

def Test_func_type_part()
  var RefVoid: func: void
  RefVoid = FuncNoArgNoRet
  RefVoid = FuncOneArgNoRet
  CheckDefFailure(['var RefVoid: func: void', 'RefVoid = FuncNoArgRetNumber'], 'E1012: Type mismatch; expected func(...) but got func(): number')
  CheckDefFailure(['var RefVoid: func: void', 'RefVoid = FuncNoArgRetString'], 'E1012: Type mismatch; expected func(...) but got func(): string')

  var RefAny: func(): any
  RefAny = FuncNoArgRetNumber
  RefAny = FuncNoArgRetString
  CheckDefFailure(['var RefAny: func(): any', 'RefAny = FuncNoArgNoRet'], 'E1012: Type mismatch; expected func(): any but got func()')
  CheckDefFailure(['var RefAny: func(): any', 'RefAny = FuncOneArgNoRet'], 'E1012: Type mismatch; expected func(): any but got func(number)')

  var RefAnyNoArgs: func: any = RefAny

  var RefNr: func: number
  RefNr = FuncNoArgRetNumber
  RefNr = FuncOneArgRetNumber
  CheckDefFailure(['var RefNr: func: number', 'RefNr = FuncNoArgNoRet'], 'E1012: Type mismatch; expected func(...): number but got func()')
  CheckDefFailure(['var RefNr: func: number', 'RefNr = FuncNoArgRetString'], 'E1012: Type mismatch; expected func(...): number but got func(): string')

  var RefStr: func: string
  RefStr = FuncNoArgRetString
  RefStr = FuncOneArgRetString
  CheckDefFailure(['var RefStr: func: string', 'RefStr = FuncNoArgNoRet'], 'E1012: Type mismatch; expected func(...): string but got func()')
  CheckDefFailure(['var RefStr: func: string', 'RefStr = FuncNoArgRetNumber'], 'E1012: Type mismatch; expected func(...): string but got func(): number')
enddef

def Test_func_type_fails()
  CheckDefFailure(['var ref1: func()'], 'E704:')

  CheckDefFailure(['var Ref1: func()', 'Ref1 = FuncNoArgRetNumber'], 'E1012: Type mismatch; expected func() but got func(): number')
  CheckDefFailure(['var Ref1: func()', 'Ref1 = FuncOneArgNoRet'], 'E1012: Type mismatch; expected func() but got func(number)')
  CheckDefFailure(['var Ref1: func()', 'Ref1 = FuncOneArgRetNumber'], 'E1012: Type mismatch; expected func() but got func(number): number')
  CheckDefFailure(['var Ref1: func(bool)', 'Ref1 = FuncTwoArgNoRet'], 'E1012: Type mismatch; expected func(bool) but got func(bool, number)')
  CheckDefFailure(['var Ref1: func(?bool)', 'Ref1 = FuncTwoArgNoRet'], 'E1012: Type mismatch; expected func(?bool) but got func(bool, number)')
  CheckDefFailure(['var Ref1: func(...bool)', 'Ref1 = FuncTwoArgNoRet'], 'E1012: Type mismatch; expected func(...bool) but got func(bool, number)')

  CheckDefFailure(['var RefWrong: func(string ,number)'], 'E1068:')
  CheckDefFailure(['var RefWrong: func(string,number)'], 'E1069:')
  CheckDefFailure(['var RefWrong: func(bool, bool, bool, bool, bool, bool, bool, bool, bool, bool, bool, bool, bool, bool, bool, bool, bool, bool, bool, bool)'], 'E1005:')
  CheckDefFailure(['var RefWrong: func(bool):string'], 'E1069:')
enddef

def Test_func_return_type()
  var nr: number
  nr = FuncNoArgRetNumber()
  nr->assert_equal(1234)

  nr = FuncOneArgRetAny(122)
  nr->assert_equal(122)

  var str: string
  str = FuncOneArgRetAny('yes')
  str->assert_equal('yes')

  CheckDefFailure(['var str: string', 'str = FuncNoArgRetNumber()'], 'E1012: Type mismatch; expected string but got number')
enddef

def Test_func_common_type()
  def FuncOne(n: number): number
    return n
  enddef
  def FuncTwo(s: string): number
    return len(s)
  enddef
  def FuncThree(n: number, s: string): number
    return n + len(s)
  enddef
  var list = [FuncOne, FuncTwo, FuncThree]
  assert_equal(8, list[0](8))
  assert_equal(4, list[1]('word'))
  assert_equal(7, list[2](3, 'word'))
enddef

def MultiLine(
    arg1: string,
    arg2 = 1234,
    ...rest: list<string>
      ): string
  return arg1 .. arg2 .. join(rest, '-')
enddef

def MultiLineComment(
    arg1: string, # comment
    arg2 = 1234, # comment
    ...rest: list<string> # comment
      ): string # comment
  return arg1 .. arg2 .. join(rest, '-')
enddef

def Test_multiline()
  MultiLine('text')->assert_equal('text1234')
  MultiLine('text', 777)->assert_equal('text777')
  MultiLine('text', 777, 'one')->assert_equal('text777one')
  MultiLine('text', 777, 'one', 'two')->assert_equal('text777one-two')
enddef

func Test_multiline_not_vim9()
  call MultiLine('text')->assert_equal('text1234')
  call MultiLine('text', 777)->assert_equal('text777')
  call MultiLine('text', 777, 'one')->assert_equal('text777one')
  call MultiLine('text', 777, 'one', 'two')->assert_equal('text777one-two')
endfunc


" When using CheckScriptFailure() for the below test, E1010 is generated instead
" of E1056.
func Test_E1056_1059()
  let caught_1056 = 0
  try
    def F():
      return 1
    enddef
  catch /E1056:/
    let caught_1056 = 1
  endtry
  eval caught_1056->assert_equal(1)

  let caught_1059 = 0
  try
    def F5(items : list)
      echo 'a'
    enddef
  catch /E1059:/
    let caught_1059 = 1
  endtry
  eval caught_1059->assert_equal(1)
endfunc

func DelMe()
  echo 'DelMe'
endfunc

def Test_error_reporting()
  # comment lines at the start of the function
  var lines =<< trim END
    " comment
    def Func()
      # comment
      # comment
      invalid
    enddef
    defcompile
  END
  writefile(lines, 'Xdef')
  try
    source Xdef
    assert_report('should have failed')
  catch /E476:/
    v:exception->assert_match('Invalid command: invalid')
    v:throwpoint->assert_match(', line 3$')
  endtry

  # comment lines after the start of the function
  lines =<< trim END
    " comment
    def Func()
      var x = 1234
      # comment
      # comment
      invalid
    enddef
    defcompile
  END
  writefile(lines, 'Xdef')
  try
    source Xdef
    assert_report('should have failed')
  catch /E476:/
    v:exception->assert_match('Invalid command: invalid')
    v:throwpoint->assert_match(', line 4$')
  endtry

  lines =<< trim END
    vim9script
    def Func()
      var db = #{foo: 1, bar: 2}
      # comment
      var x = db.asdf
    enddef
    defcompile
    Func()
  END
  writefile(lines, 'Xdef')
  try
    source Xdef
    assert_report('should have failed')
  catch /E716:/
    v:throwpoint->assert_match('_Func, line 3$')
  endtry

  delete('Xdef')
enddef

def Test_deleted_function()
  CheckDefExecFailure([
      'var RefMe: func = function("g:DelMe")',
      'delfunc g:DelMe',
      'echo RefMe()'], 'E117:')
enddef

def Test_unknown_function()
  CheckDefExecFailure([
      'var Ref: func = function("NotExist")',
      'delfunc g:NotExist'], 'E700:')
enddef

def RefFunc(Ref: func(string): string): string
  return Ref('more')
enddef

def Test_closure_simple()
  var local = 'some '
  RefFunc({s -> local .. s})->assert_equal('some more')
enddef

def MakeRef()
  var local = 'some '
  g:Ref = {s -> local .. s}
enddef

def Test_closure_ref_after_return()
  MakeRef()
  g:Ref('thing')->assert_equal('some thing')
  unlet g:Ref
enddef

def MakeTwoRefs()
  var local = ['some']
  g:Extend = {s -> local->add(s)}
  g:Read = {-> local}
enddef

def Test_closure_two_refs()
  MakeTwoRefs()
  join(g:Read(), ' ')->assert_equal('some')
  g:Extend('more')
  join(g:Read(), ' ')->assert_equal('some more')
  g:Extend('even')
  join(g:Read(), ' ')->assert_equal('some more even')

  unlet g:Extend
  unlet g:Read
enddef

def ReadRef(Ref: func(): list<string>): string
  return join(Ref(), ' ')
enddef

def ExtendRef(Ref: func(string): list<string>, add: string)
  Ref(add)
enddef

def Test_closure_two_indirect_refs()
  MakeTwoRefs()
  ReadRef(g:Read)->assert_equal('some')
  ExtendRef(g:Extend, 'more')
  ReadRef(g:Read)->assert_equal('some more')
  ExtendRef(g:Extend, 'even')
  ReadRef(g:Read)->assert_equal('some more even')

  unlet g:Extend
  unlet g:Read
enddef

def MakeArgRefs(theArg: string)
  var local = 'loc_val'
  g:UseArg = {s -> theArg .. '/' .. local .. '/' .. s}
enddef

def MakeArgRefsVarargs(theArg: string, ...rest: list<string>)
  var local = 'the_loc'
  g:UseVararg = {s -> theArg .. '/' .. local .. '/' .. s .. '/' .. join(rest)}
enddef

def Test_closure_using_argument()
  MakeArgRefs('arg_val')
  g:UseArg('call_val')->assert_equal('arg_val/loc_val/call_val')

  MakeArgRefsVarargs('arg_val', 'one', 'two')
  g:UseVararg('call_val')->assert_equal('arg_val/the_loc/call_val/one two')

  unlet g:UseArg
  unlet g:UseVararg
enddef

def MakeGetAndAppendRefs()
  var local = 'a'

  def Append(arg: string)
    local ..= arg
  enddef
  g:Append = Append

  def Get(): string
    return local
  enddef
  g:Get = Get
enddef

def Test_closure_append_get()
  MakeGetAndAppendRefs()
  g:Get()->assert_equal('a')
  g:Append('-b')
  g:Get()->assert_equal('a-b')
  g:Append('-c')
  g:Get()->assert_equal('a-b-c')

  unlet g:Append
  unlet g:Get
enddef

def Test_nested_closure()
  var local = 'text'
  def Closure(arg: string): string
    return local .. arg
  enddef
  Closure('!!!')->assert_equal('text!!!')
enddef

func GetResult(Ref)
  return a:Ref('some')
endfunc

def Test_call_closure_not_compiled()
  var text = 'text'
  g:Ref = {s ->  s .. text}
  GetResult(g:Ref)->assert_equal('sometext')
enddef

def Test_double_closure_fails()
  var lines =<< trim END
    vim9script
    def Func()
      var name = 0
      for i in range(2)
          timer_start(0, {-> name})
      endfor
    enddef
    Func()
  END
  CheckScriptSuccess(lines)
enddef

def Test_nested_closure_used()
  var lines =<< trim END
      vim9script
      def Func()
        var x = 'hello'
        var Closure = {-> x}
        g:Myclosure = {-> Closure()}
      enddef
      Func()
      assert_equal('hello', g:Myclosure())
  END
  CheckScriptSuccess(lines)
enddef

def Test_nested_closure_fails()
  var lines =<< trim END
    vim9script
    def FuncA()
      FuncB(0)
    enddef
    def FuncB(n: number): list<string>
      return map([0], {_, v -> n})
    enddef
    FuncA()
  END
  CheckScriptFailure(lines, 'E1012:')
enddef

def Test_nested_lambda()
  var lines =<< trim END
    vim9script
    def Func()
      var x = 4
      var Lambda1 = {-> 7}
      var Lambda2 = {-> [Lambda1(), x]}
      var res = Lambda2()
      assert_equal([7, 4], res)
    enddef
    Func()
  END
  CheckScriptSuccess(lines)
enddef

def Shadowed(): list<number>
  var FuncList: list<func: number> = [{ -> 42}]
  return FuncList->map({_, Shadowed -> Shadowed()})
enddef

def Test_lambda_arg_shadows_func()
  assert_equal([42], Shadowed())
enddef

def Line_continuation_in_def(dir: string = ''): string
  var path: string = empty(dir)
          \ ? 'empty'
          \ : 'full'
  return path
enddef

def Test_line_continuation_in_def()
  Line_continuation_in_def('.')->assert_equal('full')
enddef

def Line_continuation_in_lambda(): list<string>
  var x = range(97, 100)
      ->map({_, v -> nr2char(v)
          ->toupper()})
      ->reverse()
  return x
enddef

def Test_line_continuation_in_lambda()
  Line_continuation_in_lambda()->assert_equal(['D', 'C', 'B', 'A'])
enddef

func Test_silent_echo()
  CheckScreendump

  let lines =<< trim END
    vim9script
    def EchoNothing()
      silent echo ''
    enddef
    defcompile
  END
  call writefile(lines, 'XTest_silent_echo')

  " Check that the balloon shows up after a mouse move
  let buf = RunVimInTerminal('-S XTest_silent_echo', {'rows': 6})
  call term_sendkeys(buf, ":abc")
  call VerifyScreenDump(buf, 'Test_vim9_silent_echo', {})

  " clean up
  call StopVimInTerminal(buf)
  call delete('XTest_silent_echo')
endfunc

def SilentlyError()
  execute('silent! invalid')
  g:did_it = 'yes'
enddef

func UserError()
  silent! invalid
endfunc

def SilentlyUserError()
  UserError()
  g:did_it = 'yes'
enddef

" This can't be a :def function, because the assert would not be reached.
func Test_ignore_silent_error()
  let g:did_it = 'no'
  call SilentlyError()
  call assert_equal('yes', g:did_it)

  let g:did_it = 'no'
  call SilentlyUserError()
  call assert_equal('yes', g:did_it)

  unlet g:did_it
endfunc

def Test_ignore_silent_error_in_filter()
  var lines =<< trim END
      vim9script
      def Filter(winid: number, key: string): bool
          if key == 'o'
              silent! eval [][0]
              return true
          endif
          return popup_filter_menu(winid, key)
      enddef

      popup_create('popup', #{filter: Filter})
      feedkeys("o\r", 'xnt')
  END
  CheckScriptSuccess(lines)
enddef

def Fibonacci(n: number): number
  if n < 2
    return n
  else
    return Fibonacci(n - 1) + Fibonacci(n - 2)
  endif
enddef

def Test_recursive_call()
  Fibonacci(20)->assert_equal(6765)
enddef

def TreeWalk(dir: string): list<any>
  return readdir(dir)->map({_, val ->
            fnamemodify(dir .. '/' .. val, ':p')->isdirectory()
               ? {val: TreeWalk(dir .. '/' .. val)}
               : val
             })
enddef

def Test_closure_in_map()
  mkdir('XclosureDir/tdir', 'p')
  writefile(['111'], 'XclosureDir/file1')
  writefile(['222'], 'XclosureDir/file2')
  writefile(['333'], 'XclosureDir/tdir/file3')

  TreeWalk('XclosureDir')->assert_equal(['file1', 'file2', {'tdir': ['file3']}])

  delete('XclosureDir', 'rf')
enddef

def Test_invalid_function_name()
  var lines =<< trim END
      vim9script
      def s: list<string>
  END
  CheckScriptFailure(lines, 'E129:')

  lines =<< trim END
      vim9script
      def g: list<string>
  END
  CheckScriptFailure(lines, 'E129:')

  lines =<< trim END
      vim9script
      def <SID>: list<string>
  END
  CheckScriptFailure(lines, 'E884:')

  lines =<< trim END
      vim9script
      def F list<string>
  END
  CheckScriptFailure(lines, 'E488:')
enddef

def Test_partial_call()
  var Xsetlist = function('setloclist', [0])
  Xsetlist([], ' ', {'title': 'test'})
  getloclist(0, {'title': 1})->assert_equal({'title': 'test'})

  Xsetlist = function('setloclist', [0, [], ' '])
  Xsetlist({'title': 'test'})
  getloclist(0, {'title': 1})->assert_equal({'title': 'test'})

  Xsetlist = function('setqflist')
  Xsetlist([], ' ', {'title': 'test'})
  getqflist({'title': 1})->assert_equal({'title': 'test'})

  Xsetlist = function('setqflist', [[], ' '])
  Xsetlist({'title': 'test'})
  getqflist({'title': 1})->assert_equal({'title': 'test'})

  var Len: func: number = function('len', ['word'])
  assert_equal(4, Len())
enddef

def Test_cmd_modifier()
  tab echo '0'
  CheckDefFailure(['5tab echo 3'], 'E16:')
enddef

def Test_restore_modifiers()
  # check that when compiling a :def function command modifiers are not messed
  # up.
  var lines =<< trim END
      vim9script
      set eventignore=
      autocmd QuickFixCmdPost * copen
      def AutocmdsDisabled()
        eval 0
      enddef
      func Func()
        noautocmd call s:AutocmdsDisabled()
        let g:ei_after = &eventignore
      endfunc
      Func()
  END
  CheckScriptSuccess(lines)
  g:ei_after->assert_equal('')
enddef

def StackTop()
  eval 1
  eval 2
  # call not on fourth line
  StackBot()
enddef

def StackBot()
  # throw an error
  eval [][0]
enddef

def Test_callstack_def()
  try
    StackTop()
  catch
    v:throwpoint->assert_match('Test_callstack_def\[2\]..StackTop\[4\]..StackBot, line 2')
  endtry
enddef

" Re-using spot for variable used in block
def Test_block_scoped_var()
  var lines =<< trim END
      vim9script
      def Func()
        var x = ['a', 'b', 'c']
        if 1
          var y = 'x'
          map(x, {-> y})
        endif
        var z = x
        assert_equal(['x', 'x', 'x'], z)
      enddef
      Func()
  END
  CheckScriptSuccess(lines)
enddef


" vim: ts=8 sw=2 sts=2 expandtab tw=80 fdm=marker
