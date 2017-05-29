{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-------------------------------------------------------------------------------
-- Module    :  Domain.Concrete
-- Copyright :  (c) 2017 Marcelo Sousa
--
-- Collapse for concrete semantics:
--  This will amount to execute the current edge in the CFG
--  Optimize to execute all local executions 
-------------------------------------------------------------------------------
module Domain.Concrete () where

import Control.Monad.State.Lazy
import Data.List
import Data.Map (Map)
import Data.Set (Set)
import Domain.Action
import Domain.Class
import Domain.Concrete.API (update_pc, read_memory)
import Domain.Concrete.State
import Domain.Concrete.Transformers.Declaration (transformer_decl)
import Domain.Concrete.Transformers.Expression (transformer_expr)
import Domain.Concrete.Transformers.State
import Domain.Concrete.Transformers.Statement (get_addrs_expr, get_tid_expr, has_exited, is_locked)
import Domain.Concrete.Value
import Domain.Util
import Language.SimpleC.AST
import Language.SimpleC.Converter (get_symbol_name)
import Language.SimpleC.Flow hiding (trace)
import Language.SimpleC.Util hiding (cfgs,symt)
import Model.GCS
import Util.Generic 
import qualified Data.Map as M
import qualified Data.Set as S

type ConGraph      = CGraph     ConState ConAct
type ConGraphs     = CGraphs    ConState ConAct
type ConResultList = ResultList ConState ConAct
type ConNodeTable  = NodeTable  ConState ConAct
type ConFixOp val  = FixOp      ConState ConAct val

instance Domain ConState ConAct where
  is_enabled       = is_enabled_con
  code_transformer = code_transformer_con
  weak_update      = weak_update_con
  strong_update    = strong_update_con
  loop_head_update = loop_head_update_con   
  run              = run_con
  
-- Enabledness transformer for Interval State
is_enabled_con :: System ConState ConAct -> ConState -> TId -> Bool
is_enabled_con syst st tid =
  let control     = controlPart st
      tid_cfg_sym = toThCFGSym st tid
  in case M.lookup tid control of
       Nothing  -> False
       Just pos -> case M.lookup tid_cfg_sym (cfgs syst) of 
         Nothing  -> error $ "is_enabled fatal: tid " ++ show tid ++ " not found in cfgs"
         Just cfg -> case succs cfg pos of
           [] -> False
           s  -> any (\(eId,nId) -> is_live tid syst eId cfg st) s

-- | Instead of just looking at the immediate edge, one needs to potentially
--   traverse the graph until reaching a global action. Only at those leafs
--   one can compute the right result with respect to enabledness.
--   I will opt to not implement such procedure and generate events that are 
--   potentially only local.
is_live :: TId -> System ConState ConAct -> EdgeId -> ConGraph -> ConState -> Bool
is_live tid syst eId cfg st = 
  let EdgeInfo tags code = get_edge_info cfg eId 
  in case code of
    E (Call fname args _) -> case fname of
      Var ident -> case get_symbol_name ident (symt syst) of
        "pthread_join" ->
          let tid' = get_tid_expr (Local tid) st (args!!0) 
           -- not exited
          -- in not $ is_enabled syst st tid' 
          in has_exited (cfgs syst) st tid' 
         -- assume the mutex is declared globally 
        "pthread_mutex_lock" -> not $ is_locked st (Local tid) (args!!0)
        _ -> True 
      _ -> True
    _ -> True             
       
code_transformer_con       = undefined
weak_update_con            = undefined
strong_update_con          = undefined
loop_head_update_con       = undefined
run_con                    = undefined
    
{-      
  -- call collapse on the thread tid
  collapse b wid syst@System{..} st tid = 
    let control = controlPart st
        pos = case M.lookup tid control of
          Nothing -> error $ "collapse: tid " ++ show tid ++ " is not control"
          Just p  -> p
        th_cfg_sym = case M.lookup tid (cs_tstates st) of
          Nothing -> error $ "collapse: cant find thread in " ++ show tid
          Just th_st -> th_cfg_id th_st 
        th_cfg = case M.lookup th_cfg_sym cfgs of
          Nothing -> error $ "collapse: cant find thread " ++ show th_cfg_sym
          Just cfg -> cfg 
    in mytrace False ("collapse: fixpoint of thread "++show tid ++ ", position = " ++ show pos) $
       let res = undefined --fixpt wid syst b tid cfgs symt th_cfg pos st
       in mytrace False "collapse: end" res
-}
