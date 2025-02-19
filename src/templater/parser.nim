import std/[algorithm, enumerate, strformat, strutils, sugar, tables]
import regex
import variable

const
  variablePattern = re2 "\\{\\{\\s*([a-zA-Z0-9]*)\\s*\\}\\}"
  forLoopPattern = re2 "\\{\\{#for\\s*([a-zA-Z0-9]*)\\s*in\\s*([a-zA-Z0-9]*)\\s*(?:\\|\\s*([a-zA-Z0-9]*))?\\}\\}"
  endForPattern = re2 "\\{\\{#endfor\\}\\}"
  forLoopVarPattern = re2 "\\{\\{#(?!for|endfor)([a-zA-Z0-9]*)\\}\\}"

func createLoopVarPattern(name: string): Regex2 =
  let pattern = "\\{\\{#" & name & "\\}\\}"
  re2 pattern

type
  ValidationError* = object of ValueError
  VariableError* = object of ValueError

  Parser* = ref object
    templ, output: string
    variables: TableRef[string, Variable]
    index: int

## Returns a list of validation issues, to output to the user
proc validate(templ: static string): seq[string] =
  result = newSeq[string]()

  let
    forLoops = templ.findAll(forLoopPattern)
    endFors = templ.findAll(endForPattern)

  if forLoops.len != endFors.len:
    result.add("No. of ForLoops not equivalent to No. of EndFors")
    result.add("No. of ForLoops not equivalent to No. of EndFors")

func newParser*(templ: static string; variables: TableRef[string, Variable]): Parser {.raises: [ValidationError].} =
  ## Creates a new parser, and validates the template on build
  ## 
  ## `templ` must be a static string, meaning to load an actual template you must do:
  ## ```nim
  ## var parser = newParser(staticRead "myfile.html", newTable[string, Variable]())
  ## ```
  ## If there is a validation error on build, you can either handle the ValidationError, or let it output
  const errors = templ.validate()
  if errors.len != 0:
    raise ValidationError.newException(errors.join(",\n"))

  Parser(templ: templ, output: templ, index: 0, variables: variables)

template replace(templ: var string; value: string; bounds: Slice[int]): void =
  ## This function will modify `templ` in place
  templ.delete(bounds)
  templ.insert(value, bounds.a)

proc insertVariables(p: var Parser): void {.raises: [VariableError, ref KeyError].} =
  let matches = p.output.findAll(variablePattern)

  for match in matches.reversed:
    let variableName = p.output[match.group(0)]
    if not p.variables.hasKey(variableName):
      raise VariableError.newException("Variable " & variableName & " not found")

    let value = p.variables[variableName]

    p.output.replace($value, match.boundaries)

proc getForLoopEnd(p: Parser; m: RegexMatch2): RegexMatch2 {.raises: [ValidationError].} =
  if not p.output.find(endForPattern, result, m.boundaries.a):
    raise ValidationError.newException("Unable to find end for loop")

proc insertForLoops(p: var Parser): void {.raises: [ValidationError, VariableError, ref KeyError, RegexError].} =
  var match = RegexMatch2()

  while p.output.find(forLoopPattern, match, match.boundaries.b):
    let endMatch = p.getForLoopEnd(match)

    let 
      iterationName = p.output[match.group(0)]
      iterationValue = p.output[match.group(1)]
      indexName = p.output[match.group(2)]
      hasIndex = indexName != ""

    if not p.variables.hasKey(iterationValue):
      raise VariableError.newException(fmt"Variable {iterationValue} not found")

    let values = p.variables[iterationValue]

    if not values.isArray:
      raise VariableError.newException(fmt"Variable {iterationValue} cannot be iterated")

    let htmlBetween = p.output[match.boundaries.b+1 .. endMatch.boundaries.a-1]

    var output = ""

    for idx, value in enumerate(values):
      var iteration = htmlBetween
      let
        vars = htmlBetween.findAll(forLoopVarPattern)
        map = collect:
          for v in vars:
            {htmlBetween[v.group(0)]: v}

      if hasIndex:
        if not map.hasKey(indexName):
          raise VariableError.newException(fmt"Index value {indexName} not found")
      
        var indexMatch: RegexMatch2
        
        if not iteration.find(createLoopVarPattern(indexName), indexMatch):
          raise VariableError.newException("Couldn't find place to insert index")
        
        iteration.replace($idx, indexMatch.boundaries)
        
      var iterMatch: RegexMatch2

      if not iteration.find(createLoopVarPattern(iterationName), iterMatch):
        raise VariableError.newException(fmt"Couldn't find place to insert {iterationName}")

      iteration.replace($value, iterMatch.boundaries)

      output &= iteration

    p.output.replace(output, match.boundaries.a .. endMatch.boundaries.b)

proc parse*(p: var Parser): string {.raises: [ValidationError, VariableError, ref KeyError, RegexError].} =
  p.insertVariables()
  p.insertForLoops()

  return p.output
