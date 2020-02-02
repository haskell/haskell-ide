{-# LANGUAGE CPP #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}
-- | Information and display strings for HIE's version
-- and the current project's version
module Haskell.Ide.Engine.Version where

import           Data.Maybe
import           Development.GitRev              (gitCommitCount)
import           Distribution.System             (buildArch)
import           Distribution.Text               (display)
import           Options.Applicative.Simple      (simpleVersion)
import           Haskell.Ide.Engine.Cradle       (execProjectGhc)
import qualified HIE.Bios.Types                  as Bios
import qualified Haskell.Ide.Engine.Cradle       as Bios
import qualified Paths_haskell_ide_engine        as Meta
import           System.Directory
import           System.Info

hieVersion :: String
hieVersion =
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

getProjectGhcVersion :: Bios.Cradle Bios.CabalHelper -> IO String
getProjectGhcVersion crdl =
  fmap
    (fromMaybe "No System GHC Found.")
    (execProjectGhc crdl ["--numeric-version"])


hieGhcVersion :: String
hieGhcVersion = VERSION_ghc

-- ---------------------------------------------------------------------

checkCabalInstall :: IO Bool
checkCabalInstall = isJust <$> findExecutable "cabal"

-- ---------------------------------------------------------------------
