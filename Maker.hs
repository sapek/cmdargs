{-# LANGUAGE DeriveDataTypeable #-}

module Maker where

import System.Console.CmdArgs


data Maker
    = Wipe
    | Test {threads :: Int {- , extra :: [String] -} }
    | Build {threads :: Int, profile :: Bool, files :: [FilePath]}
      deriving (Data,Typeable,Show,Eq)


threadsMsg x = x & text "Number of threads to use" & flag "j"


wipe = mode $ Wipe & text "Clean all build objects"

test = mode $ Test
    {threads = threadsMsg def
    -- ,extra = def & typ "ANY" & args & unknownFlags
    } & text "Run the test suite"

build = mode $ Build
    {threads = threadsMsg def
    ,profile = def & text "Run in profiling mode"
    ,files = def & args
    } & text "Build stuff" & defMode

modes = [build,wipe,test]

main = print =<< cmdModes "Maker v1.0" modes