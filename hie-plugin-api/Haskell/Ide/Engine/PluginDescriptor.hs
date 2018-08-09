{-# LANGUAGE CPP                  #-}
{-# LANGUAGE OverloadedStrings    #-}
-- | A data structure to define a plugin.
-- Allows description of a plugin and the commands it provides

module Haskell.Ide.Engine.PluginDescriptor
  ( runPluginCommand
  , pluginDescToIdePlugins
  , DynamicJSON
  , dynToJSON
  , fromDynJSON
  , toDynJSON
  ) where

import           Data.Aeson
import           Data.List
import qualified Data.Map                        as Map
#if __GLASGOW_HASKELL__ < 804
import           Data.Monoid
#endif
import qualified Data.Text                       as T
import qualified Data.ConstrainedDynamic         as CD
import           Data.Typeable
import           Haskell.Ide.Engine.MonadTypes
import           Control.Lens

pluginDescToIdePlugins :: [(PluginId,PluginDescriptor)] -> IdePlugins
pluginDescToIdePlugins plugins = IdePlugins $ Map.fromList plugins

type DynamicJSON = CD.ConstrainedDynamic ToJSON

dynToJSON :: DynamicJSON -> Value
dynToJSON x = CD.applyClassFn x toJSON

fromDynJSON :: (Typeable a, ToJSON a) => DynamicJSON -> Maybe a
fromDynJSON = CD.fromDynamic

toDynJSON :: (Typeable a, ToJSON a) => a -> DynamicJSON
toDynJSON = CD.toDyn

-- | Runs a plugin command given a PluginId, CommandName and
-- arguments in the form of a JSON object.
runPluginCommand :: PluginId -> CommandName -> Value -> IDErring IdeGhcM DynamicJSON
runPluginCommand p com arg = do
  IdePlugins m <- liftIde $ use idePlugins
  PluginDescriptor { pluginCommands = xs } <- case Map.lookup p m of
    Nothing -> ideError UnknownPlugin ("Plugin " <> p <> " doesn't exist") Null
    Just x -> return x
  PluginCommand _ _ (CmdSync f) <- case find ((com ==) . commandName) xs of
    Nothing -> ideError UnknownCommand ("Command " <> com <> " isn't defined for plugin " <> p <> ". Legal commands are: " <> T.pack(show $ map commandName xs)) Null
    Just x -> return x
  a <- case fromJSON arg of
    Error err -> ideError ParameterError ("error while parsing args for " <> com <> " in plugin " <> p <> ": " <> T.pack err) Null
    Success x -> return x
  toDynJSON <$> f a
