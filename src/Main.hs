{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE RecordWildCards #-}
-------------------------------------------------------------------------------
-- Module    :  Main
-- Copyright :  (c) 2015-17 Marcelo Sousa
-------------------------------------------------------------------------------
module Main where

--import Benchmark
--import Exploration.UNF.Prime
--import Frontend.PetriNet
import Model.GCS 
--import Model.Interpreter
--import Printer
--import Test.Examples
--import Test.Tests
--import Unfolderful
import Control.Monad.ST
import Domain.Action
-- import Domain.Concrete
-- import Domain.Concrete.State
import Domain.Interval.Collapse
import Domain.Interval
import Exploration.UNF.Unfolder  
import Language.SimpleC
import Language.SimpleC.Util
import qualified Language.SimpleC.Printer as P
import System.Console.CmdArgs
import System.FilePath.Posix
import System.Random
import System.Process
import Test.HUnit (runTestTT)
import Util.CmdOpts
import Util.Generic
-- import Util.Printer
import qualified Data.Map as M
import qualified Data.Set as S 
import qualified Domain.Concrete.Transformers.System as CC
import qualified Domain.Interval.Transformers.System as IC
import qualified Exploration.UNF.API as US
import qualified Exploration.UNF.State as US

-- Newer version for stid
-- import Domain.Synchron
-- import Exploration.SUNF.Unfolder
-- import Exploration.SUNF.APIStid
-- import qualified Exploration.SUNF.State       as SS

-- | 'main' function 
main :: IO ()
main = do 
  options <- cmdArgsRun prog_modes
  runOption options
          
runOption :: Option -> IO ()
runOption opt = case opt of
  Frontend  f             -> frontend  f
  Execute   f dom seed    -> execute   f dom seed 
  Interpret f dom         -> interpret f dom 
  Explore   f dom stf cut w -> explore f dom (not $ toBool stf) (toBool cut) w
  Prime     f dom stf cut -> prime     f dom (not $ toBool stf) (toBool cut)
  Stid      f     stf cut -> stid      f     (not $ toBool stf) (toBool cut)
  Debug     f dom cut     -> debug     f dom (toBool cut)
  Ai        f             -> ai f 
  Test                    -> test

frontend :: FilePath -> IO ()
frontend f = do
  fe <- extract "" f
  print $ ast fe 
  let syst = IC.convert fe
      sym_table = Language.SimpleC.symt fe -- get the symbol table
      fname = fst $ splitExtension f
      dot_name = fname ++ ".dot"
  writeFile dot_name $ P.pp_dot_graphs (Language.SimpleC.cfgs fe) M.empty 
  putStrLn $ show_symt sym_table 
  putStrLn "frontend end"

execute :: FilePath -> Domain -> Int -> IO ()
execute = error "v2: working in progress"
{-    
execute f dom dseed = do
  prog <- extract f
  seed <- randomIO :: IO Int
  print $ "Using seed = " ++ show (seed,dseed)
  let (prog', fflow, flow, thcount) = frontEnd prog
  print prog'
  let gen = if dseed == 0
            then mkStdGen seed
            else mkStdGen dseed
      log = case dom of 
        Concrete -> exec gen thcount $ CC.convert prog' fflow flow thcount
        Interval -> exec gen thcount $ IC.convert prog' fflow flow thcount
  putStrLn log
-}

interpret :: FilePath -> Domain -> IO ()
interpret = error "v2: working in progress"
{-
interpret f dom = do
  prog <- extract f
  let (prog', fflow, flow, thcount) = frontEnd prog
      res = case dom of 
        Concrete -> interpret $ CC.convert prog' fflow flow thcount
        Interval -> interpret $ IC.convert prog' fflow flow thcount
  print prog'
  print res
-}

explore :: FilePath -> Domain -> Bool -> Bool -> Int -> IO ()
explore f dom stl cut wid = do
  case dom of
    --Concrete -> do
    --  fe <- extract "" f
    --  let syst = CC.convert fe 
    --  ust <- unfolder stl cut syst
    --  let (cntr, stats) = (US.cntr ust, US.stats ust)
    --  -- putStrLn $ show syst 
    --  putStrLn $ "total number of events of the unfolding: " ++ show cntr 
    --  putStrLn $ "total number of maximal configurations: " ++ show (US.nr_max_conf stats) 
    --  putStrLn $ "total number of cutoffs: " ++ show (US.nr_cutoffs stats) 
    --  putStrLn $ "average size of U at maximal configurations: " 
    --  putStrLn "explore end"
    Interval -> do 
      fe <- extract "" f
      let syst = IC.convert fe
      ust <- unfolder stl cut wid syst
      let (cntr, stats) = (US.cntr ust, US.stats ust)
      -- putStrLn $ show syst 
          outfile = replaceExtension f "log"
      putStrLn $ "total number of events of the unfolding: " ++ show cntr 
      putStrLn $ "total number of maximal configurations: " ++ show (US.nr_max_conf stats) 
      putStrLn $ "total number of cutoffs: " ++ show (US.nr_cutoffs stats) 
      putStrLn $ "average size of U at maximal configurations: " 
       ++ show (div (US.sum_size_max_conf stats) (toInteger $ US.nr_max_conf stats))
      let warns = US.nr_warns stats
      putStrLn $ show (S.size warns) ++ " warnings: " ++ show (US.nr_warns stats)
--      putStrLn $ show (cntr, stats)
--      (_,_,_,dots) <- unfToDot ust 
--      writeFile (replaceExtension f ".dot") dots
      putStrLn "explore end"
  -- print_stats cntr stats 
  -- putStrLn "Simple C generated by front-end:"
  -- print prog'
  -- putStrLn $ "events per transition map:\n" 
  --  ++ M.foldWithKey (\tr ev r -> show (snd4 tr, ev) ++ "\n" ++ r) "" evPerTr
  -- writeFile (replaceExtension f ".dot") unfst

prime :: FilePath -> Domain -> Bool -> Bool -> IO ()
prime = error "v2: working on progress"
{-
prime f dom stl cut = do 
  prog <- extract f
  let (prog', fflow, flow, thcount) = frontEnd prog
      (sys, indr) = case dom of
        Concrete -> CC.convert prog' fflow flow thcount
        Interval -> error "Interval mode not supported yet" 
      pes = runST (unfolder mode cutoffs sys indr >>= 
                   \s -> primefactor (evts s) >>= 
                   \(p,a,b,c) -> showEvents p >>= 
                   \s -> return $ s ++ show (a,b,c))
  putStrLn pes
-}

stid :: FilePath -> Bool -> Bool -> IO ()
stid f stl cut = do
  return ()
{- 
  syst <- stid_fe f
  ust  <- synfolder stl cut syst
  let (cntr, stats) = (SS.cntr ust, SS.stats ust)
  -- putStrLn $ show syst 
  stid_end syst
  putStrLn $ show (cntr, stats)
  (_,_,_,dots) <- unfToDot ust 
  writeFile (replaceExtension f ".dot") dots
  putStrLn "explore end"
-}

debug :: FilePath -> Domain -> Bool -> IO ()
debug = error "v2: working in progress"
{-
debug f dom cutoffs = do 
  prog <- extract f
  let (prog', fflow, flow, thcount) = frontEnd prog
      (sys, indr) = case dom of
        Concrete -> CC.convert prog' fflow flow thcount
        Interval -> IC.convert prog' fflow flow thcount
      pes = runST (Exp.unfolder mode cutoffs sys indr >>= 
                  \s -> showEvents $ evts s)
  putStrLn pes
-}
    
test :: IO ()
test = error "v2: working in progress"
{-
test =  do
  succCount <- runTestTT tests
  print succCount
-}

ai :: FilePath -> IO ()
ai f = do
  fe <- extract "" f
  let syst = IC.convert fe
      (warns,res) = collapse True 10 syst (gbst syst) 1
      sym_table = Language.SimpleC.symt fe -- get the symbol table
--  putStrLn $ show (gbst syst) 
      fname = fst $ splitExtension f
      dot_name = fname ++ ".dot"
      pdf_name = fname ++ ".pdf"
  writeFile dot_name $ P.pp_dot_graphs (Language.SimpleC.cfgs fe) M.empty -- sym_table
  putStrLn $ show_symt sym_table 
  putStrLn $ "Warnings: " ++ show warns
  putStrLn $ showResultList res
  -- pdf <- readProcess "dot" ["-Tpdf",dot_name] []
  -- writeFile pdf_name pdf
  putStrLn "explore end"
