{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
module Haskell.Ide.Engine.Config where

import           Data.Aeson
import           Data.Default
import           Data.Functor ((<&>))
import           Control.Monad (join)
import qualified Data.Text as T
import qualified Control.Exception as E (handle, IOException)
import qualified System.Directory as SD (getCurrentDirectory, getHomeDirectory, doesFileExist)
import           Language.Haskell.LSP.Types

-- ---------------------------------------------------------------------

-- | Callback from haskell-lsp core to convert the generic message to the
-- specific one for hie
getConfigFromNotification :: DidChangeConfigurationNotification -> Either T.Text Config
getConfigFromNotification (NotificationMessage _ _ (DidChangeConfigurationParams p)) =
  case fromJSON p of
    Success c -> Right c
    Error err -> Left $ T.pack err

-- |
-- Workaround to ‘getConfigFromNotification’ not working (Atom Editor).
getConfigFromFileSystem :: Maybe FilePath -> IO Config
getConfigFromFileSystem root = E.handle onIOException go
  where
    onIOException :: E.IOException -> IO Config
    onIOException _ = return def
    
    parse :: FilePath -> IO Config
    parse filePath = decodeFileStrict filePath <&> \case
      Just x -> x
      Nothing -> def
    
    go :: IO Config
    go = do
      suggested <- join <$> mapM checkForConfigFile root
      local <- checkForConfigFile =<< SD.getCurrentDirectory
      home <- checkForConfigFile =<< SD.getHomeDirectory
      case (suggested, local, home) of
        (Just filePath, _, _) -> parse filePath
        (_, Just filePath, _) -> parse filePath
        (_, _, Just filePath) -> parse filePath
        _ -> return def
    
    checkForConfigFile :: FilePath -> IO (Maybe FilePath)
    checkForConfigFile dir = SD.doesFileExist settingsFilePath <&> \case
      True -> Just settingsFilePath
      _ -> Nothing
      where
        settingsFilePath :: FilePath
        settingsFilePath = dir <> "/settings.json"

-- ---------------------------------------------------------------------

data Config =
  Config
    { hlintOn                     :: Bool
    , maxNumberOfProblems         :: Int
    , diagnosticsDebounceDuration :: Int
    , liquidOn                    :: Bool
    , completionSnippetsOn        :: Bool
    , formatOnImportOn            :: Bool
    , onSaveOnly                  :: Bool
    -- ^ Disables interactive “as you type“ linter/diagnostic feedback.
    , noAutocompleteArguments     :: Bool
    -- ^ Excludes argument types from autocomplete insertions (see "Configuration" from README.md for details).
    } deriving (Show,Eq)

instance Default Config where
  def = Config
    { hlintOn                     = True
    , maxNumberOfProblems         = 100
    , diagnosticsDebounceDuration = 350000
    , liquidOn                    = False
    , completionSnippetsOn        = True
    , formatOnImportOn            = True
    , onSaveOnly                  = False
    , noAutocompleteArguments     = False
    }

-- TODO: Add API for plugins to expose their own LSP config options
instance FromJSON Config where
  parseJSON = withObject "Config" $ \v -> do
    s <- v .: "languageServerHaskell"
    flip (withObject "Config.settings") s $ \o -> Config
      <$> o .:? "hlintOn"                     .!= hlintOn def
      <*> o .:? "maxNumberOfProblems"         .!= maxNumberOfProblems def
      <*> o .:? "diagnosticsDebounceDuration" .!= diagnosticsDebounceDuration def
      <*> o .:? "liquidOn"                    .!= liquidOn def
      <*> o .:? "completionSnippetsOn"        .!= completionSnippetsOn def
      <*> o .:? "formatOnImportOn"            .!= formatOnImportOn def 
      <*> o .:? "onSaveOnly"                  .!= onSaveOnly def
      <*> o .:? "noAutocompleteArguments"     .!= noAutocompleteArguments def 


-- 2017-10-09 23:22:00.710515298 [ThreadId 11] - ---> {"jsonrpc":"2.0","method":"workspace/didChangeConfiguration","params":{"settings":{"languageServerHaskell":{"maxNumberOfProblems":100,"hlintOn":true}}}}
-- 2017-10-09 23:22:00.710667381 [ThreadId 15] - reactor:got didChangeConfiguration notification:
-- NotificationMessage
--   {_jsonrpc = "2.0"
--   , _method = WorkspaceDidChangeConfiguration
--   , _params = DidChangeConfigurationParams
--                 {_settings = Object (fromList [("languageServerHaskell",Object (fromList [("hlintOn",Bool True)
--                                                                                          ,("maxNumberOfProblems",Number 100.0)]))])}}

instance ToJSON Config where
  toJSON (Config h m d l c f saveOnly noAutoArg) = object [ "languageServerHaskell" .= r ]
    where
      r = object [ "hlintOn"                     .= h
                 , "maxNumberOfProblems"         .= m
                 , "diagnosticsDebounceDuration" .= d
                 , "liquidOn"                    .= l
                 , "completionSnippetsOn"        .= c
                 , "formatOnImportOn"            .= f
                 , "onSaveOnly"                  .= saveOnly
                 , "noAutocompleteArguments"     .= noAutoArg
                 ]


