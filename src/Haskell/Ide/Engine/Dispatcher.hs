{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE OverloadedStrings         #-}
{-# LANGUAGE NamedFieldPuns            #-}
{-# LANGUAGE FlexibleContexts #-}
module Haskell.Ide.Engine.Dispatcher where

import           Control.Concurrent.STM.TChan
import           Control.Concurrent
import           Control.Concurrent.STM.TVar
import           Control.Monad
import           Control.Monad.IO.Class
import           Control.Monad.Reader
import           Control.Monad.STM
import qualified Data.Map                              as Map
import qualified Data.Set                              as S
import           Haskell.Ide.Engine.MonadFunctions
import           Haskell.Ide.Engine.MonadTypes
import           Haskell.Ide.Engine.Types
import qualified Language.Haskell.LSP.Types            as J
import           System.Directory

data DispatcherEnv = DispatcherEnv
  { cancelReqsTVar     :: !(TVar (S.Set J.LspId))
  , wipReqsTVar        :: !(TVar (S.Set J.LspId))
  , docVersionTVar     :: !(TVar (Map.Map Uri Int))
  }

dispatcherP :: forall void. DispatcherEnv -> TChan PluginRequest -> IdeGhcM void
dispatcherP env inChan = do
  stateVar <- lift . lift $ ask
  gchan <- liftIO $ do
    ghcChan <- newTChanIO
    ideChan <- newTChanIO
    _ <- forkIO $ mainDispatcher inChan ghcChan ideChan
    _ <- forkIO $ runReaderT (ideDispatcher env ideChan) stateVar
    return ghcChan
  ghcDispatcher env gchan

mainDispatcher :: forall void. TChan PluginRequest -> TChan GhcRequest -> TChan IdeRequest -> IO void
mainDispatcher inChan ghcChan ideChan = forever $ do
  req <- atomically $ readTChan inChan
  case req of
    Right r ->
      atomically $ writeTChan ghcChan r
    Left r ->
      atomically $ writeTChan ideChan r

ideDispatcher :: forall void. DispatcherEnv -> TChan IdeRequest -> IdeM void
ideDispatcher env pin = forever $ do
  debugm "ideDispatcher: top of loop"
  (IdeRequest lid callback action) <- liftIO $ atomically $ readTChan pin
  debugm $ "ideDispatcher:got request with id: " ++ show lid
  cancelled <- liftIO $ atomically $ isCancelled env lid
  res <- action
  unless cancelled $
    case res of
      -- if the response is deferred
      -- first execute the callback that requires the cache to get the response
      -- then execute the callback for the request with the response
      IdeResponseDeferred uri cacheCb ->
        queueActionForModule uri $ \cm -> do
          cacheRes <- cacheCb cm
          liftIO $ callback cacheRes
      _ -> liftIO $ callback res

-- | Queues an aciton to be run after the module has been loaded
queueActionForModule :: FilePath -> (CachedModule -> IdeGhcM ()) -> IdeM ()
queueActionForModule fp action = do
  fp' <- liftIO $ canonicalizePath fp
  modifyMTS $ \s ->
    let oldQueue = actionQueue s :: Map.Map FilePath [CachedModule -> IdeGhcM ()]
        action' = action :: (CachedModule -> IdeGhcM ())
    in  s
        { actionQueue = if Map.member fp' oldQueue
                          then Map.update (Just . (action' :)) fp oldQueue
                          else Map.insert fp [action'] oldQueue
        }

ghcDispatcher :: forall void. DispatcherEnv -> TChan GhcRequest -> IdeGhcM void
ghcDispatcher env@DispatcherEnv{docVersionTVar} pin = forever $ do
  debugm "ghcDispatcher: top of loop"
  (GhcRequest context mver mid callback action) <- liftIO $ atomically $ readTChan pin
  debugm $ "got request with id: " ++ show mid

  let runner = case context of
        Nothing -> runActionWithContext Nothing
        Just uri -> case uriToFilePath uri of
          Just fp -> runActionWithContext (Just fp)
          Nothing -> \act -> do
            debugm "Got malformed uri, running action with default context"
            runActionWithContext Nothing act

  let runWithCallback = do
        r <- runner action
        liftIO $ callback r

  let runIfVersionMatch = case mver of
        Nothing -> runWithCallback
        Just (uri, reqver) -> do
          curver <- liftIO $ atomically $ Map.lookup uri <$> readTVar docVersionTVar
          if Just reqver /= curver then
            debugm "not processing request as it is for old version"
          else do
            debugm "Processing request as version matches"
            runWithCallback

  case mid of
    Nothing -> runIfVersionMatch
    Just lid -> do
      cancelled <- liftIO $ atomically $ isCancelled env lid
      if cancelled
      then
        debugm $ "cancelling request: " ++ show lid
      else do
        debugm $ "processing request: " ++ show lid
        runIfVersionMatch

-- Deletes the request from both wipReqs and cancelReqs
isCancelled :: DispatcherEnv -> J.LspId -> STM Bool
isCancelled DispatcherEnv{cancelReqsTVar,wipReqsTVar} lid = do
  modifyTVar' wipReqsTVar (S.delete lid)
  creqs <- readTVar cancelReqsTVar
  modifyTVar' cancelReqsTVar (S.delete lid)
  return $ S.member lid creqs
