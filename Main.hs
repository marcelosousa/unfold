module Main where

import Unfolderful
import Unfolderless
import Printer
import Examples
import Benchmark
import Model
import PetriNet
import qualified Data.Map as M

writeUnf :: (System, UIndependence) -> IO ()
writeUnf (sys,ind) =
    let unf@(pes@(events,_,_), cfs) = unfolder (sys,ind)
        (mcs,menv) = maximalEvents sys unf
        s =  printUnf menv unf
    in do 
     writeFile "unf.dot" s
     putStrLn "Maximal Configurations"
     putStrLn $ printConfigurations mcs
     putStrLn "All Configurations"
     putStrLn $ printConfigurations cfs
     putStrLn "List of Events"
     putStrLn $ M.foldWithKey (printEvent []) "" events

main :: IO ()
main =  run "benchmarks/debug/sdl_example.pt"
--  print $ stateless fib_bench_false ind_fib_bench_false 

runPT :: FilePath -> IO ()
runPT file = do
  (sys@(trs,i),ind) <- getSysInd file
  let sts = runSys' sys [i] []
      sts' = map (fst . unzip . M.toList) $ sortSigmas sts
      s = foldr (\s r -> init (show' s) ++ "\n" ++ r) "" sts'
  putStrLn s
  writeFile (file++".debug") s
  -- print $ stateless sys ind

run :: FilePath -> IO ()
run file = do
  (sys@(trs,i),ind) <- getSysInd file
  print $ stateless sys ind

show' :: [String] -> String
show' [] = ""
show' ((c:x):xs) = (init x) ++ " " ++ show' xs
