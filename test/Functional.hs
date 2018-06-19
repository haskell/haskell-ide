{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
module Main where

import Control.Monad.IO.Class
import Control.Lens hiding (List)
import Control.Monad
import Data.Aeson
import qualified Data.HashMap.Strict as H
import Data.Maybe
import qualified Data.Text as T
import Language.Haskell.LSP.Test
import Language.Haskell.LSP.Types
import qualified Language.Haskell.LSP.Types as LSP (error, id)
import Test.Hspec
import System.Directory
import System.FilePath
import FunctionalDispatch
import TestUtils

main :: IO ()
main = do
  setupStackFiles
  withFileLogging "functional.log" $ do
    hspec spec
    cdAndDo "./test/testdata" $ hspec dispatchSpec

spec :: Spec
spec = do
  describe "deferred responses" $ do
    it "do not affect hover requests" $ runSession hieCommand "test/testdata" $ do
      doc <- openDoc "FuncTest.hs" "haskell"

      id1 <- sendRequest TextDocumentHover (TextDocumentPositionParams doc (Position 4 2))

      skipMany anyNotification
      hoverRsp <- response :: Session HoverResponse
      let (Just (List contents1)) = hoverRsp ^? result . _Just . contents
      liftIO $ contents1 `shouldBe` []
      liftIO $ hoverRsp ^. LSP.id `shouldBe` responseId id1

      id2 <- sendRequest TextDocumentDocumentSymbol (DocumentSymbolParams doc)
      symbolsRsp <- skipManyTill anyNotification response :: Session DocumentSymbolsResponse
      liftIO $ symbolsRsp ^. LSP.id `shouldBe` responseId id2

      id3 <- sendRequest TextDocumentHover (TextDocumentPositionParams doc (Position 4 2))
      hoverRsp2 <- skipManyTill anyNotification response :: Session HoverResponse
      liftIO $ hoverRsp2 ^. LSP.id `shouldBe` responseId id3

      let (Just (List contents2)) = hoverRsp2 ^? result . _Just . contents
      liftIO $ contents2 `shouldNotSatisfy` null

      -- Now that we have cache the following request should be instant
      let highlightParams = TextDocumentPositionParams doc (Position 7 0)
      _ <- sendRequest TextDocumentDocumentHighlight highlightParams

      highlightRsp <- response :: Session DocumentHighlightsResponse
      let (Just (List locations)) = highlightRsp ^. result
      liftIO $ locations `shouldBe` [ DocumentHighlight
                     { _range = Range
                       { _start = Position {_line = 7, _character = 0}
                       , _end   = Position {_line = 7, _character = 2}
                       }
                     , _kind  = Just HkWrite
                     }
                   , DocumentHighlight
                     { _range = Range
                       { _start = Position {_line = 7, _character = 0}
                       , _end   = Position {_line = 7, _character = 2}
                       }
                     , _kind  = Just HkWrite
                     }
                   , DocumentHighlight
                     { _range = Range
                       { _start = Position {_line = 5, _character = 6}
                       , _end   = Position {_line = 5, _character = 8}
                       }
                     , _kind  = Just HkRead
                     }
                   , DocumentHighlight
                     { _range = Range
                       { _start = Position {_line = 7, _character = 0}
                       , _end   = Position {_line = 7, _character = 2}
                       }
                     , _kind  = Just HkWrite
                     }
                   , DocumentHighlight
                     { _range = Range
                       { _start = Position {_line = 7, _character = 0}
                       , _end   = Position {_line = 7, _character = 2}
                       }
                     , _kind  = Just HkWrite
                     }
                   , DocumentHighlight
                     { _range = Range
                       { _start = Position {_line = 5, _character = 6}
                       , _end   = Position {_line = 5, _character = 8}
                       }
                     , _kind  = Just HkRead
                     }
                   ]

    it "instantly respond to failed modules with no cache" $ runSession hieCommand "test/testdata" $ do
      doc <- openDoc "FuncTestFail.hs" "haskell"

      _ <- sendRequest TextDocumentDocumentSymbol (DocumentSymbolParams doc)
      skipMany anyNotification
      symbols <- response :: Session DocumentSymbolsResponse
      liftIO $ symbols ^. LSP.error `shouldNotBe` Nothing

    it "returns hints as diagnostics" $ runSession hieCommand "test/testdata" $ do
      _ <- openDoc "FuncTest.hs" "haskell"

      cwd <- liftIO getCurrentDirectory
      let testUri = filePathToUri $ cwd </> "test/testdata/FuncTest.hs"

      diags <- skipManyTill loggingNotification publishDiagnosticsNotification
      liftIO $ diags ^? params `shouldBe` (Just $ PublishDiagnosticsParams
                { _uri         = testUri
                , _diagnostics = List
                  [ Diagnostic
                      (Range (Position 9 6) (Position 10 18))
                      (Just DsInfo)
                      (Just "Redundant do")
                      (Just "hlint")
                      "Redundant do\nFound:\n  do putStrLn \"hello\"\nWhy not:\n  putStrLn \"hello\"\n"
                      Nothing
                  ]
                }
              )

      let args' = H.fromList [("pos", toJSON (Position 7 0)), ("file", toJSON testUri)]
          args = List [Object args']
      _ <- sendRequest WorkspaceExecuteCommand (ExecuteCommandParams "hare:demote" (Just args))

      executeRsp <- skipManyTill anyNotification response :: Session ExecuteCommandResponse
      liftIO $ executeRsp ^. result `shouldBe` Just (Object H.empty)

      editReq <- request :: Session ApplyWorkspaceEditRequest
      liftIO $ editReq ^. params . edit `shouldBe` WorkspaceEdit
            ( Just
            $ H.singleton testUri
            $ List
                [ TextEdit (Range (Position 6 0) (Position 7 6))
                            "  where\n    bb = 5"
                ]
            )
            Nothing

  describe "multi-server setup" $
    it "doesn't have clashing commands on two servers" $ do
      let getCommands = runSession hieCommand "test/testdata" $ do
              rsp <- getInitializeResponse
              let uuids = rsp ^? result . _Just . capabilities . executeCommandProvider . _Just . commands
              return $ fromJust uuids
      List uuids1 <- getCommands
      List uuids2 <- getCommands
      liftIO $ forM_ (zip uuids1 uuids2) (uncurry shouldNotBe)

  describe "code actions" $
    it "provide hlint suggestions" $ runSession hieCommand "test/testdata" $ do
      doc <- openDoc "ApplyRefact2.hs" "haskell"
      diagsRsp <- skipManyTill anyNotification notification :: Session PublishDiagnosticsNotification
      let (List diags) = diagsRsp ^. params . diagnostics
          reduceDiag = head diags

      liftIO $ do
        length diags `shouldBe` 2
        reduceDiag ^. range `shouldBe` Range (Position 1 0) (Position 1 12)
        reduceDiag ^. severity `shouldBe` Just DsInfo
        reduceDiag ^. code `shouldBe` Just "Eta reduce"
        reduceDiag ^. source `shouldBe` Just "hlint"

      let r = Range (Position 0 0) (Position 99 99)
          c = CodeActionContext (diagsRsp ^. params . diagnostics)
      _ <- sendRequest TextDocumentCodeAction (CodeActionParams doc r c)

      rsp <- response :: Session CodeActionResponse
      let (List cmds) = fromJust $ rsp ^. result
          evaluateCmd = head cmds
      liftIO $ do
        length cmds `shouldBe` 1
        evaluateCmd ^. title `shouldBe` "Apply hint:Evaluate"

  describe "config" $
    it "falls back to default when not specified" $ runSession hieCommand "test/testdata" $ do
      let ps = DidChangeConfigurationParams (object [])
      sendNotification WorkspaceDidChangeConfiguration ps
      nots <- count 2 notification :: Session [LogMessageNotification]
      liftIO $ map (^. params . message) nots `shouldSatisfy` all (null . T.breakOnAll "error")
