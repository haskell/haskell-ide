{-# LANGUAGE CPP               #-}
{-# LANGUAGE OverloadedStrings #-}
module GhcModPluginSpec where

import           Control.Exception
import qualified Data.Map                            as Map
#if __GLASGOW_HASKELL__ < 804
import           Data.Monoid
#endif
import qualified Data.Set                            as S
import qualified Data.Text                           as T
import           Haskell.Ide.Engine.MonadTypes
import           Haskell.Ide.Engine.PluginDescriptor
import           Haskell.Ide.Engine.PluginUtils
import           Haskell.Ide.Engine.Plugin.GhcMod
import           System.Directory
import           TestUtils

import           Test.Hspec

-- ---------------------------------------------------------------------

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  describe "ghc-mod plugin" ghcmodSpec

-- ---------------------------------------------------------------------

testPlugins :: IdePlugins
testPlugins = pluginDescToIdePlugins [("ghcmod",ghcmodDescriptor)]

-- ---------------------------------------------------------------------

ghcmodSpec :: Spec
ghcmodSpec = do
  describe "ghc-mod plugin commands" $ do

    it "runs the check command" $ cdAndDo "./test/testdata" $ do
      fp <- makeAbsolute "./FileWithWarning.hs"
      let act = setTypecheckedModule arg
          arg = filePathToUri fp
          res = IdeResponseOk $
            (Map.singleton arg (S.singleton diag), [])
          diag = Diagnostic (Range (toPos (4,7))
                                   (toPos (4,8)))
                            (Just DsError)
                            Nothing
                            (Just "ghcmod")
                            "Variable not in scope: x"
                            Nothing

      testCommand testPlugins act "ghcmod" "check" arg res

    -- ---------------------------------

    it "runs the lint command" $ cdAndDo "./test/testdata" $ do
      fp <- makeAbsolute "FileWithWarning.hs"
      let uri = filePathToUri fp
          act = lintCmd' uri
          arg = uri
          res = IdeResponseOk (T.pack fp <> ":6:9: Warning: Redundant do\NULFound:\NUL  do return (3 + x)\NULWhy not:\NUL  return (3 + x)\n")
      testCommand testPlugins act "ghcmod" "lint" arg res

    -- ---------------------------------

    it "runs the info command" $ cdAndDo "./test/testdata" $ do
      fp <- makeAbsolute "HaReRename.hs"
      let uri = filePathToUri fp
          act = infoCmd' uri "main"
          arg = IP uri "main"
          res = IdeResponseOk "main :: IO () \t-- Defined at HaReRename.hs:2:1\n"
      -- ghc-mod tries to load the test file in the context of the hie project if we do not cd first.
      testCommand testPlugins act "ghcmod" "info" arg res

    -- ---------------------------------

    it "runs the type command" $ cdAndDo "./test/testdata" $ do
      fp <- makeAbsolute "HaReRename.hs"
      let uri = filePathToUri fp
          act = do
            _ <- setTypecheckedModule uri
            liftIdeGhcM $ newTypeCmd (toPos (5,9)) uri
          arg = TP False uri (toPos (5,9))
          res = IdeResponseOk
            [(Range (toPos (5,9)) (toPos (5,10)), "Int")
            ,(Range (toPos (5,9)) (toPos (5,14)), "Int")
            ,(Range (toPos (5,1)) (toPos (5,14)), "Int -> Int")
            ]
      testCommand testPlugins act "ghcmod" "type" arg res

    it "runs the type command with an absolute path from another folder, correct params" $ do
      fp <- makeAbsolute "./test/testdata/HaReRename.hs"
      cd <- getCurrentDirectory
      cd2 <- getHomeDirectory
      bracket (setCurrentDirectory cd2)
              (\_->setCurrentDirectory cd)
              $ \_-> do
        let uri = filePathToUri fp
        let act = do
              _ <- setTypecheckedModule uri
              liftIdeGhcM $ newTypeCmd (toPos (5,9)) uri
        let arg = TP False uri (toPos (5,9))
        let res = IdeResponseOk
              [(Range (toPos (5,9)) (toPos (5,10)), "Int")
              ,(Range (toPos (5,9)) (toPos (5,14)), "Int")
              ,(Range (toPos (5,1)) (toPos (5,14)), "Int -> Int")
              ]
        testCommand testPlugins act "ghcmod" "type" arg res

    -- ---------------------------------
