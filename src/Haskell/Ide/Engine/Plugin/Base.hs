{-# LANGUAGE CPP                   #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE TemplateHaskell       #-}
module Haskell.Ide.Engine.Plugin.Base where

import           Data.Aeson
import           Data.Foldable
import qualified Data.Map                        as Map
#if __GLASGOW_HASKELL__ < 804
import           Data.Semigroup
#endif
import qualified Data.Text                       as T
import           Development.GitRev              (gitCommitCount)
import           Distribution.System             (buildArch)
import           Distribution.Text               (display)
import           Haskell.Ide.Engine.IdeFunctions
import           Haskell.Ide.Engine.MonadTypes
import           Options.Applicative.Simple      (simpleVersion)
import qualified Paths_haskell_ide_engine        as Meta

import           Stack.Options.GlobalParser
import           Stack.Runners
import           Stack.Types.Compiler
import           Stack.Types.Version

import           System.Directory
import           System.Info
import           System.Process
import qualified System.Log.Logger as L

-- ---------------------------------------------------------------------

baseDescriptor :: PluginDescriptor
baseDescriptor = PluginDescriptor
  {
    pluginName = "HIE Base"
  , pluginDesc = "Commands for HIE itself"
  , pluginCommands =
      [ PluginCommand "version" "return HIE version" versionCmd
      , PluginCommand "plugins" "list available plugins" pluginsCmd
      , PluginCommand "commands" "list available commands for a given plugin" commandsCmd
      , PluginCommand "commandDetail" "list parameters required for a given command" commandDetailCmd
      ]
  }

-- ---------------------------------------------------------------------

versionCmd :: CommandFunc () T.Text
versionCmd = CmdSync $ \_ -> return $ IdeResultOk (T.pack version)

pluginsCmd :: CommandFunc () IdePlugins
pluginsCmd = CmdSync $ \_ ->
  IdeResultOk <$> getPlugins

commandsCmd :: CommandFunc T.Text [CommandName]
commandsCmd = CmdSync $ \p -> do
  IdePlugins plugins <- getPlugins
  case Map.lookup p plugins of
    Nothing -> return $ IdeResultFail $ IdeError
      { ideCode = UnknownPlugin
      , ideMessage = "Can't find plugin:" <> p
      , ideInfo = toJSON p
      }
    Just pl -> return $ IdeResultOk $ map commandName pl

commandDetailCmd :: CommandFunc (T.Text, T.Text) T.Text
commandDetailCmd = CmdSync $ \(p,command) -> do
  IdePlugins plugins <- getPlugins
  case Map.lookup p plugins of
    Nothing -> return $ IdeResultFail $ IdeError
      { ideCode = UnknownPlugin
      , ideMessage = "Can't find plugin:" <> p
      , ideInfo = toJSON p
      }
    Just pl -> case find (\cmd -> command == (commandName cmd) ) pl of
      Nothing -> return $ IdeResultFail $ IdeError
        { ideCode = UnknownCommand
        , ideMessage = "Can't find command:" <> command
        , ideInfo = toJSON command
        }
      Just detail -> return $ IdeResultOk (commandDesc detail)

-- ---------------------------------------------------------------------

version :: String
version =
  let commitCount = $gitCommitCount
  in concat $ concat
    [ [$(simpleVersion Meta.version)]
      -- Leave out number of commits for --depth=1 clone
      -- See https://github.com/commercialhaskell/stack/issues/792
    , [" (" ++ commitCount ++ " commits)" | commitCount /= ("1"::String) &&
                                            commitCount /= ("UNKNOWN" :: String)]
    , [" ", display buildArch]
    , [" ", hieGhcDisplayVersion]
    ]

-- ---------------------------------------------------------------------

hieGhcDisplayVersion :: String
hieGhcDisplayVersion = compilerName ++ "-" ++ VERSION_ghc

getProjectGhcVersion :: IO String
getProjectGhcVersion = do
  isStack <- doesFileExist "stack.yaml"
  if isStack
    then do
      L.infoM "hie" "Using stack GHC version"
      getStackGhcVersion
    else do
      L.infoM "hie" "Using plain GHC version"
      crackGhcVersion <$> readCreateProcess (shell "ghc --version") ""
          
  where
    -- "The Glorious Glasgow Haskell Compilation System, version 8.4.3\n"
    -- "The Glorious Glasgow Haskell Compilation System, version 8.4.2\n"
    crackGhcVersion :: String -> String
    crackGhcVersion st = reverse $ takeWhile (/=' ') $ tail $ reverse st

hieGhcVersion :: String
hieGhcVersion = VERSION_ghc

getStackGhcVersion :: IO String
getStackGhcVersion = do
  compilerVer <- loadConfigWithOpts globalOpts (loadCompilerVersion globalOpts)
  let ghcVer = case compilerVer of
                  GhcVersion v -> v
                  GhcjsVersion _ v -> v
  return $ versionString ghcVer
  where globalOpts = globalOptsFromMonoid False mempty
-- ---------------------------------------------------------------------
