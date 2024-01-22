# Package

version       = "0.1.0"
author        = "Isaac Naylor"
description   = "A new awesome nimble package"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.1.1"

requires "regex"


# Tasks

task docs, "Docs":
  exec "nim doc --project -o:./docs ./src/templater.nim"

task test, "Run all Tests":
  exec "testament all" 
  exec "testament html"