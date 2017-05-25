{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-------------------------------------------------------------------------------
-- Module    :  Domain.Collapse
-- Copyright :  (c) 2017 Marcelo Sousa
--
-- General thread analysis:
--  Naive abstract interpretation fixpoint
--  based on a worklist algorithm
-------------------------------------------------------------------------------
module Domain.Collapse where

import qualified Data.Map as M

import Language.SimpleC.AST
import Model.GCS

-- | General datatypes for the collapse
type CGraph     s a = Graph  SymId () (s,a)
type CGraphs    s a = Graphs SymId () (s,a)
type ResultList s a = [(s,Pos,a)]
type NodeTable  s a = Map NodeId [(s,a)]
type WItem          = (NodeId,EdgeId,NodeId)
type Worklist       = [WItem]
         
data FixState s a =
  FixState
  {
  -- fs_mode=True returns the annotated CFG; fs_mode=False returns the final res
    fs_mode :: Bool 
  -- thread/process/function ID 
  , fs_tid  :: TId 
  , fs_cfgs :: CGraphs s a
  , fs_symt :: SymbolTable
  , fs_cfg  :: CGraph s a
  -- final worklist: every edge in this worklist is a global action 
  , fs_mark :: Set WItem
  -- map from loop heads to counter of traversals.  
  , fs_wide :: Map NodeId Int
  -- widening level
  , fs_wid  :: Int 
  }

type FixOp s a val = State (FixState s a) val

-- | API FOR STATE
get_widening_level :: FixOp s a Int
get_widening_level = do
  fs@FixState{..} <- get
  return fs_wid

inc_wide_node :: NodeId -> FixOp s a ()
inc_wide_node node_id = do
  fs@FixState{..} <- get
  let fs_wide' = case M.lookup node_id fs_wide of
        Nothing -> M.insert node_id 1 fs_wide
        Just n  -> M.insert node_id (n+1) fs_wide
  put fs { fs_wide = fs_wide' } 

get_wide_node :: NodeId -> FixOp s a Int
get_wide_node node_id = do
  fs@FixState{..} <- get
  case M.lookup node_id fs_wide of
    Nothing -> return 0
    Just n  -> return n 

add_mark :: WItem -> FixOp s a ()
add_mark i = do 
  fs@FixState{..} <- get
  let fs_mark' = S.insert i fs_mark
  put fs { fs_mark = fs_mark' }

update_node_table :: NodeTable s a -> FixOp s a (CGraph s a)
update_node_table node_table' = do 
  fs@FixState{..} <- get
  let cfg = fs_cfg { node_table = node_table' }
  put fs { fs_cfg = cfg }
  return cfg

-- @TODO: PROBLEM HERE!
up_pc :: s -> TId -> Pos -> s
up_pc i@IntTState{..} t p =
  let st' = update_pc st t p
  in i {st = st'} 

-- | main fixpoint function
fixpt :: Show s => Int -> System s a -> Bool -> TId -> CGraphs s a -> SymbolTable -> CGraph s a -> Pos -> s -> (Set Int, ResultList s a)
fixpt wid syst b tid cfgs symt cfg@Graph{..} pos st =
  mytrace False ("fixpt: tid = " ++ show tid ++ " \n" ++ show st) $ 
  -- reset the node table information with the information passed
  let node_table' = M.insert pos [(st,bot_act)] $ M.map (const []) node_table
      cfg' = cfg { node_table = node_table' }
      wlist = map (\(a,b) -> (pos,a,b)) $ succs cfg' pos
      i_fix_st = FixState b tid cfgs symt cfg' S.empty M.empty wid 
      res = mytrace False ("fixpt: cfg = " ++ show ( node_table' :: NodeTable )) $ evalState (worklist S.empty syst wlist) i_fix_st
  in res 


handle_mark :: WItem -> FixOp (Set Int, (IntState,Pos,IntAct))
handle_mark (pre,eId,post) = mytrace False ("handle_mark: " ++ show (pre,eId,post)) $ do
  fs@FixState{..} <- get
  let (node_st, pre_acts) = case get_node_info fs_cfg pre of
        [s] -> s
        l   -> error $ "handle_mark invalid pre states: " ++ show l
      -- get the edge info
      e@EdgeInfo{..} = mytrace False ("handle_mark: " ++ show node_st) $ get_edge_info fs_cfg eId
      -- construct the transformer state
      tr_st = IntTState (Local fs_tid) node_st fs_symt fs_cfgs (is_cond edge_tags) pre S.empty
      -- decide based on the type of edge which transformer to call
      (post_acts,_ns) = case edge_code of
        -- execute the transformer
        D decl -> runState (transformer_decl decl) tr_st 
        E expr -> runState (transformer_expr expr) tr_st
      ns@IntTState{..} = up_pc _ns fs_tid post 
      acts = pre_acts `join_act` post_acts
  (is_fix,node_table') <- case edge_tags of
    -- loop head point 
    [LoopHead] -> loop_head_update (node_table fs_cfg) post (st,acts)
    -- join point: join the info in the cfg 
    [IfJoin] -> return $ join_update (node_table fs_cfg) post (st,acts) 
    -- considering everything else the standard one: just replace 
    -- the information in the cfg and add the succs of post to the worklist
    _ -> return $ strong_update (node_table fs_cfg) post (st,acts) 
  cfg' <- update_node_table node_table'
  -- find the final result of the post
  case M.lookup post $ node_table cfg' of
    Just [(res_st,res_act)] -> do
      let rwlst = map (\(a,b) -> (post,a,b)) $ succs fs_cfg post
          e_act = exit_thread_act (SymId fs_tid) zero
      if (Exit `elem` edge_tags) || null rwlst
      then return (warns, (res_st,post,res_act `join_act` e_act))
      else return (warns, (res_st,post,res_act))
    _ -> error "handle_mark: unexcepted value in the final node_table"

fixpt_result :: Set Int -> FixOp (Set Int, ResultList)
fixpt_result _warns = do
  fs@FixState{..} <- get
  let marks = S.toList fs_mark
  _res <- mytrace False ("fixpt_result: marks = " ++ show marks) $ mapM handle_mark marks
  let (ws,res) = unzip _res 
      warns = S.unions (_warns:ws)
  if fs_mode
  then do 
    fs@FixState{..} <- get
    let table = node_table fs_cfg
        nodes = M.filterWithKey (\k _ -> not $ any (\(_,p,_) -> p == k) res) table
        nodes_res = M.foldWithKey (\p l r -> map (\(a,b) -> (a,p,b)) l ++ r) [] nodes 
    return (warns, res ++ nodes_res) 
  else return (warns, res)

-- standard worklist algorithm
--  we have reached a fixpoint when the worklist is empty
worklist :: Set Int -> System IntState IntAct -> Worklist -> FixOp (Set Int, ResultList) 
worklist _warns syst _wlist = mytrace False ("worklist: " ++ show _wlist) $ do
  fs@FixState{..} <- get
  case _wlist of
    [] -> fixpt_result _warns 
    (it@(pre,eId,post):wlist) -> do
      -- get the current state in the pre
      let (node_st, pre_acts) = case get_node_info fs_cfg pre of
            [s] -> s
            l   -> error $ "worklist invalid pre states: " ++ show l
          -- get the edge info
          e@EdgeInfo{..} = get_edge_info fs_cfg eId
          -- construct the transformer state
          tr_st = IntTState (Local fs_tid) node_st fs_symt fs_cfgs (is_cond edge_tags) pre _warns
          -- decide based on the type of edge which transformer to call
          (post_acts,_ns) = case edge_code of
            -- execute the transformer
            D decl -> runState (transformer_decl decl) tr_st 
            E expr -> runState (transformer_expr expr) tr_st
          rwlst = map (\(a,b) -> (post,a,b)) $ succs fs_cfg post
          -- join the actions of the predecessors with the actions of the current edge
          acts = pre_acts `join_act` post_acts
          ns = up_pc _ns fs_tid post 
          n_warns = warns _ns
      -- depending on whether the action is global or not;
      -- either add the results to the result list or update
      -- the cfg with them 
      if is_bot (st ns)
      then mytrace False ("worklist: current edge returns bottom") $ worklist n_warns syst wlist
      else if isGlobal acts || (Exit `elem` edge_tags) || null rwlst 
           then mytrace False ("is a global operation") $ do
             add_mark it
             worklist n_warns syst wlist
           else mytrace False ("worklist: returned state\n" ++ show (st ns)) $ do 
             -- depending on the tags of the edge; the behaviour is different
             (is_fix,node_table') <-
                  case edge_tags of
                    -- loop head point 
                    [LoopHead] -> loop_head_update (node_table fs_cfg) post (st ns,acts)
                    -- join point: join the info in the cfg 
                    [IfJoin] -> return $ join_update (node_table fs_cfg) post (st ns,acts) 
                    -- considering everything else the standard one: just replace 
                    -- the information in the cfg and add the succs of post to the worklist
                    _ -> return $ strong_update (node_table fs_cfg) post (st ns,acts) 
             cfg' <- update_node_table node_table'
             let nwlist = if is_fix then wlist else (wlist ++ rwlst)
             worklist n_warns syst nwlist
            -- disabled_rwlst <- filterM (check_enabledness_succ syst) rwlst
            -- -- @NOTE: If one the sucessors is not enabled then
            -- -- simply mark it as a final node
            -- if not $ null disabled_rwlst
            -- then mytrace False ("worklist: non-global event!") $ do
            --   add_mark it
            --   worklist syst wlist
            -- else worklist syst nwlist

-- | Returns true if the current edge is disabled
check_enabledness_succ :: System IntState IntAct -> (NodeId, EdgeId, NodeId) -> FixOp Bool 
check_enabledness_succ syst (pre,eId,post) = do 
  fs@FixState{..} <- get
  let (node_st, pre_acts) = case get_node_info fs_cfg pre of
        [s] -> s
        l   -> error $ "check_enabledness_succ: invalid pre states = " ++ show l
  return $ not $ is_live fs_tid syst eId fs_cfg node_st

loop_head_update :: NodeTable -> NodeId -> (IntState, IntAct) -> FixOp (Bool, NodeTable)
loop_head_update node_table node (st,act) =  do
  c <- get_wide_node node
  inc_wide_node node
  w <- get_widening_level
  if c >= w 
  then mytrace False ("loop_head_update: going to apply widening") $ do 
    case M.lookup node node_table of
      -- error "loop_head_update: widening between a state and empty?" 
      Nothing ->  return $ (False, M.insert node [(st,act)] node_table)
      Just lst -> case lst of
        [] -> error "loop_head_update: widening between a state and empty?" 
        [(st',act')] ->
          let nst = st' `widen_intstate` st
              nact = act `join_act` act'
          in if nst == st'
             then return $ (True, node_table)
             else return $ (False, M.insert node [(nst,nact)] node_table)
        _ -> error "loop_head_update: widening between a state and several states?" 
  else do
    mytrace False ("loop_head_update: not going to apply widening " ++ show c) $ return $ join_update node_table node (st,act) 

join_update :: NodeTable -> NodeId -> (IntState, IntAct) -> (Bool, NodeTable)
join_update node_table node (st,act) =
  case M.lookup node node_table of
    Nothing -> (False, M.insert node [(st,act)] node_table)
    Just lst -> case lst of
      [] -> (False, M.insert node [(st,act)] node_table)
      [(st',act')] ->
        let nst = st `join_intstate` st'
            nact = act `join_act` act'
        in mytrace False ("join_update: old state:\n" ++ show st' ++ "join_update: new state\n" ++ show st ++ "join_update:join state\n" ++ show nst) $ if nst == st'
           then (True, node_table)
           else (False, M.insert node [(nst,nact)] node_table)
      _ -> error "join_update: more than one state in the list"
 
strong_update :: NodeTable -> NodeId -> (IntState,IntAct) -> (Bool, NodeTable)
strong_update node_table node (st,act) = mytrace False ("strong_update: node = " ++ show node ++ ", state\n" ++ show st) $
  case M.lookup node node_table of
    Nothing -> (False, M.insert node [(st,act)] node_table) 
    Just lst -> case lst of
      [] -> (False, M.insert node [(st,act)] node_table)
      [(st',act')] ->
        if st == st'
        then (True, node_table)
        else (False, M.insert node [(st,act `join_act` act')] node_table)
      _ -> error "strong_update: more than one state in the list" 
      
-- | Pretty Printing
showResultList :: ResultList -> String
showResultList l = 
 "Data Flow Information:\n" ++ (snd $ foldr (\(s,p,a) (n,r) -> 
   let s_a = "CFG Node: " ++ show p ++ "\n"
       s_r = s_a ++ show s
   in (n+1, s_r ++ r))  (1,"") l)
