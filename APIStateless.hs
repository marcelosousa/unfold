{-#LANGUAGE RecordWildCards #-}
module APIStateless where

import Prelude hiding (succ)

import Control.Monad.State.Strict
import Control.Monad.ST.Safe

-- Data Structures
import qualified Data.HashTable.ST.Cuckoo as C
import qualified Data.HashTable.Class as H
import qualified Data.Set as S
import qualified Data.Maybe as M
import Data.List

import qualified Model as ML

import Debug.Trace 

-- @ The most basic type is event_id :: Int
--   Pointer to an event
type EventID = Int
type EventsID = [EventID]

-- @ Configuration  
data Configuration s = Conf {
    stc :: ML.Sigma s   -- state at this configuration
  , maxevs :: EventsID  -- maximal events of the configuration
  , enevs  :: EventsID  -- enabled events of the configuration
  , cevs   :: EventsID  -- special events: the ones that have imm conflicts
}

-- @ An alternative is a conflicting extension of the configuration
--   that is being/was explored. 
type Alternative = EventsID
type Alternatives = [Alternative]
type Counter = Int

-- @ Value of the main HashTable
--   (transition_id, predecessors, successors, #^, D, V)
data Event = Event {
    evtr :: ML.TransitionID  -- Transition id
  , pred :: EventsID         -- Immediate predecessors
  , succ :: EventsID         -- Immediate successors
  , icnf :: EventsID         -- Immediate conflicts: #^
  , disa :: EventsID         -- Disabled events: D
  , alte :: Alternatives     -- Valid alternatives: V
} deriving (Show,Eq,Ord)

-- @ Events represents the unfolding prefix as LPES
--   with a HashTable : EventID -> Event 
type Events s = ML.HashTable s EventID Event

-- @ The state of the unfolder at any moment
data UnfolderState s = UnfolderState {
    syst :: ML.System s      -- The system being analyzed
  , inde :: ML.UIndep        -- Independence relation
  , evts :: Events s         -- Unfolding prefix 
  , pcnf :: Configuration s  -- Previous configuration
  , cntr :: Counter          -- Event counter
}

-- @ Abbreviation of the type of an operation of the unfolder
type UnfolderOp s a = StateT (UnfolderState s) (ST s) a

-- @ Bottom event and event_id
botEID :: EventID
botEID = 0

botEvent :: Event
botEvent = Event ML.botID [] [] [] [] []

-- @ Initial state of the unfolder
iState :: ML.System s -> ML.UIndep -> ST s (UnfolderState s) 
iState sys indep = do
  events <- H.new
  H.insert events 0 botEvent
  let pconf = Conf undefined [] [] []
  return $ UnfolderState sys indep events pconf 1

beg = "--------------------------------\n BEGIN Unfolder State          \n--------------------------------\n"
end = "\n--------------------------------\n END   Unfolder State          \n--------------------------------\n"
instance Show (UnfolderState s) where
    show (u@UnfolderState{..}) = "" 
--        beg ++ "UIndep: " ++ show indep ++ "\nEvents: " ++ show events ++ "\nCausality: " ++ show causality 
--     ++ "\n" ++ show (cevs configurations) ++ "\nEnabled: " ++ show enable 
--     ++ "\nDisable: " ++ show disable ++ "\nAlternatives: " ++ show alternatives  ++ "\nImmConflicts: " ++ show immediateConflicts ++ "\nCounters: " 
--     ++ show counters ++ end

{-
gc :: UnfolderState -> UnfolderState
gc s@UnfolderState{..} = 
  let nevents = 0:(M.foldrWithKey (\e alts r -> nub $ e:(concat alts) ++ r) [] alternatives)
      events' = M.filterWithKey (\eID _ -> eID `elem` nevents) events
      causality' = filter (\(e1,e2) -> e1 `elem` nevents && e2 `elem` nevents) causality
      immediateCnfls = M.filterWithKey (\eID _ -> eID `elem` nevents) immediateConflicts
  in UnfolderState system indep events' configurations causality' enable disable alternatives immediateCnfls counters
-}

-- @ Given the state s and an enabled event e, execute s e
--   is going to apply h(e) to s to produce the new state s'
execute :: ML.Sigma s -> EventID -> UnfolderOp s (ML.Sigma s)
execute cst e = do
  s@UnfolderState{..} <- get
  ev@Event{..} <- lift $ getEvent "execute" e evts 
  let t = ML.getTransition syst evtr
  fn <- lift $ (t cst >>= return . M.fromMaybe (error $ "newState: the transition was not enabled " ++ show cst))
  lift $ fn cst

-- Check if two events are concurrent
-- Need to optimise this function: this is very inneficient!
-- The standard definition is: e || e' iff not (e < e' || e' < e || e # e')
-- TODO: FIX THIS FUNCTION
isConcurrent :: EventID -> EventID -> UnfolderOp s Bool
isConcurrent e e' = do
  s@UnfolderState{..} <- get
  prede  <- lift $ predecessors e  evts
  prede' <- lift $ predecessors e' evts
  let eprede  = e:prede
      eprede' = e':prede' 
      -- imd conflicts of all prede cfle = fromMaybe [] $ M.lookup e immediateConflicts
      -- imd conflicts of all prede'
      -- check that e is not an imd clf of any prede' and vice versa
  return $ not $ e' `elem` prede || e `elem` prede' -- missing cnfl part

-- This can be removed
isDependent :: ML.UIndep -> Events s -> ML.TransitionID -> EventID -> ST s Bool
{-# INLINE isDependent #-}
isDependent indep events tr e = do
    ev@Event{..} <- getEvent "isDependent" e events
    return $ ML.isDependent indep tr evtr

-- Useful Functions
predecessors, successors :: EventID -> Events s -> ST s EventsID
{-# INLINABLE predecessors #-}
predecessors e events = do
  preds <- predecessors' e events
  return $ nub preds 
 where
  predecessors' :: EventID -> Events s -> ST s EventsID
  predecessors' e events = do
     ev@Event{..} <- getEvent "predecessors" e events 
     foldM (\a e -> predecessors' e events >>= \r -> return $ a ++ r) pred pred
{-# INLINABLE successors #-}
successors e events = do 
  succs <- successors' e events
  return $ nub succs 
 where
  successors' :: EventID -> Events s -> ST s EventsID
  successors' e events = do
     ev@Event{..} <- getEvent "successors" e events 
     foldM (\a e -> successors' e events >>= \r -> return $ a ++ r) succ succ

 
-- path from e to e' in the causality
-- path :: Causality -> EventID -> EventID -> Bool
-- path = undefined

-- GETTERS
-- retrieves the event associated with the event id 
getEvent :: String -> EventID -> Events s -> ST s Event
{-# INLINE getEvent #-}
getEvent s e events =
  H.lookup events e >>= return . M.fromMaybe (error $ s ++ "-getEvent:") 

-- @ getConfEvs - retrieves all the events of a configuration
getConfEvs :: EventsID -> Events s -> ST s EventsID
getConfEvs maxevs events = undefined
    
getImmediateConflicts :: EventID -> Events s -> ST s EventsID
getImmediateConflicts = undefined 

getDisabled :: EventID -> UnfolderOp s EventsID
getDisabled = undefined

-- SETTERS

setEvent :: EventID -> Event -> Events s -> ST s ()
setEvent eID e events = H.insert events eID e

-- @ setSuccessor e -> e'
setSuccessor :: EventID -> EventID -> Events s -> ST s ()
setSuccessor e e' events = do
  ev@Event{..} <- getEvent "setSuccessor" e' events
  let succEv = e:succ
      ev' = ev{ succ = succEv } 
  setEvent e' ev' events 

setConflict :: EventID -> EventID -> Events s -> ST s ()
setConflict e e' events = do
  ev@Event{..} <- getEvent "setConflict" e' events
  let icnfEv = e:icnf
      ev' = ev{ icnf = icnfEv }
  setEvent e' ev' events 

addDisable :: EventID -> EventID -> UnfolderOp s ()
addDisable = undefined
{-
addDisable :: EventID -> EventID -> State (UnfolderState s) ()
addDisable ê e = do  -- trace ("addDisable: " ++ show ê ++ " " ++ show e) $ do
    s@UnfolderState{..} <- get
    let dis = M.alter (addDisableAux e) ê disable
    put s{ disable = dis}

addDisableAux :: EventID -> Maybe EventsID -> Maybe EventsID
addDisableAux e Nothing = Just $ [e]
addDisableAux e (Just d) = Just $ e:d
-}
-- @ freshCounter - updates the counter of events
freshCounter :: UnfolderOp s Counter
freshCounter = do
  s@UnfolderState{..} <- get
  let ec = cntr
      nec = ec + 1
  put s{ cntr = nec }
  return ec
