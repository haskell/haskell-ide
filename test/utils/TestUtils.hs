{-# LANGUAGE CPP #-}
module TestUtils
  (
    testOptions
  , cdAndDo
  , withFileLogging
  , setupStackFiles
  , testCommand
  , runSingleReq
  , makeRequest
  , runIGM
  , hieCommand
  , hieCommandVomit
  ) where

import           Control.Exception
import           Control.Monad
import           Data.Aeson.Types (typeMismatch)
import           Data.Default
import           Data.Text (pack)
import           Data.Typeable
import           Data.Yaml
import qualified Data.Map as Map
import qualified GhcMod.Monad as GM
import qualified GhcMod.Types as GM
import qualified Language.Haskell.LSP.Core as Core
import           Haskell.Ide.Engine.Monad
import           Haskell.Ide.Engine.MonadTypes
import           Haskell.Ide.Engine.PluginDescriptor
import           System.Directory
import           System.FilePath
import qualified System.Log.Logger as L

import           Test.Hspec

-- ---------------------------------------------------------------------

testOptions :: GM.Options
testOptions = GM.defaultOptions {
    GM.optOutput     = GM.OutputOpts {
      GM.ooptLogLevel       = GM.GmError
      -- GM.ooptLogLevel       = GM.GmVomit
    , GM.ooptStyle          = GM.PlainStyle
    , GM.ooptLineSeparator  = GM.LineSeparator "\0"
    , GM.ooptLinePrefix     = Nothing
    }

    }

cdAndDo :: FilePath -> IO a -> IO a
cdAndDo path fn = do
  old <- getCurrentDirectory
  bracket (setCurrentDirectory path) (\_ -> setCurrentDirectory old)
          $ const fn


testCommand :: (ToJSON a, Typeable b, ToJSON b, Show b, Eq b) => IdePlugins -> IdeGhcM (IdeResult b) -> CommandId -> a -> IdeResult b -> IO ()
testCommand testPlugins act cmdId arg res = do
  (newApiRes, oldApiRes) <- runIGM testPlugins $ do
    new <- act
    old <- makeRequest cmdId arg
    return (new, old)
  newApiRes `shouldBe` res
  fmap fromDynJSON oldApiRes `shouldBe` fmap Just res

runSingleReq :: ToJSON a => IdePlugins -> CommandId -> a -> IO (IdeResult DynamicJSON)
runSingleReq testPlugins cmdId arg = runIGM testPlugins (makeRequest cmdId arg)

makeRequest :: ToJSON a => CommandId -> a -> IdeGhcM (IdeResult DynamicJSON)
makeRequest cmdId arg = runPluginCommand cmdId (toJSON arg)

runIGM :: IdePlugins -> IdeGhcM a -> IO a
runIGM testPlugins = runIdeGhcM testOptions def (IdeState emptyModuleCache Map.empty testPlugins Map.empty Nothing Nothing)

withFileLogging :: FilePath -> IO a -> IO a
withFileLogging logFile f = do
  let logDir = "./test-logs"
      logPath = logDir </> logFile

  dirExists <- doesDirectoryExist logDir
  unless dirExists $ createDirectory logDir

  exists <- doesFileExist logPath
  when exists $ removeFile logPath

  Core.setupLogger (Just logPath) ["hie"] L.DEBUG

  f

-- ---------------------------------------------------------------------

setupStackFiles :: IO ()
setupStackFiles =
  forM_ files $ \f -> do
    resolver <- readResolver
    writeFile (f ++ "stack.yaml") $ stackFileContents resolver
    removePathForcibly (f ++ ".stack-work")

-- ---------------------------------------------------------------------

files :: [FilePath]
files =
  [  "./test/testdata/"
   , "./test/testdata/gototest/"
   , "./test/testdata/addPackageTest/cabal/"
   , "./test/testdata/addPackageTest/hpack/"
   , "./test/testdata/redundantImportTest/"
   , "./test/testdata/completion/"
   , "./test/testdata/definition/"
  ]

stackYaml :: FilePath
stackYaml =
#if (defined(MIN_VERSION_GLASGOW_HASKELL) && (MIN_VERSION_GLASGOW_HASKELL(8,4,3,0)))
  "stack.yaml"
#elif (defined(MIN_VERSION_GLASGOW_HASKELL) && (MIN_VERSION_GLASGOW_HASKELL(8,4,2,0)))
  "stack-8.4.2.yaml"
#elif (defined(MIN_VERSION_GLASGOW_HASKELL) && (MIN_VERSION_GLASGOW_HASKELL(8,2,2,0)))
  "stack-8.2.2.yaml"
#elif __GLASGOW_HASKELL__ >= 802
  "stack-8.2.1.yaml"
#else
  "stack-8.0.2.yaml"
#endif

-- | The command to execute the version of hie for the current compiler.
-- Make sure to disable the STACK_EXE and GHC_PACKAGE_PATH environment
-- variables or else it messes up -- ghc-mod.
-- We also need to unset STACK_EXE manually inside the tests if they are
-- run with `stack test`
hieCommand :: String
hieCommand = "stack exec --no-stack-exe --no-ghc-package-path --stack-yaml=" ++ stackYaml ++
             " hie -- -d -l test-logs/functional-hie-" ++ stackYaml ++ ".log"

hieCommandVomit :: String
hieCommandVomit = hieCommand ++ " --vomit"

-- |Choose a resolver based on the current compiler, otherwise HaRe/ghc-mod will
-- not be able to load the files
readResolver :: IO String
readResolver = readResolverFrom stackYaml

newtype StackResolver = StackResolver String

instance FromJSON StackResolver where
  parseJSON (Object x) = StackResolver <$> x .: pack "resolver"
  parseJSON invalid = typeMismatch "StackResolver" invalid

readResolverFrom :: FilePath -> IO String
readResolverFrom yamlPath = do
  result <- decodeFileEither yamlPath
  case result of
    Left err -> error $ yamlPath ++ " parsing failed: " ++ show err
    Right (StackResolver res) -> return res

-- ---------------------------------------------------------------------

stackFileContents :: String -> String
stackFileContents resolver = unlines
  [ "# WARNING: THIS FILE IS AUTOGENERATED IN test/Main.hs. IT WILL BE OVERWRITTEN ON EVERY TEST RUN"
  , "resolver: " ++ resolver
  , "packages:"
  , "- '.'"
  , "extra-deps: []"
  , "flags: {}"
  , "extra-package-dbs: []"
  ]
-- ---------------------------------------------------------------------
