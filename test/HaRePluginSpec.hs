{-# LANGUAGE OverloadedStrings #-}
module HaRePluginSpec where

import           Control.Concurrent.STM.TChan
import           Control.Monad.STM
import           Control.Logging
import           Data.Aeson
import qualified Data.HashMap.Strict as H
import qualified Data.Map as Map
import           Haskell.Ide.Engine.Dispatcher
import           Haskell.Ide.Engine.Monad
import           Haskell.Ide.Engine.PluginDescriptor
import           Haskell.Ide.Engine.Types
import           Haskell.Ide.HaRePlugin
import           Test.Hspec

-- ---------------------------------------------------------------------

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  describe "hare plugin" hareSpec

-- -- |Used when running from ghci, and it sets the current directory to ./tests
-- tt :: IO ()
-- tt = do
--   cd ".."
--   hspec spec

-- ---------------------------------------------------------------------

testPlugins :: Plugins
testPlugins = Map.fromList [("hare",hareDescriptor "hare")]

-- TODO: break this out into a TestUtils file
dispatchRequest :: IdeRequest -> IO (Maybe (IdeResponse Object))
dispatchRequest req = do
  testChan <- atomically newTChan
  let cr = CReq "hare" 1 req testChan
  r <- withStdoutLogging $ runIdeM (IdeState Map.empty) (doDispatch testPlugins cr)
  return r

-- ---------------------------------------------------------------------

hareSpec :: Spec
hareSpec = do
  describe "hare plugin commands" $ do

    -- ---------------------------------

    it "renames" $ do

      let req = IdeRequest "rename" (Map.fromList [("file",ParamValP $ ParamFile "./test/testdata/HaReRename.hs")
                                                  ,("start_pos",ParamValP $ ParamPos (5,1))
                                                  ,("name",ParamValP $ ParamText "foolong")])
      r <- dispatchRequest req
      r `shouldBe` Just (IdeResponseOk (H.fromList ["ok" .= ["test/testdata/HaReRename.hs"::FilePath]]))

    -- ---------------------------------

    it "returns an error for invalid rename" $ do
      let req = IdeRequest "rename" (Map.fromList [("file",ParamValP $ ParamFile "./test/testdata/HaReRename.hs")
                                                  ,("start_pos",ParamValP $ ParamPos (15,1))
                                                  ,("name",ParamValP $ ParamText "foolong")])
      r <- dispatchRequest req
      r `shouldBe` Just (IdeResponseFail
                      (IdeError { ideCode = PluginError
                                , ideMessage = "rename: \"Invalid cursor position!\"", ideInfo = Nothing}))

    -- ---------------------------------

    it "demotes" $ do
      let req = IdeRequest "demote" (Map.fromList [("file",ParamValP $ ParamFile "./test/testdata/HaReDemote.hs")
                                                  ,("start_pos",ParamValP $ ParamPos (6,1))])
      r <- dispatchRequest req
      r `shouldBe` Just (IdeResponseOk (H.fromList ["ok" .= ["test/testdata/HaReDemote.hs"::FilePath]]))


    -- ---------------------------------

    it "duplicates a definition" $ do

      let req = IdeRequest "dupdef" (Map.fromList [("file",ParamValP $ ParamFile "./test/testdata/HaReRename.hs")
                                                  ,("start_pos",ParamValP $ ParamPos (5,1))
                                                  ,("name",ParamValP $ ParamText "foonew")])
      r <- dispatchRequest req
      r `shouldBe` Just (IdeResponseOk (H.fromList ["ok" .= ["test/testdata/HaReRename.hs"::FilePath]]))


    -- ---------------------------------

    it "converts if to case" $ do

      let req = IdeRequest "iftocase" (Map.fromList [("file",ParamValP $ ParamFile "./test/testdata/HaReCase.hs")
                                                    ,("start_pos",ParamValP $ ParamPos (5,9))
                                                    ,("end_pos",  ParamValP $ ParamPos (9,12))])
      r <- dispatchRequest req
      r `shouldBe` Just (IdeResponseOk (H.fromList ["ok" .= ["test/testdata/HaReCase.hs"::FilePath]]))

    -- ---------------------------------

    it "lifts one level" $ do

      let req = IdeRequest "liftonelevel" (Map.fromList [("file",ParamValP $ ParamFile "./test/testdata/HaReMoveDef.hs")
                                                    ,("start_pos",ParamValP $ ParamPos (6,5))])
      r <- dispatchRequest req
      r `shouldBe` Just (IdeResponseOk (H.fromList ["ok" .= ["test/testdata/HaReMoveDef.hs"::FilePath]]))

    -- ---------------------------------

    it "lifts to top level" $ do

      let req = IdeRequest "lifttotoplevel" (Map.fromList [("file",ParamValP $ ParamFile "./test/testdata/HaReMoveDef.hs")
                                                          ,("start_pos",ParamValP $ ParamPos (12,9))])
      r <- dispatchRequest req
      r `shouldBe` Just (IdeResponseOk (H.fromList ["ok" .= ["test/testdata/HaReMoveDef.hs"::FilePath]]))

    -- ---------------------------------
