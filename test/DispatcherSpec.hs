{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PolyKinds #-}
module DispatcherSpec where

import           Control.Concurrent
import           Control.Concurrent.STM.TChan
import           Control.Monad.IO.Class
import           Control.Monad.STM
import           Data.Aeson
import qualified Data.HashMap.Strict as H
import qualified Data.HashMap.Strict as HM
import qualified Data.Map as Map
import qualified Data.Text as T
import           Haskell.Ide.Engine.Dispatcher
import           Haskell.Ide.Engine.Monad
import           Haskell.Ide.Engine.MonadFunctions
import           Haskell.Ide.Engine.PluginDescriptor
import           Haskell.Ide.Engine.Types

import           Test.Hspec

-- ---------------------------------------------------------------------

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  describe "dispatcher" dispatcherSpec

-- -- |Used when running from ghci, and it sets the current directory to ./tests
-- tt :: IO ()
-- tt = do
--   cd ".."
--   hspec spec

-- ---------------------------------------------------------------------

dispatcherSpec :: Spec
dispatcherSpec = do
  describe "checking contexts" $ do

    it "identifies CtxNone" $ do
      chan <- atomically newTChan
      chSync <- atomically newTChan
      let req = IdeRequest "cmd1" (Map.fromList [])
          cr = CReq "test" 1 req chan
      r <- withStdoutLogging $ runIdeM (IdeState Map.empty Map.empty) (doDispatch (testPlugins chSync) cr)
      r `shouldBe` Just (IdeResponseOk (H.fromList ["ok" .= ("result:ctxs=[CtxNone]"::String)]))

    -- ---------------------------------

    it "identifies bad CtxFile" $ do
      chan <- atomically newTChan
      chSync <- atomically newTChan
      let req = IdeRequest "cmd2" (Map.fromList [])
          cr = CReq "test" 1 req chan
      r <- withStdoutLogging $ runIdeM (IdeState Map.empty Map.empty) (doDispatch (testPlugins chSync) cr)
      r `shouldBe` Just (IdeResponseFail (IdeError {ideCode = MissingParameter, ideMessage = "need `file` parameter", ideInfo = String "file"}))

    -- ---------------------------------

    it "identifies CtxFile" $ do
      chan <- atomically newTChan
      chSync <- atomically newTChan
      let req = IdeRequest "cmd2" (Map.fromList [("file", ParamFileP "foo.hs")])
          cr = CReq "test" 1 req chan
      r <- withStdoutLogging $ runIdeM (IdeState Map.empty Map.empty) (doDispatch (testPlugins chSync) cr)
      r `shouldBe` Just (IdeResponseOk (H.fromList ["ok" .= ("result:ctxs=[CtxFile]"::String)]))

    -- ---------------------------------

    it "identifies CtxPoint" $ do
      chan <- atomically newTChan
      chSync <- atomically newTChan
      let req = IdeRequest "cmd3" (Map.fromList [("file", ParamFileP "foo.hs"),("start_pos", ParamPosP (1,2))])
          cr = CReq "test" 1 req chan
      r <- withStdoutLogging $ runIdeM (IdeState Map.empty Map.empty) (doDispatch (testPlugins chSync) cr)
      r `shouldBe` Just (IdeResponseOk (H.fromList ["ok" .= ("result:ctxs=[CtxPoint]"::String)]))

    -- ---------------------------------

    it "identifies CtxRegion" $ do
      chan <- atomically newTChan
      chSync <- atomically newTChan
      let req = IdeRequest "cmd4" (Map.fromList [("file", ParamFileP "foo.hs")
                                                ,("start_pos", ParamPosP (1,2))
                                                ,("end_pos", ParamPosP (3,4))])
          cr = CReq "test" 1 req chan
      r <- withStdoutLogging $ runIdeM (IdeState Map.empty Map.empty) (doDispatch (testPlugins chSync) cr)
      r `shouldBe` Just (IdeResponseOk (H.fromList ["ok" .= ("result:ctxs=[CtxRegion]"::String)]))

    -- ---------------------------------

    it "identifies CtxCabal" $ do
      chan <- atomically newTChan
      chSync <- atomically newTChan
      let req = IdeRequest "cmd5" (Map.fromList [("cabal", ParamTextP "lib")])
          cr = CReq "test" 1 req chan
      r <- withStdoutLogging $ runIdeM (IdeState Map.empty Map.empty) (doDispatch (testPlugins chSync) cr)
      r `shouldBe` Just (IdeResponseOk (H.fromList ["ok" .= ("result:ctxs=[CtxCabalTarget]"::String)]))


    -- ---------------------------------

    it "identifies CtxProject" $ do
      chan <- atomically newTChan
      chSync <- atomically newTChan
      let req = IdeRequest "cmd6" (Map.fromList [("dir", ParamFileP ".")])
          cr = CReq "test" 1 req chan
      r <- withStdoutLogging $ runIdeM (IdeState Map.empty Map.empty) (doDispatch (testPlugins chSync) cr)
      r `shouldBe` Just (IdeResponseOk (H.fromList ["ok" .= ("result:ctxs=[CtxProject]"::String)]))

    -- ---------------------------------

    it "identifies all multiple" $ do
      chan <- atomically newTChan
      chSync <- atomically newTChan
      let req = IdeRequest "cmdmultiple" (Map.fromList [("file", ParamFileP "foo.hs")
                                                       ,("start_pos", ParamPosP (1,2))
                                                       ,("end_pos", ParamPosP (3,4))])
          cr = CReq "test" 1 req chan
      r <- withStdoutLogging $ runIdeM (IdeState Map.empty Map.empty) (doDispatch (testPlugins chSync) cr)
      r `shouldBe` Just (IdeResponseOk (H.fromList ["ok" .= ("result:ctxs=[CtxFile,CtxPoint,CtxRegion]"::String)]))

    -- ---------------------------------

    it "identifies CtxFile,CtxPoint multiple" $ do
      chan <- atomically newTChan
      chSync <- atomically newTChan
      let req = IdeRequest "cmdmultiple" (Map.fromList [("file", ParamFileP "foo.hs")
                                                       ,("start_pos", ParamPosP (1,2))])
          cr = CReq "test" 1 req chan
      r <- withStdoutLogging $ runIdeM (IdeState Map.empty Map.empty) (doDispatch (testPlugins chSync) cr)
      r `shouldBe` Just (IdeResponseOk (H.fromList ["ok" .= ("result:ctxs=[CtxFile,CtxPoint]"::String)]))

    -- ---------------------------------

    it "identifies error when no match multiple" $ do
      chan <- atomically newTChan
      chSync <- atomically newTChan
      let req = IdeRequest "cmdmultiple" (Map.fromList [("cabal", ParamTextP "lib")])
          cr = CReq "test" 1 req chan
      r <- withStdoutLogging $ runIdeM (IdeState Map.empty Map.empty) (doDispatch (testPlugins chSync) cr)
      r `shouldBe`
        Just (IdeResponseFail (IdeError { ideCode = MissingParameter
                                        , ideMessage = "need `file` parameter"
                                        , ideInfo = String "file"}))

  -- -----------------------------------

  describe "checking extra params" $ do

    it "identifies matching params" $ do
      chan <- atomically newTChan
      chSync <- atomically newTChan
      let req = IdeRequest "cmdextra" (Map.fromList [("file", ParamFileP "foo.hs")
                                                    ,("txt",  ParamTextP "a")
                                                    ,("file", ParamFileP "f")
                                                    ,("pos",  ParamPosP (1,2))
                                                    ])
          cr = CReq "test" 1 req chan
      r <- withStdoutLogging $ runIdeM (IdeState Map.empty Map.empty) (doDispatch (testPlugins chSync) cr)
      r `shouldBe` Just (IdeResponseOk (H.fromList ["ok" .= ("result:ctxs=[CtxFile]"::String)]))


    -- ---------------------------------

    it "reports mismatched param" $ do
      chan <- atomically newTChan
      chSync <- atomically newTChan
      let req = IdeRequest "cmdextra" (Map.fromList [("file", ParamFileP "foo.hs")
                                                    ,("txt",  ParamFileP "a")
                                                    ,("file", ParamFileP "f")
                                                    ,("pos",  ParamPosP (1,2))
                                                    ])
          cr = CReq "test" 1 req chan
      r <- withStdoutLogging $ runIdeM (IdeState Map.empty Map.empty) (doDispatch (testPlugins chSync) cr)
      r `shouldBe`
         Just (IdeResponseFail
               (IdeError
                 { ideCode = IncorrectParameterType
                 , ideMessage = "got wrong parameter type for `txt`, expected: PtText , got:ParamValP {unParamValP = ParamFile \"a\"}"
                 , ideInfo = Object (HM.fromList [("value",String "ParamValP {unParamValP = ParamFile \"a\"}"),("param",String "txt"),("expected",String "PtText")])}))



    -- ---------------------------------

    it "reports matched optional param" $ do
      chan <- atomically newTChan
      chSync <- atomically newTChan
      let req = IdeRequest "cmdoptional" (Map.fromList [("txt",   ParamTextP "a")
                                                       ,("fileo", ParamFileP "f")
                                                       ,("poso",  ParamPosP (1,2))
                                                       ])
          cr = CReq "test" 1 req chan
      r <- withStdoutLogging $ runIdeM (IdeState Map.empty Map.empty) (doDispatch (testPlugins chSync) cr)
      r `shouldBe` Just (IdeResponseOk (H.fromList ["ok" .= ("result:ctxs=[CtxNone]"::String)]))

    -- ---------------------------------

    it "reports mismatched optional param" $ do
      chan <- atomically newTChan
      chSync <- atomically newTChan
      let req = IdeRequest "cmdoptional" (Map.fromList [("txt",   ParamTextP "a")
                                                       ,("fileo", ParamTextP "f")
                                                       ,("poso",  ParamPosP (1,2))
                                                       ])
          cr = CReq "test" 1 req chan
      r <- withStdoutLogging $ runIdeM (IdeState Map.empty Map.empty) (doDispatch (testPlugins chSync) cr)
      r `shouldBe`
        Just (IdeResponseFail
              (IdeError { ideCode = IncorrectParameterType
                        , ideMessage = "got wrong parameter type for `fileo`, expected: PtFile , got:ParamValP {unParamValP = ParamText \"f\"}"
                        , ideInfo = Object (HM.fromList [("value"
                                                      ,String "ParamValP {unParamValP = ParamText \"f\"}")
                                                     ,("param"
                                                      ,String "fileo")
                                                      ,("expected",String "PtFile")])}))

  -- -----------------------------------

  describe "async dispatcher operation" $ do

    it "receives replies out of order" $ do
      chan <- atomically newTChan
      chSync <- atomically newTChan
      let req1 = IdeRequest "cmdasync1" Map.empty
          req2 = IdeRequest "cmdasync2" Map.empty
          cr1 = CReq "test" 1 req1 chan
          cr2 = CReq "test" 2 req2 chan
      r1 <- withStdoutLogging $ runIdeM (IdeState Map.empty Map.empty) (doDispatch (testPlugins chSync) cr1)
      r2 <- withStdoutLogging $ runIdeM (IdeState Map.empty Map.empty) (doDispatch (testPlugins chSync) cr2)
      r1 `shouldBe` Nothing
      r2 `shouldBe` Nothing
      rc1 <- atomically $ readTChan chan
      rc2 <- atomically $ readTChan chan
      rc1 `shouldBe` (CResp { couPlugin = "test"
                            , coutReqId = 2
                            , coutResp = IdeResponseOk (HM.fromList [("ok",String "asyncCmd2 sending strobe")])})
      rc2 `shouldBe` (CResp { couPlugin = "test"
                            , coutReqId = 1
                            , coutResp = IdeResponseOk (HM.fromList [("ok",String "asyncCmd1 got strobe")])})

-- ---------------------------------------------------------------------

testPlugins :: TChan () -> Plugins
testPlugins chSync = Map.fromList [("test",testDescriptor chSync)]

testDescriptor :: TChan () -> UntaggedPluginDescriptor
testDescriptor chSync = PluginDescriptor
  {
    pdUIShortName = "testDescriptor"
  , pdUIOverview = "PluginDescriptor for testing Dispatcher"
  , pdCommands =
      [
        mkCmdWithContext "cmd1" [CtxNone] []
      , mkCmdWithContext "cmd2" [CtxFile] []
      , mkCmdWithContext "cmd3" [CtxPoint] []
      , mkCmdWithContext "cmd4" [CtxRegion] []
      , mkCmdWithContext "cmd5" [CtxCabalTarget] []
      , mkCmdWithContext "cmd6" [CtxProject] []
      , mkCmdWithContext "cmdmultiple" [CtxFile,CtxPoint,CtxRegion] []

      , mkCmdWithContext "cmdextra" [CtxFile] [ RP "txt"  "help" PtText
                                              , RP "file" "help" PtFile
                                              , RP "pos"  "help" PtPos
                                              ]

      , mkCmdWithContext "cmdoptional" [CtxNone] [ RP "txt"   "help" PtText
                                                 , OP "txto"  "help" PtText
                                                 , OP "fileo" "help" PtFile
                                                 , OP "poso"  "help" PtPos
                                                 ]
      , mkAsyncCmdWithContext (asyncCmd1 chSync) "cmdasync1" [CtxNone] []
      , mkAsyncCmdWithContext (asyncCmd2 chSync) "cmdasync2" [CtxNone] []
      ]
  , pdExposedServices = []
  , pdUsedServices    = []
  }

mkCmdWithContext :: CommandName -> [AcceptedContext] -> [ParamDescription] -> UntaggedCommand
mkCmdWithContext n cts pds =
        Command
          { cmdDesc = CommandDesc
                        { cmdName = n
                        , cmdUiDescription = "description"
                        , cmdFileExtensions = []
                        , cmdContexts = cts
                        , cmdAdditionalParams = pds
                        , cmdReturnType = "Text"
                        }
          , cmdFunc = CmdSync $ \ctxs _ -> return (IdeResponseOk (T.pack $ "result:ctxs=" ++ show ctxs))
          }

mkAsyncCmdWithContext :: (ValidResponse a) => CommandFunc a -> CommandName -> [AcceptedContext] -> [ParamDescription] -> UntaggedCommand
mkAsyncCmdWithContext cf n cts pds =
  Command {cmdDesc =
             CommandDesc {cmdName = n
                         ,cmdUiDescription = "description"
                         ,cmdFileExtensions = []
                         ,cmdContexts = cts
                         ,cmdAdditionalParams = pds
                         ,cmdReturnType = "Text"}
          ,cmdFunc = cf}

-- ---------------------------------------------------------------------

asyncCmd1 :: TChan () -> CommandFunc T.Text
asyncCmd1 ch = CmdAsync $ \f _ctxs _ -> do
  _ <- liftIO $ forkIO $ do
    _synced <- atomically $ readTChan ch
    logm $ "asyncCmd1 got val"
    f (IdeResponseOk "asyncCmd1 got strobe")
  return ()

asyncCmd2 :: TChan () -> CommandFunc T.Text
asyncCmd2 ch  = CmdAsync $ \f _ctxs _ -> do
  _ <- liftIO $ forkIO $ do
    f (IdeResponseOk "asyncCmd2 sending strobe")
    atomically $ writeTChan ch ()
  return ()

-- ---------------------------------------------------------------------
