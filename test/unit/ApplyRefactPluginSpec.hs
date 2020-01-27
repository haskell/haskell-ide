{-# LANGUAGE CPP #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings     #-}
module ApplyRefactPluginSpec where

import qualified Data.HashMap.Strict                   as H
import qualified Data.Text                             as T
import           Haskell.Ide.Engine.Plugin.ApplyRefact
import           Haskell.Ide.Engine.MonadTypes
import           Haskell.Ide.Engine.PluginUtils
import           Language.Haskell.LSP.Types
import           System.Directory
import           TestUtils

import           Test.Hspec

{-# ANN module ("HLint: ignore Redundant do"       :: String) #-}

-- ---------------------------------------------------------------------

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  describe "apply-refact plugin" applyRefactSpec

-- ---------------------------------------------------------------------

testPlugins :: IdePlugins
testPlugins = pluginDescToIdePlugins [applyRefactDescriptor "applyrefact"]

-- ---------------------------------------------------------------------

applyRefactSpec :: Spec
applyRefactSpec = do
  describe "apply-refact plugin commands" $ do
    applyRefactFp  <- runIO $ makeAbsolute "./test/testdata/ApplyRefact.hs"
    let applyRefactPath = filePathToUri applyRefactFp
    -- ---------------------------------

    it "applies one hint only" $ do

      let furi = applyRefactPath
          act = applyOneCmd arg
          arg = AOP furi (toPos (2,8)) "Redundant bracket"
          textEdits = List [TextEdit (Range (Position 1 0) (Position 1 25)) "main = putStrLn \"hello\""]
          res = Right $ WorkspaceEdit
            (Just $ H.singleton applyRefactPath textEdits)
            Nothing
      testCommand testPlugins applyRefactFp act "applyrefact" "applyOne" arg res

    -- ---------------------------------

    it "applies all hints" $ do

      let act = applyAllCmd arg
          arg = applyRefactPath
          textEdits = List [ TextEdit (Range (Position 1 0) (Position 1 25)) "main = putStrLn \"hello\""
                           , TextEdit (Range (Position 3 0) (Position 3 15)) "foo x = x + 1" ]
          res = Right $ WorkspaceEdit
            (Just $ H.singleton applyRefactPath textEdits)
            Nothing
      testCommand testPlugins applyRefactFp act "applyrefact" "applyAll" arg res

    -- ---------------------------------

    it "returns hints as diagnostics" $ do

      let act = lint applyRefactPath
          res = Right
            PublishDiagnosticsParams
             { _uri = applyRefactPath
             , _diagnostics = List $
               [ Diagnostic (Range (Position 1 7) (Position 1 25))
                            (Just DsHint)
                            (Just (StringValue "Redundant bracket"))
                            (Just "hlint")
                            "Redundant bracket\nFound:\n  (putStrLn \"hello\")\nWhy not:\n  putStrLn \"hello\"\n"
                            Nothing
               , Diagnostic (Range (Position 3 8) (Position 3 15))
                            (Just DsHint)
                            (Just (StringValue "Redundant bracket"))
                            (Just "hlint")
                            "Redundant bracket\nFound:\n  (x + 1)\nWhy not:\n  x + 1\n"
                            Nothing
               ]}
      runIGM testPlugins applyRefactFp act `shouldReturn` res

    -- ---------------------------------

    it "returns hlint parse error as DsInfo ignored diagnostic" $ do
      filePathNoUri  <- makeAbsolute "./test/testdata/HlintParseFail.hs"
      let filePath = filePathToUri filePathNoUri

      let act = lint filePath
          res = Right
            PublishDiagnosticsParams
             { _uri = filePath
             , _diagnostics = List
               [Diagnostic {_range = Range { _start = Position {_line = 12, _character = 23}
                                           , _end = Position {_line = 12, _character = 100000}}
                           , _severity = Just DsInfo
                           , _code = Just (StringValue "parser")
                           , _source = Just "hlint"
                           , _message = T.pack filePathNoUri <> ":13:24: error:\n    Operator applied to too few arguments: +\n  data instance Sing (z :: (a :~: b)) where\n>     SRefl :: Sing Refl +\n\n"
                           , _relatedInformation = Nothing }]}
      runIGM testPlugins applyRefactFp act `shouldReturn` res

    -- ---------------------------------

    it "respects hlint pragmas in the source file" $ do
      fp  <- makeAbsolute "./test/testdata/HlintPragma.hs"
      let filePath = filePathToUri fp
      let req = lint filePath
      r <- runIGM testPlugins fp req
      r `shouldBe` Right
        PublishDiagnosticsParams
          { _uri = filePath
          , _diagnostics = List
            [ Diagnostic (Range (Position 3 11) (Position 3 20))
                          (Just DsInfo)
                          (Just (StringValue "Redundant bracket"))
                          (Just "hlint")
                          "Redundant bracket\nFound:\n  (\"hello\")\nWhy not:\n  \"hello\"\n"
                          Nothing
            ]
          }
           

    -- ---------------------------------

    it "respects hlint config files in project root dir" $ do
      fp  <- makeAbsolute "./test/testdata/HlintPragma.hs"
      let filePath = filePathToUri fp

      let req = lint filePath
      r <- withCurrentDirectory "./test/testdata" $ runIGM testPlugins fp req
      r `shouldBe` Right
        PublishDiagnosticsParams
        -- { _uri = filePathToUri "./HlintPragma.hs"
        { _uri = filePath
        , _diagnostics = List []
        }

    -- ---------------------------------

    it "reports error without crash" $ do
      fp <- makeAbsolute "./test/testdata/ApplyRefactError.hs"
      let filePath = filePathToUri fp
      let req = applyAllCmd filePath
          isExpectedError (Left (IdeError PluginError err _)) =
              "Illegal symbol " `T.isInfixOf` err
          isExpectedError _ = False
      r <- withCurrentDirectory "./test/testdata" $ runIGM testPlugins fp req
      r `shouldSatisfy` isExpectedError
